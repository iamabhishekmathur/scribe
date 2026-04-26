import AppKit
import SwiftUI
import ScribeCore

/// Main window with sidebar: All Meetings | Folders | Settings
public struct MainWindowPlaceholder: View {
    @ObservedObject var appState: AppState
    @ObservedObject private var settings = AppSettings.shared
    @State private var selectedMeetingId: UUID?
    @State private var sidebarItem: SidebarItem = .allMeetings
    @State private var refreshTrigger = UUID()
    @State private var folders: [Folder] = []
    @State private var editingFolderId: UUID?
    @State private var editingFolderName = ""
    @State private var settingsSection: SettingsSection = .general
    @State private var showCommandPalette = false

    private static let toolbarDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, h:mm a"
        return f
    }()

    enum SidebarItem: Hashable {
        case allMeetings
        case starred
        case archive
        case settings
        case folder(UUID)
    }

    public init(appState: AppState) {
        self.appState = appState
    }

    @ObservedObject private var recorder = RecordingCoordinator.shared

    public var body: some View {
        VStack(spacing: 0) {
            // Chrome bar
            chromeBar

            NavigationSplitView {
                List(selection: $sidebarItem) {
                    Label("All Meetings", systemImage: "list.bullet")
                        .tag(SidebarItem.allMeetings)
                    Label("Starred", systemImage: "star")
                        .tag(SidebarItem.starred)
                        .foregroundStyle(MonoColors.textMuted)
                    Label("Archive", systemImage: "archivebox")
                        .tag(SidebarItem.archive)
                        .foregroundStyle(MonoColors.textMuted)

                    if !folders.isEmpty {
                        Section("Folders") {
                            ForEach(folders) { folder in
                                folderRow(folder)
                                    .tag(SidebarItem.folder(folder.id))
                            }
                            .onMove { source, destination in
                                moveFolder(from: source, to: destination)
                            }
                        }
                    }

                    Button {
                        createNewFolder()
                    } label: {
                        Label("New Folder", systemImage: "plus")
                            .foregroundStyle(MonoColors.textMuted)
                    }
                    .buttonStyle(.plain)

                    Section {
                        Label("Settings", systemImage: "gear")
                            .tag(SidebarItem.settings)
                    }
                }
                .navigationTitle("Scribe")
                .frame(minWidth: 180)
                .safeAreaInset(edge: .bottom) {
                    // Sidebar footer
                    HStack(spacing: 8) {
                        Circle().fill(MonoColors.accent).frame(width: 20, height: 20)
                        Text("User")
                            .font(MonoFont.sans(size: TypeScale.sm, weight: .medium))
                            .lineLimit(1)
                        Spacer()
                        Button { sidebarItem = .settings } label: {
                            Image(systemName: "gear")
                                .font(.system(size: 12))
                                .foregroundStyle(MonoColors.textFaint)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .overlay(alignment: .top) {
                        Rectangle().fill(MonoColors.divider).frame(height: 1)
                    }
                }
                .task { await loadFolders() }
                .onReceive(NotificationCenter.default.publisher(for: .foldersChanged)) { _ in
                    Task { await loadFolders() }
                }
            } content: {
                switch sidebarItem {
                case .allMeetings, .starred, .archive:
                    MeetingListView(selectedMeetingId: $selectedMeetingId, folderId: nil, folders: folders)
                        .id(refreshTrigger)
                        .navigationSplitViewColumnWidth(min: 300, ideal: 340, max: 500)
                case .settings:
                    SettingsSidebarList(selectedSection: $settingsSection)
                        .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 300)
                case .folder(let folderId):
                    MeetingListView(selectedMeetingId: $selectedMeetingId, folderId: folderId, folders: folders)
                        .id("\(folderId)-\(refreshTrigger)")
                        .navigationSplitViewColumnWidth(min: 300, ideal: 340, max: 500)
                }
            } detail: {
                switch sidebarItem {
                case .allMeetings, .starred, .archive, .folder:
                if let meetingId = selectedMeetingId {
                    MeetingDetailView(meetingId: meetingId)
                        .id(meetingId)
                } else {
                    ContentUnavailableView(
                        "Select a Meeting",
                        systemImage: "waveform.circle",
                        description: Text("Choose a meeting from the list to view its details.")
                    )
                }
            case .settings:
                SettingsDetailView(appState: appState, selectedSection: $settingsSection)
            }
        }
        .toolbar {
            // Hidden keyboard shortcuts
            ToolbarItem(placement: .automatic) {
                HStack(spacing: 0) {
                    Button("Search") { showCommandPalette = true }
                        .keyboardShortcut("k", modifiers: .command)
                        .hidden()
                    Button("Find") { showCommandPalette = true }
                        .keyboardShortcut("f", modifiers: .command)
                        .hidden()
                    Button("Settings") { sidebarItem = .settings }
                        .keyboardShortcut(",", modifiers: .command)
                        .hidden()
                    Button("New") { startNewMeeting() }
                        .keyboardShortcut("n", modifiers: .command)
                        .hidden()
                }
                .frame(width: 0, height: 0)
                .clipped()
            }
        }
        .overlay {
            if showCommandPalette {
                ZStack {
                    Color.black.opacity(0.35)
                        .ignoresSafeArea()
                        .onTapGesture { showCommandPalette = false }

                    VStack {
                        CommandPaletteView(
                            isPresented: $showCommandPalette,
                            selectedMeetingId: $selectedMeetingId,
                            sidebarItem: $sidebarItem
                        )
                        .padding(.top, 60)
                        Spacer()
                    }
                }
                .transition(.opacity)
                .animation(Anim.fast, value: showCommandPalette)
            }
        }
        .tint(MonoColors.accent)
        .frame(minWidth: 950, minHeight: 550)
        .onAppear { applyAppearance(settings.appearance) }
        .onChange(of: settings.appearance) { newValue in applyAppearance(newValue) }
        .onReceive(NotificationCenter.default.publisher(for: .meetingDeleted)) { _ in
            selectedMeetingId = nil
            refreshTrigger = UUID()
        }
        .onReceive(NotificationCenter.default.publisher(for: .meetingUpdated)) { _ in
            refreshTrigger = UUID()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openMeeting)) { notification in
            if let meetingId = notification.object as? UUID {
                sidebarItem = .allMeetings
                selectedMeetingId = meetingId
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSettingsWindow)) { _ in
            sidebarItem = .settings
        }
        .onReceive(NotificationCenter.default.publisher(for: .startNewMeeting)) { notification in
            if let info = notification.object as? [String: Any],
               let meetingId = info["meetingId"] as? UUID,
               let title = info["title"] as? String {
                appState.startRecording(meetingId: meetingId)
                Task {
                    await RecordingCoordinator.shared.startRecording(meetingId: meetingId, title: title)
                }
                NotificationCenter.default.post(name: .openMainWindow, object: nil)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    NotificationCenter.default.post(name: .openMeeting, object: meetingId)
                }
            }
        }
        } // end VStack wrapping chrome bar + nav
    }

    // MARK: - Chrome Bar

    private var chromeBar: some View {
        HStack(spacing: 0) {
            HStack(spacing: 4) {
                Text("scribe")
                    .font(MonoFont.mono(size: TypeScale.sm, weight: .semibold))
                    .foregroundStyle(MonoColors.accent)
                    .tracking(0.5)
                Text("/")
                    .font(MonoFont.mono(size: TypeScale.sm))
                    .foregroundStyle(MonoColors.textFaint)
                Text(chromeContext)
                    .font(MonoFont.mono(size: TypeScale.sm))
                    .foregroundStyle(MonoColors.textMuted)
                    .lineLimit(1)
            }
            .padding(.leading, 14)

            Spacer()

            HStack(spacing: 8) {
                if recorder.isRecording {
                    HStack(spacing: 5) {
                        RecDot(size: 5, color: MonoColors.live)
                        Text("REC")
                            .font(MonoFont.mono(size: TypeScale.xs, weight: .bold))
                            .foregroundStyle(MonoColors.live)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(MonoColors.liveBg, in: Capsule())
                }

                Button { showCommandPalette = true } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 10))
                            .foregroundStyle(MonoColors.textFaint)
                        Text("Search…")
                            .font(MonoFont.sans(size: TypeScale.sm))
                            .foregroundStyle(MonoColors.textFaint)
                        KbdView("⌘K")
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(MonoColors.bgElev, in: RoundedRectangle(cornerRadius: Radius.md))
                    .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(MonoColors.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            .padding(.trailing, 14)
        }
        .frame(height: 32)
        .background(MonoColors.bgSubtle)
        .overlay(alignment: .bottom) {
            Rectangle().fill(MonoColors.divider).frame(height: 1)
        }
    }

    private var chromeContext: String {
        switch sidebarItem {
        case .allMeetings: return "all meetings"
        case .starred: return "starred"
        case .archive: return "archive"
        case .settings: return "settings"
        case .folder(let id): return folders.first(where: { $0.id == id })?.name.lowercased() ?? "folder"
        }
    }

    // MARK: - Appearance

    /// Bridges the user's appearance preference to AppKit so it propagates to
    /// NSWindow chrome (sidebar background, titlebar) — `.preferredColorScheme()`
    /// alone leaves NavigationSplitView sidebars stuck on the previous value.
    private func applyAppearance(_ value: String) {
        switch value {
        case "dark":
            NSApp.appearance = NSAppearance(named: .darkAqua)
        case "light":
            NSApp.appearance = NSAppearance(named: .aqua)
        default:
            NSApp.appearance = nil
        }
    }

    // MARK: - Start New Meeting

    private func startNewMeeting() {
        let meetingId = UUID()
        let title = "Meeting " + Self.toolbarDateFormatter.string(from: Date())
        appState.startRecording(meetingId: meetingId)
        Task {
            await RecordingCoordinator.shared.startRecording(meetingId: meetingId, title: title)
        }
        NotificationCenter.default.post(name: .openMainWindow, object: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NotificationCenter.default.post(name: .openMeeting, object: meetingId)
        }
    }

    // MARK: - Folder Row

    @ViewBuilder
    private func folderRow(_ folder: Folder) -> some View {
        if editingFolderId == folder.id {
            TextField("Folder name", text: $editingFolderName)
                .textFieldStyle(MonoTextFieldStyle())
                .onSubmit { renameFolder(folder) }
                .onExitCommand { editingFolderId = nil }
        } else {
            Label(folder.name, systemImage: "folder")
                .contextMenu {
                    Button("Rename") {
                        editingFolderId = folder.id
                        editingFolderName = folder.name
                    }
                    Divider()
                    Button("Delete Folder", role: .destructive) {
                        deleteFolder(folder)
                    }
                }
                // Accept meeting drops
                .dropDestination(for: String.self) { items, _ in
                    guard let meetingIdStr = items.first,
                          let meetingId = UUID(uuidString: meetingIdStr) else { return false }
                    Task {
                        try? await MeetingStore.shared.moveMeetingToFolder(meetingId: meetingId, folderId: folder.id)
                        NotificationCenter.default.post(name: .meetingUpdated, object: nil)
                    }
                    return true
                }
        }
    }

    // MARK: - Folder Actions

    private func loadFolders() async {
        folders = (try? await MeetingStore.shared.getFolders()) ?? []
    }

    private func createNewFolder() {
        let folder = Folder(name: "New Folder", sortOrder: folders.count)
        Task {
            try? await MeetingStore.shared.createFolder(folder)
            await loadFolders()
            // Start editing the name immediately
            editingFolderId = folder.id
            editingFolderName = folder.name
        }
    }

    private func renameFolder(_ folder: Folder) {
        let newName = editingFolderName.trimmingCharacters(in: .whitespaces)
        guard !newName.isEmpty else { editingFolderId = nil; return }
        var updated = folder
        updated.name = newName
        Task {
            try? await MeetingStore.shared.updateFolder(updated)
            await loadFolders()
        }
        editingFolderId = nil
    }

    private func deleteFolder(_ folder: Folder) {
        Task {
            try? await MeetingStore.shared.deleteFolder(id: folder.id)
            // If currently viewing this folder, switch to All Meetings
            if case .folder(let id) = sidebarItem, id == folder.id {
                sidebarItem = .allMeetings
            }
            await loadFolders()
            refreshTrigger = UUID()
        }
    }

    private func moveFolder(from source: IndexSet, to destination: Int) {
        folders.move(fromOffsets: source, toOffset: destination)
        let orderedIds = folders.map(\.id)
        Task {
            try? await MeetingStore.shared.reorderFolders(orderedIds)
        }
    }
}

// MARK: - Notification

public extension Notification.Name {
    static let foldersChanged = Notification.Name("com.scribe.foldersChanged")
    static let startNewMeeting = Notification.Name("com.scribe.startNewMeeting")
}

// MARK: - Settings Section Enum (shared between sidebar list and detail)

public enum SettingsSection: String, CaseIterable, Identifiable {
    case general = "General"
    case transcription = "Transcription"
    case llm = "AI / LLM"
    case calendar = "Calendar"
    case permissions = "Permissions"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .general: return "gear"
        case .transcription: return "text.bubble"
        case .llm: return "brain"
        case .calendar: return "calendar"
        case .permissions: return "lock.shield"
        }
    }
}

// MARK: - Settings sidebar list (middle column when Settings selected)

struct SettingsSidebarList: View {
    @Binding var selectedSection: SettingsSection

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Settings")
                .font(MonoFont.sans(size: TypeScale.xl, weight: .bold))
                .foregroundStyle(MonoColors.text)
                .padding(.horizontal, Spacing.standard)
                .padding(.top, Spacing.standard)
                .padding(.bottom, Spacing.compact)

            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(SettingsSection.allCases) { section in
                        SettingsSidebarRow(
                            section: section,
                            isSelected: section == selectedSection
                        ) {
                            withAnimation(Anim.fast) { selectedSection = section }
                        }
                    }
                }
                .padding(.horizontal, Spacing.compact)
                .padding(.bottom, Spacing.standard)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(MonoColors.bg)
    }
}

private struct SettingsSidebarRow: View {
    let section: SettingsSection
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Spacing.compact) {
                Image(systemName: section.icon)
                    .font(.system(size: 12))
                    .foregroundStyle(isSelected ? MonoColors.accent : MonoColors.textMuted)
                    .frame(width: 16)
                Text(section.rawValue)
                    .font(MonoFont.sans(size: TypeScale.md, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? MonoColors.text : MonoColors.textMuted)
                Spacer()
            }
            .padding(.horizontal, Spacing.compact)
            .padding(.vertical, 6)
            .background(isSelected ? MonoColors.accentBg : Color.clear, in: RoundedRectangle(cornerRadius: Radius.md))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Command Palette (⌘K)

struct CommandPaletteView: View {
    @Binding var isPresented: Bool
    @Binding var selectedMeetingId: UUID?
    @Binding var sidebarItem: MainWindowPlaceholder.SidebarItem
    @State private var query = ""
    @State private var results: [SearchResult] = []
    @State private var aiAnswer: String?
    @State private var extractedKeywords: [String] = []
    @State private var isAISearching = false
    @State private var searchTask: Task<Void, Never>?
    @State private var recentMeetings: [MeetingRecord] = []
    @State private var activeFilter: SearchFilter = .everything
    @FocusState private var isFocused: Bool

    enum SearchFilter: String, CaseIterable { case everything, transcripts, notes, summaries, screen }

    var body: some View {
        VStack(spacing: 0) {
            // Search input
            HStack(spacing: 10) {
                if isAISearching {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 14, height: 14)
                } else {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14))
                        .foregroundStyle(MonoColors.textFaint)
                }
                TextField("Search or ask a question...", text: $query)
                    .textFieldStyle(.plain)
                    .font(MonoFont.sans(size: TypeScale.lg))
                    .focused($isFocused)
                    .onSubmit {
                        if let first = results.first {
                            selectResult(first)
                        }
                    }
                if !query.isEmpty {
                    Button {
                        query = ""
                        results = []
                        aiAnswer = nil
                        extractedKeywords = []
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(MonoColors.textFaint)
                    }
                    .buttonStyle(.plain)
                }
                KbdView("esc")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            if !results.isEmpty || !query.isEmpty || aiAnswer != nil {
                Rectangle().fill(MonoColors.divider).frame(height: 1)
            }

            // Filter bar (visible when query is non-empty)
            if !query.isEmpty {
                HStack(spacing: 6) {
                    Text("in:")
                        .font(MonoFont.mono(size: TypeScale.xs))
                        .foregroundStyle(MonoColors.textFaint)
                    ForEach(SearchFilter.allCases, id: \.self) { filter in
                        Button {
                            activeFilter = filter
                        } label: {
                            Text(filter.rawValue)
                                .font(MonoFont.mono(size: 10.5))
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background(activeFilter == filter ? MonoColors.accentBg : .clear, in: RoundedRectangle(cornerRadius: Radius.sm))
                                .foregroundStyle(activeFilter == filter ? MonoColors.accentText : MonoColors.textMuted)
                                .overlay(RoundedRectangle(cornerRadius: Radius.sm).strokeBorder(activeFilter == filter ? MonoColors.accentBorder : MonoColors.border, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(MonoColors.bgSubtle)
                .overlay(alignment: .bottom) { Rectangle().fill(MonoColors.divider).frame(height: 1) }
            }

            ScrollView {
                LazyVStack(spacing: 0) {
                    // Actions section (when query is empty)
                    if query.isEmpty {
                        paletteSectionHeader("ACTIONS")
                        paletteActionRow(icon: "mic", label: "start recording", hint: "record audio + system audio", kbd: "⌘N") {
                            isPresented = false
                            NotificationCenter.default.post(name: .startNewMeeting, object: ["meetingId": UUID(), "title": "Meeting \(ScribeDateFormatting.dateTime(Date()))"])
                        }
                        paletteActionRow(icon: "gear", label: "open settings", hint: "preferences and configuration", kbd: "⌘,") {
                            sidebarItem = .settings
                            isPresented = false
                        }
                        paletteActionRow(icon: "circle.lefthalf.filled", label: "toggle theme", hint: "switch dark/light mode", kbd: nil) {
                            let s = AppSettings.shared
                            s.appearance = s.appearance == "dark" ? "light" : "dark"
                        }

                        if !recentMeetings.isEmpty {
                            paletteSectionHeader("RECENT MEETINGS")
                            ForEach(recentMeetings.prefix(5)) { meeting in
                                paletteActionRow(icon: "waveform", label: meeting.title, hint: ScribeDateFormatting.shortDate(meeting.startTime), kbd: nil) {
                                    sidebarItem = .allMeetings
                                    selectedMeetingId = meeting.id
                                    isPresented = false
                                }
                            }
                        }
                    }

                    // AI answer card
                    if let answer = aiAnswer {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 10))
                                    .foregroundStyle(MonoColors.accent)
                                Text("AI Answer")
                                    .font(MonoFont.mono(size: TypeScale.xs, weight: .semibold))
                                    .foregroundStyle(MonoColors.accent)
                                Spacer()
                                if !extractedKeywords.isEmpty {
                                    Text(extractedKeywords.joined(separator: " · "))
                                        .font(MonoFont.mono(size: TypeScale.xs))
                                        .foregroundStyle(MonoColors.textFaint)
                                        .lineLimit(1)
                                }
                            }
                            Text(answer)
                                .font(MonoFont.sans(size: TypeScale.sm))
                                .foregroundStyle(MonoColors.text)
                                .lineSpacing(3)
                                .textSelection(.enabled)
                        }
                        .padding(12)
                        .background(MonoColors.accentBg, in: RoundedRectangle(cornerRadius: Radius.md))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }

                    // Loading indicator for AI search
                    if isAISearching && results.isEmpty {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Searching with AI...")
                                .font(MonoFont.mono(size: TypeScale.sm))
                                .foregroundStyle(MonoColors.textMuted)
                        }
                        .padding(16)
                    }

                    // No results
                    if results.isEmpty && !query.isEmpty && !isAISearching && aiAnswer == nil {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(MonoColors.textFaint)
                            Text("No results for \"\(query)\"")
                                .font(MonoFont.sans(size: TypeScale.sm))
                                .foregroundStyle(MonoColors.textMuted)
                        }
                        .padding(20)
                    }

                    // Results
                    ForEach(filteredResults.prefix(10)) { result in
                        paletteRow(result)
                    }
                }
            }
            .frame(maxHeight: aiAnswer != nil ? 400 : 320)
        }
        .frame(width: 560)
        .background(MonoColors.bgElev, in: RoundedRectangle(cornerRadius: Radius.xl))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl).strokeBorder(MonoColors.border, lineWidth: 1))
        .shadow(color: .black.opacity(0.4), radius: 30, y: 10)
        .onAppear {
            isFocused = true
            Task { recentMeetings = (try? await MeetingStore.shared.getAllMeetings())?.prefix(5).map { $0 } ?? [] }
        }
        .onChange(of: query) { _ in
            if query.isEmpty { activeFilter = .everything }
            debouncedSearch()
        }
        .onExitCommand { isPresented = false }
    }

    private func paletteRow(_ result: SearchResult) -> some View {
        Button {
            selectResult(result)
        } label: {
            HStack(spacing: 10) {
                // Source icon
                Image(systemName: sourceIcon(result.source))
                    .font(.system(size: 10))
                    .foregroundStyle(MonoColors.textFaint)
                    .frame(width: 14)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(result.meetingTitle)
                            .font(MonoFont.sans(size: TypeScale.base, weight: .medium))
                            .foregroundStyle(MonoColors.text)
                            .lineLimit(1)
                        if let speaker = result.speaker {
                            Text(speaker)
                                .font(MonoFont.mono(size: TypeScale.xs))
                                .foregroundStyle(MonoColors.accent)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(MonoColors.accentBg, in: RoundedRectangle(cornerRadius: Radius.sm))
                        }
                    }
                    Text(highlightedSnippet(result.snippet))
                        .font(MonoFont.sans(size: TypeScale.sm))
                        .lineLimit(1)
                }

                Spacer()

                Text(result.source.rawValue)
                    .font(MonoFont.mono(size: TypeScale.xs))
                    .foregroundStyle(MonoColors.textFaint)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(MonoColors.bgSubtle, in: RoundedRectangle(cornerRadius: Radius.sm))
                    .overlay(RoundedRectangle(cornerRadius: Radius.sm).strokeBorder(MonoColors.border, lineWidth: 1))

                Text(ScribeDateFormatting.shortDate(result.timestamp))
                    .font(MonoFont.mono(size: TypeScale.xs))
                    .foregroundStyle(MonoColors.textFaint)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            Rectangle().fill(MonoColors.divider).frame(height: 1)
        }
    }

    private func sourceIcon(_ source: SearchResult.SearchSource) -> String {
        switch source {
        case .transcript: return "waveform"
        case .note: return "pencil"
        case .summary: return "sparkles"
        case .title: return "text.document"
        case .screen: return "rectangle.on.rectangle"
        case .participant: return "person"
        }
    }

    private func selectResult(_ result: SearchResult) {
        sidebarItem = .allMeetings
        selectedMeetingId = result.meetingId
        isPresented = false
    }

    private func highlightedSnippet(_ html: String) -> AttributedString {
        var result = AttributedString()
        var remaining = html
        while let openRange = remaining.range(of: "<b>") {
            let before = String(remaining[remaining.startIndex..<openRange.lowerBound])
            result += AttributedString(before)
            remaining = String(remaining[openRange.upperBound...])
            if let closeRange = remaining.range(of: "</b>") {
                let matched = String(remaining[remaining.startIndex..<closeRange.lowerBound])
                var attr = AttributedString(matched)
                attr.font = MonoFont.sans(size: TypeScale.sm, weight: .semibold)
                attr.foregroundColor = MonoColors.accentText
                attr.backgroundColor = MonoColors.accentBg
                result += attr
                remaining = String(remaining[closeRange.upperBound...])
            }
        }
        result += AttributedString(remaining)
        return result
    }

    private func paletteSectionHeader(_ title: String) -> some View {
        Text(title)
            .font(MonoFont.mono(size: 9.5, weight: .semibold))
            .foregroundStyle(MonoColors.textFaint)
            .tracking(0.8)
            .padding(.horizontal, 14).padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MonoColors.bgSubtle)
            .overlay(alignment: .bottom) { Rectangle().fill(MonoColors.divider).frame(height: 1) }
    }

    private func paletteActionRow(icon: String, label: String, hint: String, kbd: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(MonoColors.textMuted)
                    .frame(width: 14)
                VStack(alignment: .leading, spacing: 1) {
                    Text(label)
                        .font(MonoFont.mono(size: 11.5, weight: .semibold))
                        .foregroundStyle(MonoColors.text)
                    Text(hint)
                        .font(MonoFont.sans(size: 10.5))
                        .foregroundStyle(MonoColors.textFaint)
                }
                Spacer()
                if let kbd { KbdView(kbd) }
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { Rectangle().fill(MonoColors.divider).frame(height: 1) }
    }

    private var filteredResults: [SearchResult] {
        guard activeFilter != .everything else { return results }
        return results.filter { result in
            switch activeFilter {
            case .everything: return true
            case .transcripts: return result.source == .transcript
            case .notes: return result.source == .note
            case .summaries: return result.source == .summary
            case .screen: return result.source == .screen
            }
        }
    }

    private func debouncedSearch() {
        searchTask?.cancel()
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else {
            results = []
            aiAnswer = nil
            extractedKeywords = []
            isAISearching = false
            return
        }

        searchTask = Task {
            // Always start with instant keyword search
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }

            // Detect NL early so instant search can use OR logic
            let isNL = await SearchIndex.shared.isNaturalLanguageQuery(q)

            // For NL queries, use OR logic so "which meeting did we do testing in?"
            // matches on "meeting" OR "testing" instead of requiring all words
            let fts = (try? await SearchIndex.shared.search(query: q, useOrLogic: isNL)) ?? []
            let titles = (try? await SearchIndex.shared.searchTitles(query: q)) ?? []
            let participants = (try? await SearchIndex.shared.searchParticipants(query: q)) ?? []

            var seen = Set<UUID>()
            var merged: [SearchResult] = []
            for r in titles where seen.insert(r.meetingId).inserted { merged.append(r) }
            for r in participants where seen.insert(r.meetingId).inserted { merged.append(r) }
            for r in fts { merged.append(r) }

            await MainActor.run {
                results = merged
                aiAnswer = nil
                extractedKeywords = []
            }

            // If NL query and LLM is available, also fire AI search for answer synthesis
            guard !Task.isCancelled, isNL else { return }

            await MainActor.run { isAISearching = true }

            if let nlResult = try? await SearchIndex.shared.naturalLanguageSearch(query: q) {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    // Merge NL results with existing, keeping any unique ones
                    var allResults = results
                    let existingIds = Set(allResults.map(\.id))
                    for r in nlResult.results where !existingIds.contains(r.id) {
                        allResults.append(r)
                    }
                    results = allResults
                    aiAnswer = nlResult.answer
                    extractedKeywords = nlResult.extractedKeywords
                    isAISearching = false
                }
            } else {
                await MainActor.run { isAISearching = false }
            }
        }
    }
}
