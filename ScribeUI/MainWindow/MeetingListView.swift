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

    public init(selectedMeetingId: Binding<UUID?>, folderId: UUID?, folders: [Folder]) {
        self._selectedMeetingId = selectedMeetingId
        self.folderId = folderId
        self.folders = folders
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Design: header bar "MEETINGS · count" with filter/sort icons
            HStack(spacing: 8) {
                MonoSectionLabel("MEETINGS · \(meetings.count)")
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .overlay(alignment: .bottom) {
                Rectangle().fill(MonoColors.divider).frame(height: 1)
            }

            List {
                // Upcoming section (only in All Meetings, not folder views)
                if folderId == nil && !upcomingEvents.isEmpty {
                    Section {
                        ForEach(upcomingEvents, id: \.id) { event in
                            UpcomingEventRow(event: event)
                                .listRowInsets(EdgeInsets(top: 2, leading: 6, bottom: 2, trailing: 6))
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        }
                    } header: {
                        MonoSectionLabel("UPCOMING · \(upcomingEvents.count)")
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
                                    .contentShape(Rectangle())
                                    .onTapGesture { selectedMeetingId = meeting.id }
                                    .listRowInsets(EdgeInsets(top: 2, leading: 6, bottom: 2, trailing: 6))
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                                    .draggable(meeting.id.uuidString)
                                    .contextMenu {
                                        meetingContextMenu(for: meeting)
                                    }
                            }
                        } header: {
                            MonoSectionLabel(formatSectionDate(date).uppercased())
                                .textCase(nil)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(MonoColors.bg)
        .safeAreaInset(edge: .bottom) {
            if folderId == nil {
                Button {
                    let meetingId = UUID()
                    let title = "Meeting " + ScribeDateFormatting.dateTime(Date())
                    NotificationCenter.default.post(name: .startNewMeeting, object: ["meetingId": meetingId, "title": title])
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "mic")
                            .font(MonoFont.sans(size: TypeScale.md))
                        Text("Start new meeting")
                            .font(MonoFont.mono(size: TypeScale.sm, weight: .semibold))
                        KbdView("⌘N")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(MonoColors.accentBg, in: RoundedRectangle(cornerRadius: Radius.md))
                    .foregroundStyle(MonoColors.accent)
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
        } // end VStack wrapper
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

    // MARK: - Grouped Past Meetings

    private var groupedMeetings: [Date: [MeetingRecord]] {
        var groups: [Date: [MeetingRecord]] = [:]
        let cal = Calendar.current
        for meeting in meetings {
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
                .foregroundStyle(MonoColors.textFaint)
            Text(folderId != nil ? "No Meetings in Folder" : "No Meetings Yet")
                .font(MonoFont.sans(size: TypeScale.md, weight: .medium))
                .foregroundStyle(MonoColors.textMuted)
            Text(folderId != nil
                 ? "Drag meetings here or right-click a meeting\nto move it to this folder."
                 : "Start a recording from the menu bar\nor connect your calendar in Settings.")
                .font(MonoFont.sans(size: TypeScale.sm))
                .foregroundStyle(MonoColors.textFaint)
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
            // Monospace time label
            Text(relativeTime)
                .font(MonoFont.mono(size: TypeScale.sm))
                .foregroundStyle(MonoColors.textFaint)
                .frame(width: 50, alignment: .trailing)

            // Accent bar
            RoundedRectangle(cornerRadius: 1)
                .fill(MonoColors.accent)
                .frame(width: 2, height: 36)

            // Event info
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(MonoFont.sans(size: TypeScale.base, weight: .medium))
                    .foregroundStyle(MonoColors.text)
                    .lineLimit(1)
                Text(formatTime(event.startDate))
                    .font(MonoFont.mono(size: TypeScale.xs))
                    .foregroundStyle(MonoColors.textFaint)
            }

            Spacer()

            // Source tag
            MonoTag(sourceLabel.lowercased())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isHovered ? MonoColors.bgHover : .clear, in: RoundedRectangle(cornerRadius: Radius.md))
        .onHover { isHovered = $0 }
        .animation(Anim.fast, value: isHovered)
    }

    private var relativeTime: String {
        let minutes = Int(event.startDate.timeIntervalSinceNow / 60)
        if minutes < 0 { return formatTime(event.startDate) }
        if minutes < 60 { return "+\(minutes)m" }
        let hours = minutes / 60
        return "+\(hours)h"
    }

    private var sourceLabel: String {
        if let url = event.meetingURL?.lowercased() {
            if url.contains("zoom") { return "zoom" }
            if url.contains("meet.google") { return "meet" }
            if url.contains("teams") { return "teams" }
        }
        return "cal"
    }

    private func formatTime(_ date: Date) -> String { ScribeDateFormatting.time(date) }
}

// MARK: - Past Meeting Row

struct PastMeetingRow: View {
    let meeting: MeetingRecord
    let isSelected: Bool
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            // Monospace time
            Text(formatTime(meeting.startTime))
                .font(MonoFont.mono(size: TypeScale.sm))
                .foregroundStyle(isSelected ? MonoColors.accentText : MonoColors.textFaint)
                .frame(width: 50, alignment: .trailing)

            // Accent bar with state color
            RoundedRectangle(cornerRadius: 1)
                .fill(accentBarColor)
                .frame(width: 2, height: 34)
                .accessibilityLabel(stateAccessibilityLabel)

            // Title + subtitle
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if meeting.state == "recording" {
                        RecDot(size: 5, color: MonoColors.live)
                    }
                    Text(meeting.title)
                        .font(MonoFont.sans(size: TypeScale.base, weight: .medium))
                        .foregroundStyle(MonoColors.text)
                        .lineLimit(1)
                }
                Text(subtitleText)
                    .font(MonoFont.mono(size: TypeScale.xs))
                    .foregroundStyle(MonoColors.textFaint)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            // Duration on the right
            if let duration = meeting.duration, duration > 0 {
                Text(ScribeDateFormatting.duration(duration))
                    .font(MonoFont.mono(size: TypeScale.xs))
                    .foregroundStyle(isSelected ? MonoColors.accentText : MonoColors.textFaint)
            } else if meeting.state == "recording" {
                Text("scribing")
                    .font(MonoFont.mono(size: TypeScale.xs))
                    .foregroundStyle(MonoColors.live)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            isSelected ? MonoColors.accentBg : (isHovered ? MonoColors.bgHover : .clear),
            in: RoundedRectangle(cornerRadius: Radius.md)
        )
        .overlay(alignment: .leading) {
            if isSelected {
                RoundedRectangle(cornerRadius: 1)
                    .fill(MonoColors.accent)
                    .frame(width: 2)
                    .padding(.vertical, 4)
            }
        }
        .onHover { isHovered = $0 }
        .animation(Anim.fast, value: isHovered)
        .animation(Anim.fast, value: isSelected)
    }

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
        case "recording": return MonoColors.live
        case "complete": return MonoColors.accent
        case "processing": return MonoColors.warn
        default: return MonoColors.textFaint.opacity(0.4)
        }
    }

    private var subtitleText: String {
        var parts: [String] = []

        // Folder name if available (kebab-case style)
        // Duration or state
        if let duration = meeting.duration, duration > 0 {
            let mins = Int(duration) / 60
            if mins < 1 { parts.append("\(Int(duration))s") }
            else if mins < 60 { parts.append("\(mins)m") }
            else { parts.append("\(mins / 60)h\(mins % 60)m") }
        } else {
            switch meeting.state {
            case "recording": parts.append("scribing…")
            case "processing": parts.append("processing…")
            default: parts.append(meeting.state)
            }
        }

        // Speaker count from participants
        if let participantsJSON = meeting.participants,
           let data = participantsJSON.data(using: .utf8),
           let names = try? JSONDecoder().decode([String].self, from: data),
           !names.isEmpty {
            parts.append("\(names.count)sp")
        }

        return parts.joined(separator: " · ")
    }

    private func formatTime(_ date: Date) -> String { ScribeDateFormatting.time(date) }
}

// MARK: - Badge (reusable)

struct MeetingStateBadge: View {
    let state: String

    var body: some View {
        HStack(spacing: 3) {
            if state == "recording" {
                RecDot(size: 6, color: MonoColors.live)
            }
            Text(displayText)
                .font(MonoFont.mono(size: TypeScale.xs, weight: .semibold))
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
        case "recording": return MonoColors.live
        case "processing": return MonoColors.warn
        case "complete": return MonoColors.textMuted
        case "ended": return MonoColors.accent
        default: return MonoColors.textMuted
        }
    }
}
