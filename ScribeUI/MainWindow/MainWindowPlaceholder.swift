import SwiftUI
import ScribeCore

/// Main window with sidebar: All Meetings | Search | Folders | Settings
public struct MainWindowPlaceholder: View {
    @ObservedObject var appState: AppState
    @State private var selectedMeetingId: UUID?
    @State private var sidebarItem: SidebarItem = .allMeetings
    @State private var refreshTrigger = UUID()
    @State private var folders: [Folder] = []
    @State private var editingFolderId: UUID?
    @State private var editingFolderName = ""
    @State private var settingsSection: SettingsSection = .general

    private static let toolbarDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, h:mm a"
        return f
    }()

    enum SidebarItem: Hashable {
        case allMeetings
        case search
        case settings
        case folder(UUID)
    }

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        NavigationSplitView {
            List(selection: $sidebarItem) {
                Label("All Meetings", systemImage: "list.bullet")
                    .tag(SidebarItem.allMeetings)
                Label("Search", systemImage: "magnifyingglass")
                    .tag(SidebarItem.search)

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

                // New Folder button
                Button {
                    createNewFolder()
                } label: {
                    Label("New Folder", systemImage: "plus")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Section {
                    Label("Settings", systemImage: "gear")
                        .tag(SidebarItem.settings)
                }
            }
            .navigationTitle("Scribe")
            .frame(minWidth: 180)
            .task { await loadFolders() }
            .onReceive(NotificationCenter.default.publisher(for: .foldersChanged)) { _ in
                Task { await loadFolders() }
            }
        } content: {
            switch sidebarItem {
            case .allMeetings:
                MeetingListView(selectedMeetingId: $selectedMeetingId, folderId: nil, folders: folders)
                    .id(refreshTrigger)
                    .navigationSplitViewColumnWidth(min: 300, ideal: 340, max: 500)
            case .search:
                SearchView(selectedMeetingId: $selectedMeetingId)
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
            case .allMeetings, .search, .folder:
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
            // Hidden keyboard shortcut buttons
            ToolbarItem(placement: .automatic) {
                HStack(spacing: 0) {
                    Button("Search") { sidebarItem = .search }
                        .keyboardShortcut("f", modifiers: .command)
                        .hidden()
                    Button("Settings") { sidebarItem = .settings }
                        .keyboardShortcut(",", modifiers: .command)
                        .hidden()
                }
                .frame(width: 0, height: 0)
                .clipped()
            }

            // Keyboard shortcut only (hidden) — actual button is in MeetingListView
            ToolbarItem(placement: .primaryAction) {
                Button {
                    startNewMeeting()
                } label: {
                    EmptyView()
                }
                .keyboardShortcut("n", modifiers: .command)
                .frame(width: 0, height: 0)
                .clipped()
            }
        }
        .frame(minWidth: 950, minHeight: 550)
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
                .textFieldStyle(.roundedBorder)
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
        List(SettingsSection.allCases, selection: $selectedSection) { section in
            Label(section.rawValue, systemImage: section.icon)
                .tag(section)
        }
        .navigationTitle("Settings")
    }
}
