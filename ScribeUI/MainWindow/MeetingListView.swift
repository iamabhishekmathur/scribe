import SwiftUI
import ScribeCore
import os

private let logger = Logger(subsystem: "com.scribe.app", category: "MeetingList")

/// Meeting list with upcoming calendar events + past meetings grouped by date
public struct MeetingListView: View {
    @Binding var selectedMeetingId: UUID?
    let folderId: UUID?
    let folders: [Folder]
    @State private var meetings: [MeetingRecord] = []
    @State private var upcomingEvents: [CalendarManager.UpcomingMeeting] = []
    @State private var searchText = ""

    public init(selectedMeetingId: Binding<UUID?>, folderId: UUID?, folders: [Folder]) {
        self._selectedMeetingId = selectedMeetingId
        self.folderId = folderId
        self.folders = folders
    }

    public var body: some View {
        List(selection: $selectedMeetingId) {
            // Upcoming section (only in All Meetings, not folder views)
            if folderId == nil && !upcomingEvents.isEmpty {
                Section {
                    ForEach(upcomingEvents, id: \.id) { event in
                        UpcomingEventRow(event: event)
                            .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                    }
                } header: {
                    Text("Coming up")
                        .font(.system(.title2, design: .serif))
                        .fontWeight(.bold)
                        .foregroundStyle(.primary)
                        .textCase(nil)
                        .padding(.bottom, 4)
                }
            }

            // Past meetings grouped by date
            if meetings.isEmpty && upcomingEvents.isEmpty {
                emptyState
            } else {
                ForEach(groupedMeetings.keys.sorted().reversed(), id: \.self) { date in
                    if let dayMeetings = groupedMeetings[date] {
                        Section {
                            ForEach(dayMeetings) { meeting in
                                PastMeetingRow(meeting: meeting, isSelected: selectedMeetingId == meeting.id)
                                    .tag(meeting.id)
                                    .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                                    .draggable(meeting.id.uuidString)
                                    .contextMenu {
                                        meetingContextMenu(for: meeting)
                                    }
                            }
                        } header: {
                            Text(formatSectionDate(date))
                                .font(.callout)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                                .textCase(nil)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $searchText, prompt: "Filter meetings")
        .safeAreaInset(edge: .bottom) {
            if folderId == nil {
                Button {
                    let meetingId = UUID()
                    let title = "Meeting " + ScribeDateFormatting.dateTime(Date())
                    NotificationCenter.default.post(name: .startNewMeeting, object: ["meetingId": meetingId, "title": title])
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "waveform.circle.fill")
                            .font(.body)
                        Text("Start new meeting")
                            .font(.callout)
                            .fontWeight(.medium)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(.green.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
                    .foregroundStyle(.green)
                }
                .buttonStyle(ScribeButtonStyle())
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.bar)
            }
        }
        .task {
            await loadAll()
        }
        .refreshable {
            await loadAll()
        }
        .onReceive(NotificationCenter.default.publisher(for: .meetingUpdated)) { _ in
            Task { await loadMeetings() }
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func meetingContextMenu(for meeting: MeetingRecord) -> some View {
        if !folders.isEmpty {
            Menu("Move to Folder") {
                ForEach(folders) { folder in
                    Button {
                        moveMeeting(meeting.id, toFolder: folder.id)
                    } label: {
                        HStack {
                            Text(folder.name)
                            if meeting.folderId == folder.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
                Divider()
                if meeting.folderId != nil {
                    Button("Remove from Folder") {
                        moveMeeting(meeting.id, toFolder: nil)
                    }
                }
            }
        }

        Divider()

        Button("Delete Meeting", role: .destructive) {
            Task {
                try? await MeetingStore.shared.deleteMeeting(id: meeting.id)
                NotificationCenter.default.post(name: .meetingDeleted, object: meeting.id)
            }
        }
    }

    private func moveMeeting(_ meetingId: UUID, toFolder folderId: UUID?) {
        Task {
            try? await MeetingStore.shared.moveMeetingToFolder(meetingId: meetingId, folderId: folderId)
            NotificationCenter.default.post(name: .meetingUpdated, object: nil)
        }
    }

    // MARK: - Upcoming

    private var upcomingSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Coming up")
                .font(.title2)
                .fontWeight(.bold)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)

            VStack(spacing: 0) {
                ForEach(upcomingEvents, id: \.id) { event in
                    UpcomingEventRow(event: event)

                    if event.id != upcomingEvents.last?.id {
                        Divider()
                            .padding(.leading, 56)
                    }
                }
            }
            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 12)
            .padding(.bottom, 16)
        }
    }

    // MARK: - Grouped Past Meetings

    private var groupedMeetings: [Date: [MeetingRecord]] {
        let filtered = searchText.isEmpty ? meetings : meetings.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
        }
        var groups: [Date: [MeetingRecord]] = [:]
        let cal = Calendar.current
        for meeting in filtered {
            let day = cal.startOfDay(for: meeting.startTime)
            groups[day, default: []].append(meeting)
        }
        return groups
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: folderId != nil ? "folder" : "waveform.circle")
                .font(.system(size: 36))
                .foregroundStyle(.quaternary)
            Text(folderId != nil ? "No Meetings in Folder" : "No Meetings Yet")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(folderId != nil
                 ? "Drag meetings here or right-click a meeting\nto move it to this folder."
                 : "Start a recording from the menu bar\nor connect your calendar in Settings.")
                .font(.callout)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    // MARK: - Data

    private func loadAll() async {
        await loadMeetings()

        // Only load upcoming events for All Meetings view
        if folderId == nil {
            if let token = KeychainManager.shared.get(.googleOAuthToken) {
                await CalendarManager.shared.setGoogleToken(token)
                logger.info("Restored Google token for calendar fetch")
            }

            var events = await CalendarManager.shared.getUpcomingMeetings(minutes: 1440)
            logger.info("Upcoming events (24h): \(events.count)")
            if events.count < 5 {
                let extended = await CalendarManager.shared.getUpcomingMeetings(minutes: 4320)
                events = Array(extended.prefix(5))
                logger.info("Extended to 72h: \(events.count) events")
            }
            for e in events {
                logger.info("  Event: \(e.title) at \(e.startDate)")
            }
            await MainActor.run { upcomingEvents = events }
        }
    }

    private func loadMeetings() async {
        if let folderId {
            if let fetched = try? await MeetingStore.shared.getMeetingsInFolder(folderId: folderId) {
                await MainActor.run { meetings = fetched }
            }
        } else {
            if let fetched = try? await MeetingStore.shared.getAllMeetings() {
                await MainActor.run { meetings = fetched }
            }
        }
    }

    private func formatSectionDate(_ date: Date) -> String {
        ScribeDateFormatting.sectionDate(date)
    }
}

// MARK: - Upcoming Event Row

struct UpcomingEventRow: View {
    let event: CalendarManager.UpcomingMeeting
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            // Date badge
            VStack(spacing: 0) {
                Text(dayNumber)
                    .font(.title3)
                    .fontWeight(.bold)
                Text(dayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 36)

            // Accent bar
            RoundedRectangle(cornerRadius: 2)
                .fill(.blue)
                .frame(width: 3, height: 36)

            // Event info
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.callout)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text(formatTime(event.startDate))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Source badge
            Image(systemName: "globe")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isHovered ? Color.primary.opacity(0.04) : .clear, in: RoundedRectangle(cornerRadius: 6))
        .onHover { isHovered = $0 }
        .animation(Anim.fast, value: isHovered)
    }

    private var dayNumber: String { ScribeDateFormatting.dayNumber(event.startDate) }
    private var dayName: String { ScribeDateFormatting.dayName(event.startDate) }
    private func formatTime(_ date: Date) -> String { ScribeDateFormatting.time(date) }
}

// MARK: - Past Meeting Row

struct PastMeetingRow: View {
    let meeting: MeetingRecord
    let isSelected: Bool
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            // Date badge (same style as upcoming)
            VStack(spacing: 0) {
                Text(dayNumber)
                    .font(.title3)
                    .fontWeight(.bold)
                Text(dayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 36)

            // Accent bar with icon fallback for colorblind users
            ZStack {
                RoundedRectangle(cornerRadius: 2)
                    .fill(accentBarColor)
                    .frame(width: 3, height: 36)
            }
            .accessibilityLabel(stateAccessibilityLabel)

            // Title + subtitle
            VStack(alignment: .leading, spacing: 2) {
                Text(meeting.title)
                    .font(.callout)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text(subtitleText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // State indicator with text (non-color fallback)
            if meeting.state == "recording" {
                HStack(spacing: 3) {
                    Image(systemName: "record.circle")
                        .font(.caption2)
                    Text("Scribing")
                        .font(.caption2)
                }
                .foregroundStyle(.green)
            } else if meeting.state == "processing" {
                HStack(spacing: 3) {
                    Image(systemName: "ellipsis.circle")
                        .font(.caption2)
                    Text("Processing")
                        .font(.caption2)
                }
                .foregroundStyle(.orange)
            }

            // Time
            Text(formatTime(meeting.startTime))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor.opacity(0.1) : (isHovered ? Color.primary.opacity(0.04) : .clear), in: RoundedRectangle(cornerRadius: 6))
        .onHover { isHovered = $0 }
        .animation(Anim.fast, value: isHovered)
    }

    private var dayNumber: String { ScribeDateFormatting.dayNumber(meeting.startTime) }
    private var dayName: String { ScribeDateFormatting.dayName(meeting.startTime) }

    private var stateAccessibilityLabel: String {
        switch meeting.state {
        case "recording": return "Recording"
        case "complete": return "Complete"
        case "processing": return "Processing"
        default: return "Pending"
        }
    }

    private var accentBarColor: Color {
        switch meeting.state {
        case "recording": return .red
        case "complete": return .green
        case "processing": return .orange
        default: return .secondary.opacity(0.4)
        }
    }

    private var subtitleText: String {
        if let duration = meeting.duration, duration > 0 {
            let mins = Int(duration) / 60
            if mins < 1 { return "\(Int(duration))s" }
            if mins < 60 { return "\(mins) min" }
            return "\(mins / 60)h \(mins % 60)m"
        }
        switch meeting.state {
        case "recording": return "Scribing..."
        case "processing": return "Processing..."
        default: return meeting.state
        }
    }

    private func formatTime(_ date: Date) -> String { ScribeDateFormatting.time(date) }
}

// MARK: - Badge (reusable)

struct MeetingStateBadge: View {
    let state: String

    var body: some View {
        HStack(spacing: 3) {
            if state == "recording" {
                Circle().fill(.red).frame(width: 6, height: 6)
            }
            Text(displayText)
                .font(.caption2)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(badgeColor.opacity(0.12), in: Capsule())
        .foregroundStyle(badgeColor)
    }

    private var displayText: String {
        switch state {
        case "recording": return "Scribing"
        case "processing": return "Processing"
        case "complete": return "Complete"
        case "ended": return "Ended"
        default: return state
        }
    }

    private var badgeColor: Color {
        switch state {
        case "recording": return .green
        case "processing": return .orange
        case "complete": return .secondary
        case "ended": return .blue
        default: return .secondary
        }
    }
}
