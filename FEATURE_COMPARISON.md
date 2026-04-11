# Granola.ai vs Scribe — Feature Comparison

**Date:** 2026-04-06
**Granola version:** Production (Series C, $125M raised)
**Scribe version:** v0.1.0 (alpha, open-source)

---

## Legend


| Symbol | Meaning                                    |
| ------ | ------------------------------------------ |
| ✅      | Fully implemented                          |
| 🟡     | Partially implemented / basic version      |
| ❌      | Not implemented                            |
| 🔒     | Proprietary / closed-source (Granola only) |
| 🆓     | Open-source advantage (Scribe only)        |


---

## Core Meeting Capture


| Feature                                         | Granola    | Scribe | Notes                                                   |
| ----------------------------------------------- | ---------- | ------ | ------------------------------------------------------- |
| Audio capture from computer (no bot)            | ✅          | ✅      | Both capture system audio invisibly via OS APIs         |
| Microphone capture                              | ✅          | ✅      | AVAudioEngine in Scribe                                 |
| System audio capture                            | ✅          | ✅      | ScreenCaptureKit in Scribe                              |
| Invisible to participants                       | ✅          | ✅      | No bot joins the call                                   |
| Voice Activity Detection                        | ✅ (likely) | ✅      | RMS threshold + hysteresis in Scribe                    |
| Dual audio paths (recording + transcription)    | Unknown    | ✅      | AudioMixer splits to recording and VAD-filtered streams |
| Self-exclusion (don't capture own audio output) | ✅ (likely) | ✅      | Scribe excludes own bundle ID from ScreenCaptureKit     |


## Transcription


| Feature                                | Granola           | Scribe | Notes                                                     |
| -------------------------------------- | ----------------- | ------ | --------------------------------------------------------- |
| Real-time transcription                | ✅                 | ✅      | Streaming via WebSocket (Deepgram/AssemblyAI)             |
| Transcription provider: Deepgram       | 🔒 Internal       | ✅      | User configures API key                                   |
| Transcription provider: AssemblyAI     | 🔒 Internal       | ✅      | User configures API key                                   |
| Transcription provider: OpenAI Whisper | 🔒 Internal       | ✅      | REST-based, 5s chunk buffering                            |
| User chooses transcription provider    | ❌ (Granola picks) | ✅ 🆓   | Scribe lets user BYO provider                             |
| Speaker diarization                    | ✅                 | ✅      | Via provider (Deepgram diarize=true)                      |
| Speaker renaming                       | Unknown           | ✅      | Per-meeting or global speaker profiles                    |
| Speaker colors                         | Unknown           | ✅      | 8-color cycling palette                                   |
| Multi-language transcription           | ✅                 | 🟡     | Scribe passes language param; limited to provider support |
| Transcript editing / deletion          | ✅                 | ❌      | Granola recently added transcript editing                 |
| Interim (partial) results              | ✅ (likely)        | ✅      | Non-final segments shown in real-time                     |


## AI / LLM Features


| Feature                                  | Granola           | Scribe | Notes                                           |
| ---------------------------------------- | ----------------- | ------ | ----------------------------------------------- |
| Auto-generate meeting summary            | ✅                 | ✅      | Post-meeting summarization with 3 types         |
| Summary types: full overview             | ✅                 | ✅      |                                                 |
| Summary types: action items              | ✅                 | ✅      |                                                 |
| Summary types: key decisions             | ✅                 | ✅      |                                                 |
| Summary types: topics                    | ✅                 | 🟡     | Schema supports it; generation TBD              |
| Summary types: follow-ups                | ✅                 | 🟡     | Schema supports it; generation TBD              |
| Generate follow-up emails                | ✅                 | ❌      |                                                 |
| Extract budget info                      | ✅                 | ❌      |                                                 |
| Identify objections                      | ✅                 | ❌      |                                                 |
| Create blog posts from meetings          | ✅                 | ❌      |                                                 |
| AI chat about meetings                   | ✅                 | ✅      | Rolling context window + chat history           |
| AI chat quick actions                    | ✅                 | ✅      | "What did I miss?", "Action items", etc.        |
| AI chat across meetings                  | ✅                 | ❌      | Scribe chat is single-meeting only              |
| Note enrichment (add transcript context) | Unknown           | ✅      | LLM adds nearby transcript to user notes        |
| User chooses LLM provider                | ❌ (Granola picks) | ✅ 🆓   | Claude, GPT, Ollama, any OpenAI-compatible      |
| Local/offline LLM (Ollama)               | ❌                 | ✅ 🆓   | Full privacy with local models                  |
| Screen context in summaries              | Unknown           | ✅      | OCR from screen shares included in LLM prompt   |
| Advanced "thinking" models               | ✅ (Business+)     | ✅ 🆓   | User can pick any model, including o1/opus      |
| Recipes / templated prompts              | ✅                 | ❌      | Granola has "Recipes" for reusable chat prompts |
| Edit notes by voice                      | ✅                 | ❌      |                                                 |


## Meeting Detection


| Feature                        | Granola    | Scribe | Notes                                                    |
| ------------------------------ | ---------- | ------ | -------------------------------------------------------- |
| Auto-detect from calendar      | ✅          | ✅      | EventKit + Google Calendar polling                       |
| Detect Zoom launch             | ✅          | ✅      | NSWorkspace process monitoring                           |
| Detect Teams launch            | ✅          | ✅      |                                                          |
| Detect Webex launch            | ✅          | ✅      |                                                          |
| Detect Google Meet (browser)   | ✅          | 🟡     | Scribe detects browser launch but can't confirm Meet tab |
| Detect Slack calls             | ✅          | ❌      |                                                          |
| Audio activity detection       | Unknown    | ✅      | Mic + system audio simultaneous for >10s                 |
| Auto-start recording           | ✅          | ✅      | Configurable in settings                                 |
| Push notification on detection | ✅ (likely) | ✅      | UNNotification with Start Recording action               |


## Note-Taking & Templates


| Feature                               | Granola | Scribe | Notes                                        |
| ------------------------------------- | ------- | ------ | -------------------------------------------- |
| Take notes during meeting             | ✅       | ✅      | Floating overlay with note input             |
| Rich text / structured notes          | ✅       | 🟡     | Scribe stores plain text + enrichedText      |
| Customizable templates                | ✅       | ❌      | Customer discovery, user interview, 1:1 etc. |
| Template marketplace                  | ✅       | ❌      |                                              |
| Note formatting (headers, bullets)    | ✅       | ❌      | Scribe stores plain text                     |
| Meeting notepad (write before/during) | ✅       | 🟡     | Scribe has overlay input, not a full notepad |


## UI & App Experience


| Feature                          | Granola | Scribe | Notes                                          |
| -------------------------------- | ------- | ------ | ---------------------------------------------- |
| Menu bar app (macOS)             | ✅       | ✅      |                                                |
| Floating overlay during meetings | ✅       | ✅      | NSPanel, nonactivating, sharingType=.none      |
| Overlay hidden from screen share | ✅       | ✅      |                                                |
| Full meeting list window         | ✅       | ✅      | NavigationSplitView 3-column                   |
| Meeting detail view              | ✅       | ✅      | Tabs: Summary, Transcript, Notes, Chat         |
| Meeting search (full-text)       | ✅       | ✅      | FTS5 across transcripts, notes, summaries      |
| Live transcript view             | ✅       | ✅      | Auto-scrolling with speaker colors             |
| Transcript speaker filter        | Unknown | ✅      | Filter by individual speaker                   |
| Onboarding wizard                | ✅       | ✅      | 5-step onboarding with permissions + API keys  |
| Settings UI                      | ✅       | ✅      | Tabs: General, Transcription, LLM, Permissions |
| Dark mode support                | ✅       | 🟡     | SwiftUI adaptive, but not specifically tested  |
| Keyboard shortcuts               | ✅       | 🟡     | Menu bar shortcuts only                        |


## Platform Support


| Feature                       | Granola | Scribe | Notes                               |
| ----------------------------- | ------- | ------ | ----------------------------------- |
| macOS                         | ✅       | ✅      | macOS 14+ (Sonoma)                  |
| Windows                       | ✅       | ❌      | Swift/macOS only                    |
| iOS / iPhone                  | ✅       | ❌      |                                     |
| Phone call recording (mobile) | ✅       | ❌      | Granola mobile captures phone calls |
| Web app                       | Unknown | ❌      |                                     |


## Data & Storage


| Feature                        | Granola          | Scribe | Notes                                                       |
| ------------------------------ | ---------------- | ------ | ----------------------------------------------------------- |
| Local storage                  | Unknown (cloud?) | ✅ 🆓   | SQLite on disk, data never leaves machine                   |
| Cloud sync                     | ✅                | ❌      | Granola syncs across devices                                |
| Data stays on your machine     | ❌ (cloud)        | ✅ 🆓   | Core Scribe value prop                                      |
| JSON export                    | Unknown          | ✅      | Per-meeting export to ~/Application Support/Scribe/exports/ |
| Meeting folders / organization | ✅                | ✅      | Hierarchical folders with sort order                        |
| Meeting deletion               | ✅                | ✅      | With cascade delete of all related data                     |
| Swipe to delete                | ✅                | ✅      |                                                             |
| Search across all meetings     | ✅                | ✅      | FTS5 full-text search                                       |


## Integrations


| Feature                      | Granola  | Scribe | Notes                                   |
| ---------------------------- | -------- | ------ | --------------------------------------- |
| Slack integration            | ✅        | ❌      |                                         |
| Notion integration           | ✅        | ❌      |                                         |
| HubSpot CRM                  | ✅        | ❌      |                                         |
| Attio CRM                    | ✅        | ❌      |                                         |
| Affinity CRM                 | ✅        | ❌      |                                         |
| Zapier (8000+ apps)          | ✅        | ❌      |                                         |
| MCP (Model Context Protocol) | ✅ (beta) | ✅      | Scribe has MCP server with 4 tools      |
| Local REST API               | Unknown  | ✅ 🆓   | localhost:7777 with full CRUD endpoints |
| Email sharing                | ✅        | ❌      |                                         |
| Public link sharing          | ✅        | ❌      |                                         |
| Calendar: Google Calendar    | ✅        | ✅      | OAuth PKCE flow + REST API              |
| Calendar: Outlook/Exchange   | ✅        | ❌      | Scribe only has Google + local EventKit |
| Calendar: Apple Calendar     | ✅        | ✅      | Via EventKit                            |
| Calendar deduplication       | Unknown  | ✅      | Merges Google + EventKit by title+time  |


## Privacy & Security


| Feature                     | Granola          | Scribe | Notes                                       |
| --------------------------- | ---------------- | ------ | ------------------------------------------- |
| Data stays local            | ❌                | ✅ 🆓   | Scribe's core differentiator                |
| BYO API keys                | ❌                | ✅ 🆓   | User controls which services get their data |
| BYO LLM (including local)   | ❌                | ✅ 🆓   | Ollama for fully offline AI                 |
| No telemetry / analytics    | Unknown          | ✅ 🆓   | Scribe sends nothing                        |
| Keychain credential storage | N/A (cloud auth) | ✅      | macOS Keychain for all secrets              |
| Audio not persisted to disk | Unknown          | ✅      | Only transcript text saved                  |
| Opt out of model training   | ✅ (free tier)    | ✅ 🆓   | Scribe never sends to training              |
| SSO (enterprise)            | ✅ ($35/user)     | ❌      |                                             |
| Auto-deletion periods       | ✅ (enterprise)   | ❌      |                                             |
| Org-wide usage notification | ✅ (enterprise)   | N/A    |                                             |
| Open source                 | ❌                | ✅ 🆓   | Fully auditable                             |


## Screen Context


| Feature                           | Granola | Scribe | Notes                                                 |
| --------------------------------- | ------- | ------ | ----------------------------------------------------- |
| Screen capture during meetings    | Unknown | ✅      | ScreenCaptureKit screenshots at configurable interval |
| OCR / text extraction from slides | Unknown | ✅      | Vision LLM extracts text, image discarded             |
| Screen context in AI chat         | Unknown | ✅      | "What's on screen?" uses last 5 contexts              |
| Screen context in summaries       | Unknown | ✅      | Included in summarization prompt                      |
| Configurable capture interval     | Unknown | ✅      | Default 15s, user-configurable                        |


## API & Developer Experience


| Feature                       | Granola            | Scribe | Notes                                     |
| ----------------------------- | ------------------ | ------ | ----------------------------------------- |
| Personal API access           | ✅ (Business)       | ✅ 🆓   | localhost:7777 REST API, always available |
| Enterprise API                | ✅ ($35/user)       | ✅ 🆓   | Same API, no tier gating                  |
| MCP server for AI tools       | ✅ (beta, Business) | ✅      | 4 tools: list, get, search, status        |
| Programmatic meeting search   | ✅ (API)            | ✅      | GET /api/search?q=                        |
| Programmatic meeting deletion | Unknown            | ✅      | DELETE /api/meetings/{id}                 |


## Pricing


| Tier         | Granola                                             | Scribe                   |
| ------------ | --------------------------------------------------- | ------------------------ |
| Free         | Limited history, basic AI                           | ✅ Everything, forever 🆓 |
| Pro/Business | $14/user/mo: unlimited + advanced AI + integrations | N/A (all free)           |
| Enterprise   | $35/user/mo: SSO + admin + compliance               | N/A (all free)           |
| Self-hosted  | ❌                                                   | ✅ 🆓                     |
| Open source  | ❌                                                   | ✅ 🆓                     |


---

## Summary

### Where Granola wins:

- **Cross-platform**: Windows + iOS + mobile phone call recording
- **Integrations ecosystem**: Slack, Notion, HubSpot, Attio, Zapier (8000+ apps)
- **Sharing**: Email, public links, "Shared with me"
- **Templates**: Rich customizable templates for different meeting types
- **Post-meeting actions**: Follow-up emails, blog posts, budget extraction, objection tracking
- **Cross-meeting AI chat**: Query across all meetings, not just one
- **Team features**: Shared folders, centralized billing, admin controls
- **Polish**: Production-grade UX with years of iteration, $125M in funding
- **Recipes**: Reusable templated prompts for chat
- **Voice note editing**: Edit notes by speaking
- **Transcript editing**: Delete parts of transcripts

### Where Scribe wins:

- **Privacy**: Data never leaves your machine, fully local storage
- **BYO everything**: Choose your own transcription provider + LLM (including local Ollama)
- **Cost**: $0 forever, no tiers, no limits
- **Open source**: Fully auditable, modifiable, self-hostable
- **Local REST API**: Always-on localhost:7777 for custom integrations
- **Screen context capture**: OCR from screen shares included in AI features
- **Speaker identification**: Rename speakers, color coding, per-meeting profiles
- **No telemetry**: Zero data collection
- **Developer-friendly**: MCP server + REST API + JSON export, no API key required

### Feature parity:

- Core meeting capture (invisible, no bot)
- Real-time transcription with speaker diarization
- AI meeting summaries (full, action items, decisions)
- AI chat during/after meetings
- Meeting detection (calendar, process monitoring)
- Floating overlay (hidden from screen share)
- Full meeting list/detail UI
- Full-text search across all data
- Google Calendar integration
- Menu bar app experience
- Onboarding flow

### Key gaps to close:

1. **Templates** — Rich meeting templates would significantly improve UX
2. **Cross-meeting AI** — Chat that spans multiple meetings
3. **Follow-up emails** — Auto-generate and send
4. **Sharing** — Export to Slack, Notion, email
5. **Windows/iOS** — Platform expansion (long-term)

