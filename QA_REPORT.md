# Scribe QA Report - Phase 1

**Date:** 2026-04-05
**Scope:** Full codebase review of ScribeCore, ScribeUI, ScribeApp
**Method:** Static analysis + spec-driven test derivation (per agentic-qa-skill.md)

**Test command:**
```bash
# Accept Xcode license first if needed:
sudo xcodebuild -license accept

# Run tests:
swift test -Xlinker -L/Library/Developer/CommandLineTools/Library/Developer/usr/lib -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/usr/lib
```

---

## Executive Summary

Build compiles successfully. Test infrastructure is broken (`swift test` fails - XCTest not found with Command Line Tools). Found **13 bugs/issues** across severity levels. Test coverage is minimal (5 basic model creation tests).

---

## Bugs Found

### CRITICAL

**BUG-001: Database singleton crashes app on init failure**
- **File:** `ScribeCore/Storage/Database.swift:26`
- **Issue:** Uses `fatalError("Failed to create database: \(error)")` in the `init()`. If the Application Support directory is not writable, or disk is full, or SQLite can't be created, the app crashes instantly with no user feedback.
- **Fix:** Make init failable or use a factory method that throws. Show user-facing alert on failure.

**BUG-002: Test infrastructure broken - swift test fails** [FIXED]
- **File:** `Package.swift`, `ScribeTests/ScribeCoreTests.swift`
- **Issue:** `swift test` fails with `error: no such module 'XCTest'` because the active developer directory is Command Line Tools, not Xcode.
- **Fix applied:** Switched to Swift Testing framework via `swift-testing` package dependency. Bumped platform to macOS 14+. Tests now run with: `swift test -Xlinker -L/Library/Developer/CommandLineTools/Library/Developer/usr/lib -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/usr/lib`

**NOTE on UUID storage:** Investigation confirmed GRDB stores UUIDs as text (uppercase) when column type is `.text`. The `MeetingStore` pattern of using `.uuidString` is correct for the current schema. However, best practice is to pass UUID directly (e.g., `Column("meetingId") == meetingId`) to avoid breakage if schema changes.

### HIGH

**BUG-003: Silent error swallowing in recording lifecycle**
- **File:** `ScribeUI/MenuBar/MenuBarView.swift:62-63, 89-92`
- **Issue:** `try?` silently discards all errors when creating/ending/completing meetings. If the database write fails, the meeting is lost with no indication to the user. The AppState shows "recording" but nothing was persisted.
- **Fix:** Catch errors explicitly and show user feedback (alert or status indicator).

**BUG-004: Race condition in stop recording flow**
- **File:** `ScribeUI/MenuBar/MenuBarView.swift:86-98`
- **Issue:** `stopRecording()` immediately sets state to `.processing`, then an async Task runs `endMeeting` + `completeMeeting` + `finishProcessing`. If any of those `try?` calls fail silently, `finishProcessing()` still runs and the meeting state in DB doesn't match AppState. Also, if the user quits during processing, the meeting is left in an inconsistent state.
- **Fix:** Add error handling. Don't call `finishProcessing()` if persistence fails. Consider a recovery mechanism on app launch to clean up stale "recording"/"processing" meetings.

**BUG-005: Ollama and Custom LLM share same Keychain key**
- **File:** `ScribeCore/Config/KeychainManager.swift:63-64`
- **Issue:** Both `.ollama` and `.custom` return `.customLLMAPIKey`. If user configures a Custom LLM API key, then switches to Ollama and back, the key is shared/overwritten. Ollama doesn't typically need an API key anyway.
- **Fix:** Either give Ollama its own key slot (even if rarely used) or don't store/retrieve a key for Ollama.

**BUG-006: @StateObject misuse for singleton**
- **File:** `ScribeUI/MainWindow/SettingsView.swift:7`
- **Issue:** `@StateObject private var permissions = PermissionsManager.shared` - `@StateObject` takes ownership and manages lifecycle, but `PermissionsManager.shared` is a singleton whose lifecycle is the app. This can cause SwiftUI to re-create the wrapper, leading to unexpected behavior.
- **Fix:** Use `@ObservedObject` instead since the singleton is already owned externally.

### MEDIUM

**BUG-007: RecordingState enum doesn't match MeetingRecord states**
- **File:** `ScribeCore/Config/AppState.swift` vs `ScribeCore/Storage/Models/MeetingRecord.swift`
- **Issue:** `RecordingState` has: `idle, recording, processing`. `MeetingRecord.state` uses strings: `"idle", "recording", "ended", "processing", "complete"`. No `ended` state in the UI enum, and state is a raw String with no validation.
- **Fix:** Create a shared `MeetingState` enum used by both. Validate state transitions.

**BUG-008: No validation on screen context interval**
- **File:** `ScribeCore/Config/AppSettings.swift:68-69`, `ScribeUI/MainWindow/SettingsView.swift:60`
- **Issue:** User can set `screenContextInterval` to 0, negative, or extremely small values via the TextField. This could cause rapid-fire screen captures or division by zero when used as a timer interval.
- **Fix:** Clamp to a reasonable minimum (e.g., 5 seconds). Add validation in the UI.

**BUG-009: onChange(of:) uses deprecated API**
- **File:** `ScribeUI/MainWindow/SettingsView.swift:100, 169`
- **Issue:** Uses `onChange(of: value) { _ in ... }` which is deprecated in macOS 14+. Since the target is macOS 13+, it works but produces warnings and will eventually be removed.
- **Fix:** Use the new `onChange(of: value) { oldValue, newValue in ... }` with `#available` check, or accept the deprecation warning for macOS 13 compat.

**BUG-010: Database migration erases data in DEBUG builds**
- **File:** `ScribeCore/Storage/Database.swift:41-42`
- **Issue:** `migrator.eraseDatabaseOnSchemaChange = true` in `#if DEBUG` means any schema change during development wipes ALL user data without warning. This is dangerous during active development where schema changes are frequent.
- **Fix:** Consider making this opt-in via a flag or environment variable rather than automatic.

### LOW

**BUG-011: JSONExporter overwrites existing exports silently**
- **File:** `ScribeCore/Storage/JSONExporter.swift:49`
- **Issue:** Re-exporting the same meeting overwrites the previous export file without warning.
- **Fix:** Either append timestamp to filename or warn before overwriting.

**BUG-012: SearchResult uses fallback UUID() on parse failure**
- **File:** `ScribeCore/Storage/SearchIndex.swift:51, 52, 72, 73, 94, 95`
- **Issue:** `UUID(uuidString: row["id"]) ?? UUID()` creates a random UUID if parsing fails, making the result unreferenceable. Should surface the error instead of silently creating garbage data.
- **Fix:** Skip the result or log the error rather than creating a phantom UUID.

**BUG-013: Missing input sanitization in FTS5 search query**
- **File:** `ScribeCore/Storage/SearchIndex.swift:27-31`
- **Issue:** FTS5 special characters (like `*`, `"`, `OR`, `AND`, `NOT`, `NEAR`) in user input are not escaped before being used in the MATCH query. Searching for `"hello*"` or `NOT meeting` could produce unexpected results or SQL errors.
- **Fix:** Escape or strip FTS5 special syntax from user input before building the query.

---

## Missing Functionality (from project spec)

These are features mentioned in the project memory/spec that are not yet implemented:

1. **Audio capture engine** - No AVAudioEngine / ScreenCaptureKit integration for actual recording
2. **Transcription provider integration** - No API clients for Deepgram/AssemblyAI/OpenAI Whisper
3. **LLM integration** - No API clients for Claude/OpenAI/Ollama
4. **Meeting detection** - No calendar monitoring or process detection
5. **Floating overlay** - No overlay window implementation
6. **MCP server** - No local HTTP server for MCP protocol
7. **Google OAuth** - No OAuth flow implementation
8. **Onboarding flow** - `hasCompletedOnboarding` flag exists but no onboarding UI
9. **Connection test** - Marked as TODO in SettingsView (line 113), currently fakes success

---

## Test Coverage Analysis

### New Test Suite Written (75+ tests across 2 targets)

**ScribeTests/ScribeCoreTests.swift** - Unit tests (no DB):
- `MeetingRecordTests` (14 tests): defaults, unique IDs, all states, unicode, codable round-trip, timestamps
- `TranscriptSegmentTests` (8 tests): defaults, speaker info, non-final, confidence, boundaries, codable
- `UserNoteTests` (3 tests): defaults, enriched text, table name
- `AISummaryTests` (3 tests): all types, invalid type detection, table name
- `FolderTests` (4 tests): defaults, nesting, empty name, table name
- `ScreenContextTests` (3 tests): defaults, source description, table name
- `MeetingExportTests` (2 tests): full codable round-trip, empty collections
- `AppStateTests` (7 tests): initial state, transitions, invalid transitions (bug detection)
- `KeychainManagerTests` (5 tests): provider mappings, key collision bug detection, uniqueness
- `AppSettingsTests` (4 tests): defaults, Ollama defaults, providers, interval validation bug
- `RecordingStateTests` (2 tests): raw values, missing states bug detection
- `TranscriptionProviderTypeTests` (3 tests): all cases, display values, identifiable
- `LLMProviderTypeTests` (2 tests): all cases, display values

**ScribeCoreIntegrationTests/DatabaseIntegrationTests.swift** - Database integration tests:
- `MeetingCRUDTests` (8 tests): insert/fetch, update state, delete, cascade delete, ordering, pagination, FK constraints, folder deletion set null
- `TranscriptSegmentDBTests` (5 tests): chronological order, batch insert, FK constraint, unicode text
- `FTSSearchTests` (5 tests): search transcripts/notes/summaries, no results, FTS sync
- `FolderDBTests` (3 tests): nesting, parent deletion, sort order
- `DataIntegrityTests` (4 tests): duplicate UUID, long text, special characters, concurrent reads
- `JSONExportFormatTests` (2 tests): valid JSON, round-trip

### Test Results (2026-04-05)

```
✔ Test run with 87 tests in 20 suites passed after 0.056 seconds.
```

**All 87 tests passing.** Run command:
```bash
swift test -Xlinker -L/Library/Developer/CommandLineTools/Library/Developer/usr/lib -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/usr/lib
```

### Remaining test coverage gaps:
- MeetingStore actor methods (need mocking or DI for Database)
- JSONExporter file I/O
- PermissionsManager (requires system permissions)
- UI view rendering tests
- End-to-end recording flow
