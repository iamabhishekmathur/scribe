# Scribe

**Open-source AI meeting notetaker for macOS.** Captures audio invisibly (no bot joins your call), transcribes in real-time, and generates smart summaries with action items — all stored locally on your Mac.

Think [Granola](https://granola.so) or Otter.ai, but open-source, private, and configurable.

---

## Why Scribe?

Most meeting notetakers require a bot to join your call. Your colleagues see it. It's awkward. Some workplaces ban them entirely.

Scribe works differently:
- **Invisible capture** — records directly from your mic and system audio using macOS APIs. No bot ever joins your meeting.
- **Your data, your Mac** — everything is stored in a local SQLite database. Nothing leaves your machine except what you explicitly send to your configured AI providers.
- **Bring your own AI** — configure any LLM (Claude, GPT, Ollama, or any OpenAI-compatible endpoint) and any transcription provider (Deepgram, AssemblyAI, OpenAI Whisper).
- **Open source** — MIT licensed. Fork it, extend it, self-host it.

## Who is this for?

- **Founders and executives** who are in back-to-back meetings and need action items, decisions, and follow-ups extracted automatically.
- **Individual contributors** who multitask during meetings and want to ask "what did I miss?" in real-time.
- **Privacy-conscious teams** who want meeting intelligence without sending recordings to third-party services they don't control.
- **Developers** who want to hack on a meeting tool — add integrations, customize prompts, or build on the local API.

## Features

### Core
- **Menu bar app** — lives in your menu bar, not the dock. Lightweight and unobtrusive.
- **Auto-detection** — detects when you join a Zoom meeting and prompts you to start recording.
- **Dual audio capture** — mic (your voice) via AVAudioEngine + system audio (other participants) via ScreenCaptureKit.
- **Real-time transcription** — streams audio to your configured provider with speaker diarization.
- **Structured AI summaries** — post-meeting debrief with structured rendering: topics as numbered rows, decisions as checkmark cards, action items with @mention highlighting and who/what/when columns.
- **6 summary templates** — General, 1:1, Standup, Customer Call, Interview, Brainstorm — each generates sections tailored to the meeting type.
- **Notes editor** — take notes during the meeting. Your notes are used by the AI to prioritize what matters to you.
- **Real-time chat** — ask questions during the meeting ("what did I miss?", "what are they asking?") and get immediate, concise answers with source citations.
- **Speaker timeline** — visual horizontal bars showing who spoke when, color-coded per speaker.

### Search & Navigation
- **Command palette** (`⌘K`) — Raycast-style floating search with actions (start recording, toggle theme, open settings), recent meetings, and full-text search.
- **Natural language search** — ask questions like "what did we decide about pricing?" — Scribe extracts keywords via your LLM, searches FTS, and synthesizes an AI answer.
- **Search filters** — filter by source (transcripts, notes, summaries, screen context).
- **Keyword highlighting** — matched terms highlighted in search results.
- **Full-text search** — across transcripts, notes, summaries, and screen context (powered by SQLite FTS5).
- **Chrome bar** — persistent top bar with breadcrumb navigation and recording status badge.

### Organization
- **Folders** — create folders, drag meetings into them, right-click to move. One folder per meeting.
- **Starred & Archive** — mark important meetings, archive old ones to keep the list clean.
- **Google Calendar** — see upcoming meetings in the menu bar and meeting list. OAuth 2.0 PKCE integration.

### Technical
- **Local REST API** — `localhost:7777` with endpoints for meetings, transcripts, summaries, search, and status.
- **MCP server** — Model Context Protocol server for accessing meeting data from AI clients like Claude Code.
- **Markdown export** — auto-export each meeting as a Markdown file.
- **Configurable providers** — swap transcription and LLM providers without changing code.
- **Screen context** — optionally captures periodic screenshots during screen share, extracts text via vision LLM, and feeds it into summaries and chat.
- **Disk usage** — visual storage breakdown in Settings showing audio, transcripts, summaries, and other data.

## Install

### Download (recommended)

1. Download the latest `.dmg` from [Releases](https://github.com/iamabhishekmathur/scribe/releases)
2. Open the `.dmg` and drag **Scribe** to your **Applications** folder
3. **Important:** Scribe is not notarized yet (no Apple Developer Program enrollment). macOS will block it on first launch. Run this command to remove the quarantine flag:

```bash
xattr -cr /Applications/Scribe.app
```

4. Open Scribe from Applications. It will appear in your menu bar.

> **Why is this needed?** macOS Gatekeeper quarantines apps downloaded from the internet that aren't notarized by Apple. The `xattr -cr` command removes the `com.apple.quarantine` extended attribute so macOS treats the app as trusted. This is standard for open-source macOS apps distributed outside the App Store.

### Build from Source

#### Prerequisites

- **macOS 14+** (Sonoma or later)
- **Xcode Command Line Tools** — `xcode-select --install`
- A transcription API key (Deepgram, AssemblyAI, or OpenAI)
- An LLM API key (Anthropic Claude, OpenAI, or a local Ollama instance)

```bash
# Clone the repo
git clone https://github.com/iamabhishekmathur/scribe.git
cd scribe

# Build and run
swift build
swift run Scribe
```

#### Build a .dmg for distribution

```bash
# Build release .app bundle and .dmg
./scripts/build-dmg.sh

# Output: .build/release/Scribe-0.3.0.dmg
```

The app will appear in your menu bar. On first launch, it will walk you through:
1. Granting permissions (microphone, screen recording)
2. Configuring your transcription provider + API key
3. Configuring your LLM provider + API key
4. Connecting Google Calendar (optional)

### Google Calendar Setup (Optional)

To enable Google Calendar integration for your own build:

1. Go to [Google Cloud Console](https://console.cloud.google.com) > APIs & Services > Credentials
2. Create an OAuth 2.0 Client ID (Desktop app type)
3. Enable the Google Calendar API
4. Copy `.env.example` to `.env` and fill in your credentials:

```bash
cp .env.example .env
# Edit .env with your client ID and secret
```

5. Place the `.env` file in `~/Library/Application Support/Scribe/.env` (Scribe reads from there at runtime)

## Architecture

```
Scribe/
├── ScribeApp/          # Main app target (@main, AppDelegate, menu bar)
├── ScribeCore/         # Business logic library
│   ├── Audio/          # Mic + system audio capture, mixing, VAD
│   ├── Transcription/  # Provider protocol + Deepgram, AssemblyAI, Whisper
│   ├── AI/             # LLM providers, summarization, enrichment, chat
│   ├── Meeting/        # Detection (Zoom process monitoring), session state
│   ├── Calendar/       # Google Calendar OAuth + REST client
│   ├── Storage/        # SQLite (GRDB), models, FTS5 search, JSON export
│   ├── Server/         # Local REST API on port 7777
│   └── Config/         # Settings, credentials, permissions
├── ScribeUI/           # SwiftUI views
│   ├── MainWindow/     # 3-column layout, meeting detail, settings, search
│   ├── MenuBar/        # Menu bar dropdown with upcoming events
│   ├── Overlay/        # Floating panel during meetings
│   └── Onboarding/     # First-launch wizard
└── ScribeTests/        # Unit and integration tests
```

### Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| **Swift native** (SwiftUI + AppKit) | Smallest binary (~10MB), fastest launch, best macOS integration. No Electron. |
| **SQLite via GRDB** (not Core Data) | Raw SQL for FTS5 virtual tables, WAL mode for concurrent API reads, easy JSON export. |
| **SPM executable** (not .app bundle) | Simpler build, no Xcode project needed. Trade-off: some macOS APIs need workarounds. |
| **Actor-based concurrency** | All providers and managers use Swift actors for compile-time data race safety. |
| **Dual audio path** | Recording (full mix) separate from transcription (VAD-filtered mic + unfiltered system). Reduces transcription costs. |
| **File-based credentials** | Keychain prompts on every launch for unsigned SPM executables. File storage with obfuscation avoids this. |

### Audio Pipeline

```
┌─────────────┐     ┌────────────┐     ┌─────────────────────────────────┐
│ Microphone   │────▶│            │────▶│ Recording (full, unfiltered)    │
│ (AVAudio     │     │ AudioMixer │     └─────────────────────────────────┘
│  Engine)     │────▶│            │────▶│ Transcription (VAD-filtered mic │
└─────────────┘     │            │     │  + unfiltered system audio)      │
┌─────────────┐     │            │     └─────────────────────────────────┘
│ System Audio │────▶│            │
│ (ScreenCap-  │     └────────────┘
│  tureKit)    │
└─────────────┘
```

- **Mic audio** is VAD-filtered before transcription (reduces silence/noise sent to provider)
- **System audio** (other participants) bypasses VAD — everything they say is transcribed
- Both sources go unfiltered to the recording path

### AI Prompts

Scribe's AI acts as your **executive assistant / chief of staff**:

| Prompt | Trigger | What it does |
|--------|---------|-------------|
| Full summary | Post-meeting | Debrief with overview, discussion points, decisions, action items, follow-ups |
| Action items | Post-meeting | Extracts what/who/when for each action item, weighted by your notes |
| Decisions | Post-meeting | Extracts decisions with context and ownership |
| Note enrichment | Post-meeting | Expands your notes with transcript context from the 60s around when you wrote them |
| Live chat | During meeting | Answers questions like "what did I miss?" with tight, scannable bullets |

All prompts include your notes as context — the AI treats what you wrote down as a signal for what matters to you.

## Configuration

### Transcription Providers

| Provider | Type | Best for |
|----------|------|----------|
| **Deepgram** | Real-time WebSocket | Best accuracy + speaker diarization |
| **AssemblyAI** | Real-time WebSocket | Good alternative with strong diarization |
| **OpenAI Whisper** | Chunked REST (5s segments) | Uses existing OpenAI key, slightly higher latency |

### LLM Providers

| Provider | Best for |
|----------|----------|
| **Claude** (Anthropic) | Best summarization quality, strong at structured output |
| **OpenAI** (GPT-4o, etc.) | Good all-around, widely available |
| **Ollama** | Free, fully local, no API key needed. Install from ollama.com |
| **Custom** | Any OpenAI-compatible endpoint (Azure, Together, Groq, etc.) |

All providers are configured in Settings within the app.

## Local API

Scribe runs a REST API on `localhost:7777`:

```bash
# List meetings
curl http://localhost:7777/api/meetings

# Get a specific meeting with transcript
curl http://localhost:7777/api/meetings/<id>/transcript

# Get summary
curl http://localhost:7777/api/meetings/<id>/summary

# Search across all meetings
curl http://localhost:7777/api/search?q=action+items

# Current status
curl http://localhost:7777/api/status
```

## Privacy

- **No bot joins your meetings.** Ever.
- **All data is stored locally** in `~/Library/Application Support/Scribe/`.
- **Audio is streamed to your configured transcription provider** (Deepgram, AssemblyAI, or OpenAI) for real-time transcription. No audio is stored by Scribe after transcription.
- **Transcript and notes are sent to your configured LLM** for summarization and chat. You choose the provider.
- **No telemetry, no analytics, no tracking.**
- Google Calendar integration uses read-only access and tokens are stored locally.

## Contributing

Contributions are welcome! This is an early-stage project and there's plenty to improve:

- **Meeting detection** — support for Google Meet, Microsoft Teams, Slack Huddles (currently Zoom only)
- **Speaker identification** — persistent speaker profiles across meetings
- **Export formats** — Notion, PDF, JSON export
- **Outlook Calendar** — Microsoft 365 calendar support
- **Local transcription** — Whisper.cpp integration for fully offline transcription
- **Notarization** — Apple Developer Program enrollment for signed distribution

## Tech Stack

- **Swift 6** with strict concurrency
- **SwiftUI + AppKit** for the UI
- **ScreenCaptureKit** for system audio capture
- **AVAudioEngine** for microphone capture
- **GRDB.swift** for SQLite with FTS5 full-text search
- **Starscream** for WebSocket connections to transcription providers
- **Swift Package Manager** for builds and dependencies

## License

MIT License. See [LICENSE](LICENSE) for details.

---

Built by [@iamabhishekmathur](https://github.com/iamabhishekmathur).
