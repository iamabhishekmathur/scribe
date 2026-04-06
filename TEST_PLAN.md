# Scribe — Comprehensive Test Plan

**Derived from:** Project spec, agentic-qa-skill.md principles
**Approach:** Spec-driven — every test traces back to a requirement

---

## Feature Map (from spec)

| ID | Feature | Status |
|----|---------|--------|
| F1 | Menu bar app + system tray icon | Built |
| F2 | Settings UI (General, Transcription, LLM, Permissions) | Built |
| F3 | SQLite storage (GRDB) + data models | Built |
| F4 | Full-text search (FTS5) | Built |
| F5 | JSON export for MCP/portability | Built |
| F6 | Keychain credential storage | Built |
| F7 | Permission management | Built |
| F8 | Audio capture (AVAudioEngine / ScreenCaptureKit) | Not built |
| F9 | Real-time transcription (Deepgram/AssemblyAI/Whisper) | Not built |
| F10 | LLM summarization (Claude/GPT/Ollama/Custom) | Not built |
| F11 | Meeting detection (calendar + process + audio) | Not built |
| F12 | Floating overlay during meetings | Not built |
| F13 | Full meeting list/detail window | Stub only |
| F14 | Google OAuth + calendar integration | Not built |
| F15 | MCP server (local HTTP for tool access) | Not built |
| F16 | Screen context capture (OCR during screen share) | Not built |
| F17 | Onboarding flow | Not built |
| F18 | Auto JSON export on meeting complete | Not built |

---

## Test Suites by Feature

### TS-01: Audio Capture Engine (F8)

**Spec requirement:** Capture system audio using ScreenCaptureKit and/or microphone via AVAudioEngine. Must be invisible to participants.

| Test ID | Test Case | Type | Priority |
|---------|-----------|------|----------|
| AC-001 | Audio engine initializes without crash when microphone permission granted | Unit | P0 |
| AC-002 | Audio engine fails gracefully when microphone permission denied | Unit | P0 |
| AC-003 | Audio capture starts and produces non-empty audio buffers | Integration | P0 |
| AC-004 | Audio capture stops cleanly without resource leaks | Integration | P0 |
| AC-005 | Audio level meter updates in real-time during capture | Integration | P1 |
| AC-006 | System audio capture via ScreenCaptureKit works | Integration | P0 |
| AC-007 | ScreenCaptureKit fails gracefully without screen recording permission | Unit | P0 |
| AC-008 | Audio capture survives app going to background | Integration | P1 |
| AC-009 | Audio capture handles no audio input (silence) without crashing | Edge | P1 |
| AC-010 | Audio capture handles very loud input without clipping/crash | Edge | P2 |
| AC-011 | Audio format is compatible with all transcription providers (PCM 16kHz/16bit or similar) | Integration | P0 |
| AC-012 | Audio capture does not appear in system audio routing (invisible to participants) | Manual | P0 |
| AC-013 | Audio capture does not appear in screen sharing indicators | Manual | P0 |
| AC-014 | Memory usage stays bounded during long recordings (2+ hours) | Performance | P1 |
| AC-015 | Audio buffer handoff to transcription is non-blocking | Performance | P1 |

### TS-02: Real-time Transcription (F9)

**Spec requirement:** Stream audio to user-configured cloud transcription provider. Support Deepgram, AssemblyAI, OpenAI Whisper.

| Test ID | Test Case | Type | Priority |
|---------|-----------|------|----------|
| TR-001 | Deepgram WebSocket connection establishes with valid API key | Integration | P0 |
| TR-002 | Deepgram returns transcript segments for streamed audio | Integration | P0 |
| TR-003 | Deepgram connection fails gracefully with invalid API key | Unit | P0 |
| TR-004 | Deepgram interim results marked as non-final, final results as final | Integration | P1 |
| TR-005 | AssemblyAI WebSocket connection establishes with valid API key | Integration | P0 |
| TR-006 | AssemblyAI returns transcript segments for streamed audio | Integration | P0 |
| TR-007 | AssemblyAI connection fails gracefully with invalid API key | Unit | P0 |
| TR-008 | OpenAI Whisper API call succeeds with valid API key | Integration | P0 |
| TR-009 | OpenAI Whisper returns transcript for audio chunk | Integration | P0 |
| TR-010 | OpenAI Whisper fails gracefully with invalid API key | Unit | P0 |
| TR-011 | Transcript segments are persisted to DB as they arrive | Integration | P0 |
| TR-012 | Speaker diarization labels are preserved when provider supports it | Integration | P1 |
| TR-013 | Confidence scores are stored when provider returns them | Integration | P2 |
| TR-014 | Switching provider mid-session is not possible (locked during recording) | UI | P1 |
| TR-015 | Network disconnection during transcription shows error, buffers audio | Edge | P0 |
| TR-016 | Network reconnection resumes transcription without data loss | Edge | P1 |
| TR-017 | Very long meeting (2+ hours) doesn't accumulate unbounded memory | Performance | P1 |
| TR-018 | Transcription handles non-English audio (if provider supports it) | Edge | P2 |
| TR-019 | Empty/silent audio doesn't produce garbage transcripts | Edge | P1 |
| TR-020 | Connection test button in Settings actually validates the API key | Integration | P1 |

### TS-03: LLM Summarization (F10)

**Spec requirement:** Send transcript + user notes to user-configured LLM for summarization. Support Claude, GPT, Ollama, any OpenAI-compatible endpoint.

| Test ID | Test Case | Type | Priority |
|---------|-----------|------|----------|
| LLM-001 | Claude API call succeeds with valid API key and transcript | Integration | P0 |
| LLM-002 | Claude API call fails gracefully with invalid key | Unit | P0 |
| LLM-003 | OpenAI API call succeeds with valid key | Integration | P0 |
| LLM-004 | OpenAI API call fails gracefully with invalid key | Unit | P0 |
| LLM-005 | Ollama local API call succeeds when Ollama is running | Integration | P0 |
| LLM-006 | Ollama fails gracefully when not running (connection refused) | Unit | P0 |
| LLM-007 | Custom OpenAI-compatible endpoint works with valid config | Integration | P0 |
| LLM-008 | Custom endpoint fails gracefully with bad URL | Unit | P0 |
| LLM-009 | Summary is generated with type "full" | Integration | P0 |
| LLM-010 | Action items summary is generated with type "action_items" | Integration | P0 |
| LLM-011 | Decisions summary is generated with type "decisions" | Integration | P1 |
| LLM-012 | Topics summary is generated with type "topics" | Integration | P1 |
| LLM-013 | Follow-ups summary is generated with type "follow_ups" | Integration | P1 |
| LLM-014 | All summary types are persisted to AISummary table with correct modelUsed | Integration | P0 |
| LLM-015 | Summarization includes user notes as context, not just transcript | Integration | P0 |
| LLM-016 | Summarization handles empty transcript gracefully | Edge | P1 |
| LLM-017 | Summarization handles very long transcript (truncation/chunking) | Edge | P1 |
| LLM-018 | Summarization prompt does not leak PII beyond what user typed | Security | P1 |
| LLM-019 | API timeout is handled (no infinite hang) | Edge | P0 |
| LLM-020 | Rate limiting response (429) is handled with backoff | Edge | P1 |
| LLM-021 | Summarization triggered automatically on recording stop | Integration | P0 |
| LLM-022 | User can re-trigger summarization for a completed meeting | UI | P2 |

### TS-04: Meeting Detection (F11)

**Spec requirement:** Auto-detect meetings via calendar events, process monitoring (Zoom, Meet, Teams), and audio activity.

| Test ID | Test Case | Type | Priority |
|---------|-----------|------|----------|
| MD-001 | Calendar event starting triggers meeting detection notification | Integration | P0 |
| MD-002 | Calendar event with video URL is detected as meeting (Zoom, Meet, Teams) | Integration | P0 |
| MD-003 | Calendar event without video URL is not auto-detected | Unit | P1 |
| MD-004 | Zoom process launch is detected | Integration | P1 |
| MD-005 | Google Meet browser tab is detected (if possible via accessibility) | Integration | P2 |
| MD-006 | Microsoft Teams process launch is detected | Integration | P1 |
| MD-007 | Audio activity spike triggers meeting suggestion | Integration | P2 |
| MD-008 | Auto-start recording works when enabled in settings | Integration | P0 |
| MD-009 | Auto-start does NOT trigger when disabled in settings | Integration | P0 |
| MD-010 | Meeting detection respects user's calendar selection | Integration | P1 |
| MD-011 | Multiple concurrent calendar events handled correctly | Edge | P1 |
| MD-012 | Calendar sync updates when events change | Integration | P1 |
| MD-013 | Meeting end detected when video app closes | Integration | P1 |
| MD-014 | Meeting detection doesn't drain battery (polling interval) | Performance | P1 |

### TS-05: Floating Overlay (F12)

**Spec requirement:** Floating overlay during meetings showing recording status, quick notes, timestamps. Must be discrete during screen sharing.

| Test ID | Test Case | Type | Priority |
|---------|-----------|------|----------|
| OV-001 | Overlay appears when recording starts and overlay enabled in settings | UI | P0 |
| OV-002 | Overlay does not appear when disabled in settings | UI | P0 |
| OV-003 | Overlay shows recording time elapsed | UI | P0 |
| OV-004 | Overlay allows typing quick notes | UI | P0 |
| OV-005 | Notes typed in overlay are persisted as UserNote with timestamp | Integration | P0 |
| OV-006 | Overlay is draggable to any screen position | UI | P1 |
| OV-007 | Overlay stays on top of other windows | UI | P1 |
| OV-008 | Overlay is not captured by screen sharing (using NSWindow.Level and sharing policies) | Manual/UI | P0 |
| OV-009 | Overlay has minimal footprint (small, semi-transparent) | UI | P1 |
| OV-010 | Overlay disappears when recording stops | UI | P0 |
| OV-011 | Overlay stop button works same as menu bar stop | Integration | P0 |
| OV-012 | Overlay handles multi-monitor setup | UI | P1 |
| OV-013 | Keyboard shortcut toggles overlay visibility | UI | P2 |

### TS-06: Meeting List & Detail Window (F13)

**Spec requirement:** Full window with meeting list (sidebar) and meeting detail (transcript, notes, summaries).

| Test ID | Test Case | Type | Priority |
|---------|-----------|------|----------|
| MW-001 | Meeting list shows all meetings sorted by date descending | UI | P0 |
| MW-002 | Meeting list supports pagination/infinite scroll for many meetings | UI | P1 |
| MW-003 | Selecting a meeting shows its detail view | UI | P0 |
| MW-004 | Detail view shows transcript with speaker labels and timestamps | UI | P0 |
| MW-005 | Detail view shows user notes | UI | P0 |
| MW-006 | Detail view shows AI summaries (all types) | UI | P0 |
| MW-007 | Detail view shows screen context captures | UI | P1 |
| MW-008 | Search bar filters meetings by title, transcript, notes content | UI/Integration | P0 |
| MW-009 | Search highlights matching text in results | UI | P2 |
| MW-010 | Meeting can be deleted from list | UI | P0 |
| MW-011 | Delete confirmation dialog prevents accidental deletion | UI | P1 |
| MW-012 | Folders sidebar allows organizing meetings | UI | P1 |
| MW-013 | Drag-and-drop meetings between folders | UI | P2 |
| MW-014 | Empty state shown when no meetings exist | UI | P0 |
| MW-015 | Meeting detail shows duration, participants, meeting URL | UI | P1 |
| MW-016 | Export button triggers JSON export for selected meeting | UI | P1 |
| MW-017 | Window minimum size is enforced (700x500) | UI | P1 |
| MW-018 | Edit meeting title inline | UI | P2 |
| MW-019 | Copy transcript to clipboard | UI | P1 |

### TS-07: Google OAuth & Calendar Integration (F14)

**Spec requirement:** Google OAuth via browser redirect or gcloud CLI for calendar access.

| Test ID | Test Case | Type | Priority |
|---------|-----------|------|----------|
| GC-001 | OAuth flow opens browser for Google sign-in | Integration | P0 |
| GC-002 | OAuth callback captures and stores tokens in Keychain | Integration | P0 |
| GC-003 | Calendar events are fetched for today and upcoming | Integration | P0 |
| GC-004 | Token refresh works when access token expires | Integration | P0 |
| GC-005 | OAuth fails gracefully when user denies permission | Unit | P0 |
| GC-006 | gcloud CLI fallback works when installed | Integration | P1 |
| GC-007 | Calendar events include video meeting URLs | Integration | P0 |
| GC-008 | Calendar events include participant list | Integration | P1 |
| GC-009 | Calendar sync runs periodically in background | Integration | P1 |
| GC-010 | Signing out clears OAuth tokens from Keychain | Integration | P0 |
| GC-011 | No Google data is sent to any third party (privacy) | Security | P0 |

### TS-08: MCP Server (F15)

**Spec requirement:** Local HTTP server exposing meeting data via MCP protocol for AI tool access.

| Test ID | Test Case | Type | Priority |
|---------|-----------|------|----------|
| MCP-001 | MCP server starts on configurable local port | Integration | P0 |
| MCP-002 | MCP server serves meeting list via tool | Integration | P0 |
| MCP-003 | MCP server serves meeting detail (transcript, notes, summaries) | Integration | P0 |
| MCP-004 | MCP server serves search results | Integration | P0 |
| MCP-005 | MCP server only accepts localhost connections | Security | P0 |
| MCP-006 | MCP server handles concurrent requests | Performance | P1 |
| MCP-007 | MCP server returns proper JSON-RPC responses | Integration | P0 |
| MCP-008 | MCP server returns error for invalid tool calls | Integration | P0 |
| MCP-009 | MCP server auto-starts with app | Integration | P1 |
| MCP-010 | MCP server port conflict handled gracefully | Edge | P1 |
| MCP-011 | JSON export files are accessible to MCP clients | Integration | P1 |

### TS-09: Screen Context Capture (F16)

**Spec requirement:** Capture screen text via OCR during screen sharing at configurable intervals.

| Test ID | Test Case | Type | Priority |
|---------|-----------|------|----------|
| SC-001 | Screen capture triggers at configured interval (default 15s) | Integration | P0 |
| SC-002 | OCR extracts text from captured screen image | Integration | P0 |
| SC-003 | Extracted text is saved as ScreenContext with timestamp | Integration | P0 |
| SC-004 | Screen capture respects enabled/disabled setting | Integration | P0 |
| SC-005 | Screen capture interval is configurable and validated (min 5s) | Unit | P0 |
| SC-006 | Screen capture requires screen recording permission | Unit | P0 |
| SC-007 | Screen capture stops when recording stops | Integration | P0 |
| SC-008 | OCR handles screens with no text (blank/image-heavy) | Edge | P1 |
| SC-009 | OCR handles multiple monitors (captures active/shared screen) | Edge | P1 |
| SC-010 | Screen capture does not capture the Scribe overlay | Edge | P1 |
| SC-011 | Screen context is included in LLM summarization prompt | Integration | P1 |

### TS-10: Onboarding Flow (F17)

**Spec requirement:** First-run onboarding to configure permissions, API keys, and preferences.

| Test ID | Test Case | Type | Priority |
|---------|-----------|------|----------|
| OB-001 | Onboarding shown on first launch (hasCompletedOnboarding = false) | UI | P0 |
| OB-002 | Onboarding not shown after completion | UI | P0 |
| OB-003 | Onboarding requests microphone permission | UI | P0 |
| OB-004 | Onboarding requests screen recording permission | UI | P0 |
| OB-005 | Onboarding requests calendar permission | UI | P1 |
| OB-006 | Onboarding allows configuring transcription provider + API key | UI | P0 |
| OB-007 | Onboarding allows configuring LLM provider + API key | UI | P0 |
| OB-008 | Onboarding can be skipped and completed later via Settings | UI | P1 |
| OB-009 | Onboarding validates API keys before proceeding | UI | P1 |
| OB-010 | hasCompletedOnboarding set to true on completion | Integration | P0 |

### TS-11: End-to-End Recording Flow

**Spec requirement:** Full lifecycle: detect meeting → start recording → capture audio → transcribe → user takes notes → stop recording → summarize → view in app.

| Test ID | Test Case | Type | Priority |
|---------|-----------|------|----------|
| E2E-001 | Manual start: click "Start Recording" → audio captured → transcript appears | E2E | P0 |
| E2E-002 | Manual stop: click "Stop Recording" → transcription ends → summarization triggers → meeting shows as "complete" | E2E | P0 |
| E2E-003 | Full flow: start → record 2 minutes → add notes via overlay → stop → summaries generated → viewable in main window | E2E | P0 |
| E2E-004 | Auto-detect flow: calendar event starts → notification → user confirms → recording starts | E2E | P0 |
| E2E-005 | Export after meeting: completed meeting exports as valid JSON with all data | E2E | P0 |
| E2E-006 | Search after meeting: transcript text searchable via FTS5 | E2E | P0 |
| E2E-007 | MCP access after meeting: MCP server returns meeting data to tool call | E2E | P1 |
| E2E-008 | Long meeting: 1-hour recording completes without memory leak or crash | E2E/Perf | P0 |
| E2E-009 | Multiple meetings: second meeting after first completes, both viewable | E2E | P0 |
| E2E-010 | Quit during recording: meeting saved in recoverable state on next launch | E2E | P1 |
| E2E-011 | Network loss during recording: audio still captured, transcript buffered/retried | E2E | P0 |

### TS-12: Security & Privacy

**Spec requirement:** Privacy-focused. Data stays local. No data sent to anyone except user-configured providers.

| Test ID | Test Case | Type | Priority |
|---------|-----------|------|----------|
| SEC-001 | API keys stored in Keychain, never in UserDefaults or plain files | Security | P0 |
| SEC-002 | No API keys in log output | Security | P0 |
| SEC-003 | No PII in log output | Security | P0 |
| SEC-004 | MCP server binds to localhost only (127.0.0.1) | Security | P0 |
| SEC-005 | Audio data not persisted to disk (only transcript text) | Security | P0 |
| SEC-006 | No telemetry or analytics data sent anywhere | Security | P0 |
| SEC-007 | Google OAuth tokens stored in Keychain | Security | P0 |
| SEC-008 | SQLite database is only readable by current user (file permissions) | Security | P1 |
| SEC-009 | JSON exports don't contain API keys or tokens | Security | P0 |
| SEC-010 | Screen context OCR text does not capture sensitive overlays (passwords, etc.) | Security | P2 |

### TS-13: Performance & Resource Usage

**Spec requirement:** Small binary (~9-13MB), fast launch (<0.5s), battery efficient.

| Test ID | Test Case | Type | Priority |
|---------|-----------|------|----------|
| PERF-001 | App binary size under 15MB | Build | P1 |
| PERF-002 | App launches in under 0.5 seconds | Performance | P0 |
| PERF-003 | Idle CPU usage under 1% | Performance | P0 |
| PERF-004 | Recording CPU usage under 10% | Performance | P0 |
| PERF-005 | Memory usage under 100MB during recording | Performance | P1 |
| PERF-006 | Memory usage under 50MB when idle | Performance | P1 |
| PERF-007 | Database size scales linearly with meeting count (no bloat) | Performance | P2 |
| PERF-008 | FTS5 search returns results in under 100ms for 1000+ meetings | Performance | P1 |
| PERF-009 | JSON export completes in under 2s for large meeting | Performance | P2 |
| PERF-010 | Menu bar icon renders correctly in light and dark mode | UI | P1 |

### TS-14: App Lifecycle & Error Recovery

| Test ID | Test Case | Type | Priority |
|---------|-----------|------|----------|
| LC-001 | App starts as menu bar item (no Dock icon) | UI | P0 |
| LC-002 | App stays running when last window closed | Unit | P0 |
| LC-003 | App recovers from database corruption (migration reset in debug) | Edge | P1 |
| LC-004 | Stale "recording" meetings cleaned up on app launch | Integration | P1 |
| LC-005 | App handles disk full gracefully during recording | Edge | P1 |
| LC-006 | Settings persist across app restarts | Integration | P0 |
| LC-007 | Database migrations run correctly on version upgrade | Integration | P0 |
| LC-008 | Multiple app instances prevented (single instance enforcement) | UI | P1 |

---

## Test Data Fixtures (per agentic-qa-skill Phase 4)

### Realistic Meeting Data
- **Short standup**: 5 minutes, 2 speakers, 15 transcript segments, no screen context
- **Long planning session**: 90 minutes, 6 speakers, 500+ segments, user notes, screen contexts
- **One-on-one**: 30 minutes, 2 speakers, 100 segments, action items
- **Presentation**: 45 minutes, 1 primary speaker, heavy screen context, slides text

### Edge Case Data
- **Empty meeting**: Started and immediately stopped, no audio
- **Silent meeting**: 10 minutes, no speech detected
- **Overlapping speakers**: Rapid turn-taking, speaker changes every 2-3 seconds
- **Non-English**: Japanese, Arabic, mixed-language meeting
- **Noisy environment**: Background noise, music, typing sounds
- **Unicode heavy**: Emoji in notes, CJK characters in transcript, RTL text
- **Very long text**: Single transcript segment >10KB
- **Special characters**: SQL injection strings, XSS payloads, null bytes in meeting titles

### Volume Data
- **Scale test set**: 1000 meetings, 500K transcript segments, 10K notes
- **Single massive meeting**: 50K transcript segments (6+ hour meeting)

---

## Priority Matrix

| Priority | Count | Criteria |
|----------|-------|----------|
| P0 | ~60 | Core functionality, must work for app to be useful |
| P1 | ~50 | Important for good UX, should work for release |
| P2 | ~20 | Nice to have, can ship without |

---

## Implementation Status

Tests written and passing:
- TS-03 partial (data models, DB CRUD, FTS, export) — 87 tests
- TS-12 partial (Keychain key storage tests)
- TS-13 partial (app lifecycle: window close behavior)
- TS-14 partial (settings persistence, migrations)

Tests to write as features are built:
- TS-01 through TS-02 (audio + transcription) — requires real audio infrastructure
- TS-03 through TS-04 (LLM + meeting detection) — requires API clients
- TS-05 through TS-07 (overlay, main window, OAuth) — requires UI implementation
- TS-08 (MCP server) — requires HTTP server
- TS-09 through TS-11 (screen capture, onboarding, E2E) — requires full integration
