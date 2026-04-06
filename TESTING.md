# Scribe — Feature & Architecture Reference for End-to-End Testing

## Overview

Scribe is an open-source AI meeting notetaker for macOS. It captures meeting audio invisibly (no bot joins), transcribes via configurable cloud providers, and uses configurable LLMs for summarization and real-time chat. All data is stored locally in SQLite.

**Platform:** macOS 14+ (Sonoma)
**Runtime:** Swift 6.0, SwiftUI + AppKit
**Binary:** ~12MB debug
**Tests:** 193 unit/integration tests across 35 suites

---

## Architecture

### Targets

| Target | Type | Purpose |
|---|---|---|
| `ScribeApp` | Executable | App entry point, lifecycle, scene management |
| `ScribeCore` | Library | All business logic, data, audio, AI, networking |
| `ScribeUI` | Library | All SwiftUI/AppKit views |
| `ScribeTests` | Test | Unit tests for models, config, enums |
| `ScribeCoreIntegrationTests` | Test | Database CRUD, FTS5, cascade deletes, UUID encoding |

### Dependencies

| Package | Version | Purpose |
|---|---|---|
| GRDB.swift | 7.0.0+ | SQLite ORM, WAL mode, FTS5 full-text search |
| KeychainAccess | 4.2.2+ | Secure API key storage in macOS Keychain |
| Starscream | 4.0.8+ | WebSocket client for Deepgram/AssemblyAI streaming |
| swift-testing | main | Swift Testing framework (test targets only) |

### Apple Frameworks Used

AVFoundation, ScreenCaptureKit, EventKit, UserNotifications, Network (NWListener), AppKit, SwiftUI, CommonCrypto, CoreMedia, Security, Combine

### Concurrency Model

- **Actors:** MeetingStore, SearchIndex, JSONExporter, AudioMixer, VADFilter, AudioCaptureManager, MeetingSession, CalendarDetector, ProcessDetector, AudioActivityDetector, MeetingDetector, SummarizationService, EnrichmentService, ChatService, ScreenContextCapture, GoogleOAuthManager, GoogleCalendarClient, CalendarManager, LocalAPIServer, MCPServer, SpeakerIdentifier
- **@MainActor:** AppState, AppSettings, KeychainManager, PermissionsManager, LLMManager, OverlayWindowController
- **@unchecked Sendable:** MicrophoneCapture, SystemAudioCapture, TranscriptionManager, all LLM/Transcription providers

---

## Database Schema

**Engine:** SQLite via GRDB
**Mode:** WAL (Write-Ahead Logging) for concurrent reads
**Location:** `~/Library/Application Support/Scribe/scribe.sqlite`

### Tables

#### `meetings`
| Column | Type | Constraints |
|---|---|---|
| id | TEXT | PRIMARY KEY |
| title | TEXT | NOT NULL |
| startTime | DATETIME | NOT NULL |
| endTime | DATETIME | |
| duration | DOUBLE | |
| calendarEventId | TEXT | |
| meetingURL | TEXT | |
| participants | TEXT | JSON array of names |
| folderId | TEXT | FK → folders (SET NULL) |
| state | TEXT | NOT NULL, DEFAULT 'recording' |
| createdAt | DATETIME | NOT NULL |
| updatedAt | DATETIME | NOT NULL |

**States:** `idle`, `recording`, `ended`, `processing`, `complete`
**Indexes:** `idx_meetings_startTime`, `idx_meetings_state`

#### `transcript_segments`
| Column | Type | Constraints |
|---|---|---|
| id | TEXT | PRIMARY KEY |
| meetingId | TEXT | NOT NULL, FK → meetings (CASCADE) |
| speaker | TEXT | |
| speakerIndex | INTEGER | |
| text | TEXT | NOT NULL |
| startTime | DOUBLE | NOT NULL |
| endTime | DOUBLE | NOT NULL |
| confidence | DOUBLE | |
| isFinal | BOOLEAN | NOT NULL, DEFAULT true |
| createdAt | DATETIME | NOT NULL |

**Index:** `idx_transcript_meetingId`

#### `user_notes`
| Column | Type | Constraints |
|---|---|---|
| id | TEXT | PRIMARY KEY |
| meetingId | TEXT | NOT NULL, FK → meetings (CASCADE) |
| text | TEXT | NOT NULL |
| enrichedText | TEXT | |
| timestamp | DOUBLE | NOT NULL |
| createdAt | DATETIME | NOT NULL |
| updatedAt | DATETIME | NOT NULL |

**Index:** `idx_notes_meetingId`

#### `ai_summaries`
| Column | Type | Constraints |
|---|---|---|
| id | TEXT | PRIMARY KEY |
| meetingId | TEXT | NOT NULL, FK → meetings (CASCADE) |
| summaryType | TEXT | NOT NULL |
| content | TEXT | NOT NULL |
| modelUsed | TEXT | NOT NULL |
| createdAt | DATETIME | NOT NULL |

**Summary types:** `full`, `action_items`, `decisions`, `topics`, `follow_ups`
**Index:** `idx_summaries_meetingId`

#### `screen_contexts`
| Column | Type | Constraints |
|---|---|---|
| id | TEXT | PRIMARY KEY |
| meetingId | TEXT | NOT NULL, FK → meetings (CASCADE) |
| timestamp | DOUBLE | NOT NULL |
| extractedText | TEXT | NOT NULL |
| sourceDescription | TEXT | |
| createdAt | DATETIME | NOT NULL |

**Index:** `idx_screen_contexts_meetingId`

#### `folders`
| Column | Type | Constraints |
|---|---|---|
| id | TEXT | PRIMARY KEY |
| name | TEXT | NOT NULL |
| parentId | TEXT | FK → folders (SET NULL) |
| sortOrder | INTEGER | NOT NULL, DEFAULT 0 |
| createdAt | DATETIME | NOT NULL |

#### `speaker_profiles`
| Column | Type | Constraints |
|---|---|---|
| id | TEXT | PRIMARY KEY |
| speakerIndex | INTEGER | NOT NULL |
| name | TEXT | NOT NULL |
| meetingId | TEXT | FK → meetings (CASCADE), nullable for global |
| color | TEXT | NOT NULL, DEFAULT '#007AFF' |
| createdAt | DATETIME | NOT NULL |

**Index:** `idx_speaker_profiles_meeting` on (meetingId, speakerIndex)

### FTS5 Virtual Tables (Full-Text Search)

| Virtual Table | Synced With | Indexed Column |
|---|---|---|
| `transcript_fts` | transcript_segments | text |
| `notes_fts` | user_notes | text |
| `summaries_fts` | ai_summaries | content |

### Cascade Delete Behavior

- Deleting a **meeting** cascades to: transcript_segments, user_notes, ai_summaries, screen_contexts, speaker_profiles
- Deleting a **folder** sets meeting.folderId to NULL
- Deleting a parent **folder** sets child folder.parentId to NULL

### UUID Storage

All UUIDs are stored as **uppercase TEXT strings** via custom `encode(to: PersistenceContainer)`. GRDB's default UUID encoding (16-byte BLOB) is overridden. All queries use `.uuidString` for key lookups.

---

## Features by Component

### 1. App Lifecycle & Menu Bar

**Files:** `ScribeApp.swift`, `AppDelegate.swift`, `MenuBarView.swift`, `MenuBarIcon.swift`

| Feature | Description | Test Approach |
|---|---|---|
| Menu bar icon | Dynamic SF Symbol: idle (waveform.circle), recording (waveform.circle.fill), processing (ellipsis.circle) | Verify icon changes with state transitions |
| LSUIElement | App runs as menu bar only, no Dock icon | Verify Info.plist has LSUIElement=true |
| Menu bar dropdown | Shows state-specific UI: idle (start recording), recording (stop + audio level), processing (spinner) | Click through states |
| Manual recording | Start/stop recording from menu bar, creates MeetingRecord in DB | Start → verify DB entry → stop → verify state=ended |
| Database init | Runs migrations on launch | Check ~/Library/Application Support/Scribe/scribe.sqlite exists |
| API server auto-start | LocalAPIServer starts on applicationDidFinishLaunching | `curl localhost:7777/api/status` after launch |
| Notification registration | Meeting detection categories registered at launch | Verify UNNotificationCategory exists |

### 2. Audio Capture Pipeline

**Files:** `MicrophoneCapture.swift`, `SystemAudioCapture.swift`, `AudioMixer.swift`, `VADFilter.swift`, `AudioCaptureManager.swift`

| Feature | Description | Test Approach |
|---|---|---|
| Microphone capture | AVAudioEngine, converts to 16kHz mono PCM Float32 | Start capture → verify AsyncStream yields non-empty buffers |
| System audio capture | ScreenCaptureKit SCStream, audio-only (capturesVideo minimized), excludes own app | Start → play audio from another app → verify buffers |
| Dual output paths | AudioMixer produces: recording stream (full mix) and transcription stream (VAD-filtered) | Feed buffers → verify both streams emit |
| VAD filtering | RMS threshold (0.01) + 300ms hysteresis | Feed silence → verify transcription stream empty; feed speech → verify passes |
| RMS level calculation | MicrophoneCapture.rmsLevel(from:) returns 0.0-1.0 | Create buffer with known samples → verify RMS value |
| AudioCaptureManager | Orchestrates mic + system, publishes isCapturing/audioLevel | startCapture → verify isCapturing=true → stopCapture → verify false |
| Mic-only mode | startMicOnly() for when screen recording permission denied | Start mic-only → verify only mic stream active |
| Self-exclusion | System capture excludes own app bundle ID to prevent feedback | Verify filter configuration excludes Bundle.main.bundleIdentifier |

### 3. Transcription

**Files:** `TranscriptionProvider.swift`, `DeepgramProvider.swift`, `AssemblyAIProvider.swift`, `OpenAIWhisperProvider.swift`, `TranscriptionManager.swift`

| Feature | Description | Test Approach |
|---|---|---|
| Provider protocol | connect(), sendAudio(Data), results: AsyncStream, disconnect() | Mock provider implementing protocol |
| Deepgram WebSocket | wss://api.deepgram.com/v1/listen, linear16/16kHz/mono, diarize=true | With valid key: connect → send audio → verify TranscriptionResult with speaker |
| AssemblyAI WebSocket | wss://api.assemblyai.com/v2/realtime/ws, base64-encoded PCM | With valid key: connect → send audio → verify results |
| OpenAI Whisper REST | Buffers 5s chunks → POST /v1/audio/transcriptions as WAV, verbose_json | With valid key: send audio → wait for chunk threshold → verify result |
| WAV encoding | Float32 PCM → 16-bit PCM → WAV header + data | Verify WAV header bytes: RIFF, fmt chunk, data chunk |
| TranscriptionManager | Bridges audio buffers to provider, Float32→Int16 conversion, writes final segments to DB | Start with mock provider → feed buffers → verify DB segments |
| Auto-reconnect | Provider reconnects on disconnect (via TranscriptionManager restart) | Simulate disconnect → verify reconnection |
| Provider factory | TranscriptionManager.createProvider(type:apiKey:) | Verify correct provider type returned for each TranscriptionProviderType |

### 4. Meeting Detection

**Files:** `MeetingSession.swift`, `MeetingDetector.swift`, `CalendarDetector.swift`, `ProcessDetector.swift`, `AudioActivityDetector.swift`

| Feature | Description | Test Approach |
|---|---|---|
| State machine | idle → detected → recording → ended → processing → complete | Test all valid transitions; verify invalid transitions throw |
| Guard transitions | Invalid state transitions throw MeetingSessionError | Try recording→idle (should throw) |
| CalendarDetector | Polls EventKit every 30s for events within 2 min with video URLs | Create test calendar event with Zoom URL → verify detection |
| Meeting URL extraction | Regex patterns for meet.google.com, zoom.us, teams.microsoft.com, webex.com | Test URL extraction from event notes, location, URL field |
| ProcessDetector | Monitors NSWorkspace for Zoom, Teams, WebEx, browser launches | Launch Zoom → verify DetectedApp emitted |
| Dedicated vs browser | Distinguishes Zoom/Teams (dedicated) from Chrome/Safari (browser) | Verify isDedicatedMeetingApp flag |
| AudioActivityDetector | Triggers when mic + system audio both active >10s | Feed mic RMS >0.01 AND system RMS >0.01 for 10s → verify isMeetingLikeActivity |
| Hysteresis | AudioActivityDetector doesn't flap on brief silence | Active 10s → brief silence → verify still detected |
| MeetingDetector | Combines calendar + process + audio signals | Each signal type → verify DetectionEvent emitted |
| Push notifications | UNNotificationRequest with MEETING_DETECTED category | Verify notification content and actions |
| Notification actions | START_RECORDING (foreground) and DISMISS (destructive) | Verify category registered with correct actions |

### 5. Core UI

**Files:** `FloatingOverlayWindow.swift`, `OverlayContentView.swift`, `LiveTranscriptView.swift`, `NoteInputView.swift`, `AIChatView.swift`, `MainWindowPlaceholder.swift`, `MeetingListView.swift`, `MeetingDetailView.swift`, `SearchView.swift`, `SettingsView.swift`

| Feature | Description | Test Approach |
|---|---|---|
| Floating overlay | NSPanel, nonactivatingPanel, level=.floating, sharingType=.none | Show overlay → verify doesn't steal focus; share screen → verify hidden |
| Overlay tabs | Transcript / Notes / AI Chat segmented control | Switch tabs → verify correct content |
| Live transcript | Polls DB every 1s, auto-scroll with speaker colors | During recording → verify new segments appear; verify auto-scroll |
| Speaker colors | 8-color palette indexed by speakerIndex | Verify color consistency per speaker |
| Note input | Text field + submit, saves UserNote with timestamp to DB | Type note → submit → verify in DB with timestamp |
| AI chat quick actions | "What did I miss?", "What are they asking?", "Action items", "Key decisions" | Tap each → verify question sent |
| 3-column main window | NavigationSplitView: sidebar (All Meetings / Search) | list | detail | Verify all three columns render |
| Meeting list | Sorted by startTime desc, state badges, swipe-to-delete | Create meetings → verify order; delete → verify removed |
| Meeting detail | 4 tabs: Summary / Transcript / Notes / Chat | Load meeting → switch tabs → verify content |
| Transcript speaker filter | Filter chips by speaker name | Click speaker filter → verify only that speaker's segments shown |
| Full-text search | FTS5 search across transcripts, notes, summaries | Insert data → search → verify results with correct source badges |
| Settings — General | Auto-detect, auto-start, overlay toggle, screen context interval | Toggle each → verify persisted in UserDefaults |
| Settings — Transcription | Provider picker + API key SecureField + test connection | Select provider → enter key → save → verify in Keychain |
| Settings — LLM | Provider picker, Claude/OpenAI key, Ollama endpoint/model, custom endpoint | Select each provider → verify correct fields shown |
| Settings — Permissions | Status for mic, screen recording, calendar, notifications + request buttons | Verify status reflects actual permissions; click request |

### 6. AI Features

**Files:** `LLMProvider.swift`, `ClaudeProvider.swift`, `OpenAIProvider.swift`, `OllamaProvider.swift`, `LLMManager.swift`, `SummarizationService.swift`, `EnrichmentService.swift`, `ChatService.swift`, `ScreenContextCapture.swift`

| Feature | Description | Test Approach |
|---|---|---|
| LLM protocol | complete(messages:), stream(messages:), completeWithImage for vision | Mock provider → verify protocol methods called |
| Claude provider | POST api.anthropic.com/v1/messages, x-api-key header, anthropic-version 2023-06-01 | With valid key: send message → verify response parsed |
| Claude vision | Multimodal content with base64 image + text | Send image + prompt → verify extracted text |
| OpenAI provider | POST /v1/chat/completions, Bearer token, configurable endpoint | With valid key: send message → verify response |
| OpenAI vision | image_url content type with base64 data URI | Send image + prompt → verify response |
| Ollama provider | POST /api/chat on localhost:11434, stream=false, 120s timeout | With running Ollama: send message → verify response |
| Custom provider | OpenAI-compatible with custom endpoint/model/key | Configure custom endpoint → verify request sent there |
| LLM manager | Creates provider from AppSettings + KeychainManager, refresh() on settings change | Change LLM setting → refresh → verify new provider type |
| Post-meeting summary | Generates 3 summaries: full, action_items, decisions | Complete meeting with transcript → trigger summarize → verify 3 AISummary records |
| Summary with screen context | Includes screen_contexts extracted text in summary prompt | Add screen contexts → summarize → verify context referenced |
| Note enrichment | Finds transcript segments within 60s window of note timestamp | Add note at timestamp → enrich → verify enrichedText populated |
| Batch enrichment | enrichAllNotes processes all un-enriched notes for a meeting | Add multiple notes → enrichAll → verify all enrichedText non-nil |
| Real-time chat | Rolling context window (last 100 segments) + chat history (last 10 exchanges) | Start chat → ask question → verify response uses transcript context |
| Chat with screen context | Includes last 5 screen contexts in chat prompt | Add screen context → ask "what's on screen?" → verify response |
| Quick actions | Pre-built prompts: "What did I miss?", "What are they asking?", etc. | Each action → verify correct prompt sent to LLM |
| Screen context capture | ScreenCaptureKit screenshot every N seconds → Vision LLM → text extraction | During screen share: verify ScreenContext records in DB |
| Capture interval | Configurable via screenContextInterval (default 15s) | Set to 5s → verify captures every ~5s |
| Image not stored | Only extractedText saved, screenshot discarded after LLM processing | Verify no image files in app support directory |

### 7. Calendar Integration

**Files:** `GoogleOAuthManager.swift`, `GoogleCalendarClient.swift`, `CalendarManager.swift`

| Feature | Description | Test Approach |
|---|---|---|
| Google OAuth PKCE | Browser consent → local callback server (port 8089) → code exchange | Trigger auth → verify browser opens → complete flow → verify tokens |
| Code verifier/challenge | SHA256 code challenge from random verifier, base64url encoded | Verify challenge derivation is deterministic for same verifier |
| Token refresh | POST oauth2.googleapis.com/token with refresh_token grant | With valid refresh token → verify new access token returned |
| Token expiry | GoogleTokens.isExpired checks Date() >= expiresAt | Create token with past expiry → verify isExpired=true |
| Keychain token storage | Access/refresh tokens stored in Keychain | After auth → verify tokens in Keychain keys |
| Google Calendar events | GET /calendar/v3/calendars/primary/events with timeMin/timeMax | With valid token → verify events returned |
| Conference data parsing | Extracts video entryPoint URI from conferenceData | Event with Meet/Zoom conference → verify meetingURL extracted |
| Fallback URL extraction | Regex search in event location and description fields | Event with Zoom URL in description → verify extracted |
| EventKit fallback | Local calendar events via EKEventStore.events(matching:) | Create local event → verify returned by CalendarManager |
| Deduplication | Matches by title + startTime within 5 min window | Same event in Google + EventKit → verify single result |
| Unified interface | CalendarManager.getUpcomingMeetings merges Google + EventKit | Both sources → verify merged, sorted by startDate |

### 8. Local API Server

**File:** `LocalAPIServer.swift`

**Base URL:** `http://localhost:7777`

| Endpoint | Method | Description | Test Approach |
|---|---|---|---|
| `/api/status` | GET | Health check | `curl localhost:7777/api/status` → `{"status":"running","version":"0.1.0"}` |
| `/api/meetings` | GET | List meetings | Create meetings → GET → verify JSON array with id, title, startTime, state |
| `/api/meetings/{id}` | GET | Get meeting | Create meeting → GET by UUID → verify all fields |
| `/api/meetings/{id}` | DELETE | Delete meeting | Create → DELETE → GET → verify 404 |
| `/api/meetings/{id}/transcript` | GET | Get transcript | Add segments → GET → verify array with text, speaker, startTime |
| `/api/meetings/{id}/summary` | GET | Get summaries | Add summaries → GET → verify array with type, content, model |
| `/api/meetings/{id}/notes` | GET | Get notes | Add notes → GET → verify array with text, enrichedText, timestamp |
| `/api/search?q=query` | GET | Full-text search | Add data → search → verify results with meetingId, snippet, source |
| Missing `q` param | GET /api/search | Error handling | Verify 400 response |
| Invalid meeting ID | GET /api/meetings/invalid | Error handling | Verify 404 response |
| Unknown route | GET /api/foo | 404 handling | Verify 404 JSON error |

**Response format:** All responses are JSON with `Content-Type: application/json` and `Access-Control-Allow-Origin: *`.

### 9. MCP Server

**File:** `MCPServer.swift`

| Tool | Input | Output | Test Approach |
|---|---|---|---|
| `scribe_list_meetings` | `{limit?: int}` | Array of meetings (id, title, state, startTime, duration) | Call with limit=5 → verify ≤5 results |
| `scribe_get_meeting` | `{meetingId: string}` | Meeting + transcript + notes + summaries | Create full meeting → call → verify all sections |
| `scribe_search` | `{query: string}` | Array of results (meetingId, meetingTitle, snippet, source) | Add data → search → verify matches |
| `scribe_current_status` | `{}` | `{status, version}` | Call → verify status and version fields |
| Unknown tool | `{name: "invalid"}` | Error response | Call invalid tool → verify error message |

### 10. Speaker Diarization

**Files:** `SpeakerIdentifier.swift` (+ SpeakerProfile model)

| Feature | Description | Test Approach |
|---|---|---|
| Default names | "Speaker 0", "Speaker 1", etc. | Query displayName with no profile → verify default |
| Rename speaker | Per-meeting or global profile | Rename "Speaker 0" → "Alice" → verify displayName returns "Alice" |
| Meeting-specific profiles | meetingId-scoped names override globals | Global "Speaker 0"="Bob", meeting-specific "Speaker 0"="Alice" → verify "Alice" for that meeting |
| Speaker colors | 8-color palette: blue, green, orange, purple, pink, teal, indigo, mint | Verify color(speakerIndex: 0) returns "#007AFF" |
| Color cycling | Colors cycle after index 7 | Verify color(speakerIndex: 8) == color(speakerIndex: 0) |
| Profile persistence | Stored in speaker_profiles table | Rename → restart app → verify name persists |

### 11. Onboarding

**File:** `OnboardingView.swift`

| Step | Content | Test Approach |
|---|---|---|
| Welcome | App logo, description, "All data stays on your Mac" | Verify text content renders |
| Permissions | 4 permission rows with Grant/Granted status | Grant mic → verify checkmark; verify each permission button works |
| Transcription | Provider radio group + API key SecureField | Select AssemblyAI → verify key field updates |
| LLM | Provider radio group + provider-specific fields | Select Ollama → verify endpoint/model fields shown |
| Complete | Success message + usage hints | Verify "Get Started" button sets hasCompletedOnboarding=true |
| Progress bar | ProgressView tracks current step | Verify progress increases with each Next tap |
| Back navigation | Back button returns to previous step | Go forward → back → verify correct step |
| Sheet dismissal | Onboarding shown as sheet when hasCompletedOnboarding=false | Set true → verify sheet dismissed |

### 12. JSON Export

**File:** `JSONExporter.swift`

| Feature | Description | Test Approach |
|---|---|---|
| Export location | `~/Library/Application Support/Scribe/exports/{id}.json` | Export → verify file exists at path |
| Export content | MeetingExport: meeting + transcript + notes + summaries + screenContexts + exportedAt | Export → decode JSON → verify all sections |
| ISO8601 dates | All dates encoded as ISO8601 | Verify date strings contain T and Z/+ |
| Pretty printed | JSON output formatted with .prettyPrinted + .sortedKeys | Verify JSON is human-readable |
| Missing meeting | Export non-existent ID → ExportError.meetingNotFound | Verify error thrown |

---

## Configuration Reference

### UserDefaults Keys

| Key | Type | Default | Description |
|---|---|---|---|
| `transcriptionProvider` | String | "Deepgram" | Active transcription provider |
| `llmProvider` | String | "Claude" | Active LLM provider |
| `ollamaModel` | String | "llama3" | Ollama model name |
| `ollamaEndpoint` | String | "http://localhost:11434" | Ollama endpoint |
| `customLLMEndpoint` | String | "" | Custom OpenAI-compatible endpoint |
| `customLLMModel` | String | "" | Custom model name |
| `autoDetectMeetings` | Bool | true | Auto-detect meetings |
| `showOverlayDuringMeetings` | Bool | true | Show floating overlay |
| `autoStartRecording` | Bool | false | Auto-start on detection |
| `hasCompletedOnboarding` | Bool | false | Onboarding done |
| `screenContextEnabled` | Bool | true | Screen context capture |
| `screenContextInterval` | Double | 15.0 | Capture interval (seconds) |
| `googleOAuthClientId` | String | "" | Google OAuth client ID |

### Keychain Keys (service: `com.scribe.app`)

| Key | Raw Value | Used By |
|---|---|---|
| Deepgram API Key | `deepgram_api_key` | DeepgramProvider |
| AssemblyAI API Key | `assemblyai_api_key` | AssemblyAIProvider |
| OpenAI API Key | `openai_api_key` | OpenAIWhisperProvider, OpenAIProvider |
| Claude API Key | `claude_api_key` | ClaudeProvider |
| Google OAuth Token | `google_oauth_token` | GoogleCalendarClient |
| Google OAuth Refresh | `google_oauth_refresh_token` | GoogleOAuthManager |
| Custom LLM API Key | `custom_llm_api_key` | Custom/Ollama providers |

---

## Known Issues (Documented in Tests)

| ID | Description | Severity |
|---|---|---|
| BUG-005 | Ollama and Custom LLM share the same Keychain key slot (`custom_llm_api_key`) | Low — Ollama typically doesn't need a key |
| BUG-007 | `RecordingState` enum missing `ended` and `complete` cases that `MeetingRecord.state` supports | Medium — UI state doesn't map 1:1 to DB state |
| BUG-008 | `screenContextInterval` has no minimum validation — accepts 0 and negative values | Low — would cause rapid-fire captures at 0 |
| — | `AppState` has no guard against invalid transitions (e.g., stop without start) | Low — works correctly in normal flow |
| — | `AISummary.summaryType` accepts any string, not validated against known types | Low — only generated internally |

---

## Test Execution

```bash
# Build
cd Scribe && swift build

# Run all tests (193 tests, 35 suites)
swift test

# Run specific test suite
swift test --filter "MeetingRecordTests"

# Run integration tests only
swift test --filter "ScribeCoreIntegrationTests"
```

### Test Coverage Areas

| Suite | Tests | Covers |
|---|---|---|
| MeetingRecord Model | 12 | Creation, defaults, codable, unicode, timestamps |
| TranscriptSegment Model | 7 | Creation, speakers, confidence, boundaries |
| UserNote Model | 3 | Creation, enriched text, table name |
| AISummary Model | 3 | Summary types, validation gap |
| Folder Model | 4 | Creation, nesting, empty names |
| ScreenContext Model | 3 | Creation, source description |
| MeetingExport Model | 2 | Codable round-trip, empty collections |
| AppState | 7 | State transitions, lifecycle, invalid transitions |
| KeychainManager | 5 | Provider key mapping, collision bug, display names |
| AppSettings | 4 | Defaults, Ollama defaults, providers, interval validation |
| RecordingState Enum | 2 | Raw values, missing states |
| TranscriptionProviderType | 3 | All cases, display values, identifiable |
| LLMProviderType | 2 | All cases, display values |
| Meeting DB CRUD | 9 | Insert, update, delete, cascade, ordering, pagination, FK |
| Transcript Segment DB | 4 | Chronological order, batch insert, FK, unicode |
| FTS5 Search | 5 | Transcript search, notes search, summary search, no results, sync |
| Folder DB | 3 | Nested folders, parent deletion, sort order |
| UUID Encoding | 1 | Verifies text storage via custom encode(to:) |
| Data Integrity | 4 | Duplicate UUID, long text, special characters, concurrency |
| JSON Export Format | 2 | ISO8601 dates, round-trip integrity |
| MeetingSession | varies | State machine transitions (auto-generated) |
| Meeting Detection | varies | Detector integration (auto-generated) |

---

## End-to-End Test Scenarios

### Scenario 1: Manual Recording Flow
1. Launch app → verify menu bar icon (idle state)
2. Click "Start Recording" → verify icon changes to recording
3. Speak for 10 seconds
4. Click "Stop Recording" → verify icon changes to processing → idle
5. Open main window → verify meeting appears in list
6. Click meeting → verify transcript tab shows segments
7. `curl localhost:7777/api/meetings` → verify meeting in response

### Scenario 2: Meeting Detection → Auto-Record
1. Enable autoDetectMeetings in settings
2. Open Zoom → verify push notification "Zoom Opened"
3. Click "Start Recording" on notification → verify recording begins
4. End Zoom call → verify meeting saved

### Scenario 3: Full AI Pipeline
1. Start recording with Deepgram configured
2. Speak for 2 minutes with another participant
3. Add notes during meeting via overlay
4. Stop recording
5. Verify: transcript segments in DB with speaker labels
6. Verify: post-meeting summary generated (full + action_items + decisions)
7. Verify: notes enriched with transcript context
8. Open meeting detail → verify all 4 tabs populated

### Scenario 4: Search Across Meetings
1. Create 3 meetings with distinct transcript content
2. Open Search tab
3. Search for keyword in meeting 2
4. Verify: results show meeting 2 with highlighted snippet
5. Click result → verify navigation to meeting detail

### Scenario 5: API Integration
1. Start app (API server auto-starts)
2. `curl localhost:7777/api/status` → verify running
3. `curl localhost:7777/api/meetings` → verify list
4. `curl localhost:7777/api/meetings/{id}/transcript` → verify segments
5. `curl localhost:7777/api/search?q=keyword` → verify search results
6. `curl -X DELETE localhost:7777/api/meetings/{id}` → verify deleted

### Scenario 6: Screen Context During Meeting
1. Configure Claude or GPT-4 (vision-capable LLM)
2. Start recording
3. Share screen showing a presentation
4. After 15s, verify ScreenContext record in DB with extracted text
5. Ask AI chat "What's on the screen?" → verify response references slide content
6. Stop recording → verify summary includes screen share context

### Scenario 7: Onboarding First Launch
1. Clear hasCompletedOnboarding from UserDefaults
2. Launch app → verify onboarding sheet appears
3. Step through: Welcome → Permissions → Transcription → LLM → Complete
4. Click "Get Started" → verify sheet dismissed, hasCompletedOnboarding=true
5. Relaunch → verify onboarding does NOT appear
