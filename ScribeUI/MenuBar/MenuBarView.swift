import SwiftUI
import ScribeCore
import os

private let logger = Logger(subsystem: "com.scribe.app", category: "MenuBar")

public struct MenuBarView: View {
    @ObservedObject var appState: AppState
    @ObservedObject private var coordinator = RecordingCoordinator.shared
    @State private var upcomingEvents: [CalendarManager.UpcomingMeeting] = []

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Status header
            if coordinator.isRecording {
                HStack(spacing: 6) {
                    Circle().fill(.red).frame(width: 8, height: 8)
                    Text("Scribing").font(.headline)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)

                Button("Stop Scribing") {
                    appState.stopRecording()
                    Task {
                        await coordinator.stopRecording()
                        await MainActor.run { appState.finishProcessing() }
                    }
                }
                .padding(.horizontal, 12)
            } else {
                HStack(spacing: 6) {
                    Text("Scribe")
                        .font(.headline)
                    Text("Idle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            }

            Divider()

            // Upcoming meetings
            if !upcomingEvents.isEmpty {
                Text("Upcoming")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.top, 6)

                ForEach(upcomingEvents.prefix(7), id: \.id) { event in
                    Button {
                        openMeetingForEvent(event)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.title)
                                .font(.callout)
                                .lineLimit(1)
                            Text(formatEventTime(event.startDate))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                }

                Divider()
            }

            if !coordinator.isRecording {
                Button("Start Scribing") {
                    let meetingId = UUID()
                    let title = "Meeting \(formattedDate)"
                    appState.startRecording(meetingId: meetingId)
                    Task {
                        await coordinator.startRecording(meetingId: meetingId, title: title)
                    }
                    // Open the meeting page
                    NotificationCenter.default.post(name: .openMainWindow, object: nil)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        NotificationCenter.default.post(name: .openMeeting, object: meetingId)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            }

            Divider()

            Button("Open Scribe") {
                NotificationCenter.default.post(name: .openMainWindow, object: nil)
            }
            .keyboardShortcut("o")

            Button("Settings...") {
                NotificationCenter.default.post(name: .openMainWindow, object: nil)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    NotificationCenter.default.post(name: .openSettingsWindow, object: nil)
                }
            }
            .keyboardShortcut(",")

            Button("Check for Updates...") {
                Task {
                    if let release = await UpdateChecker.shared.checkForUpdate() {
                        await MainActor.run {
                            let alert = NSAlert()
                            alert.messageText = "Scribe \(release.version) Available"
                            alert.informativeText = release.releaseNotes.isEmpty
                                ? "A new version of Scribe is available."
                                : release.releaseNotes
                            alert.alertStyle = .informational
                            alert.addButton(withTitle: "Download")
                            alert.addButton(withTitle: "Later")
                            if alert.runModal() == .alertFirstButtonReturn {
                                NSWorkspace.shared.open(release.downloadURL)
                            }
                        }
                    } else {
                        await MainActor.run {
                            let alert = NSAlert()
                            alert.messageText = "You're Up to Date"
                            alert.informativeText = "Scribe is running the latest version."
                            alert.alertStyle = .informational
                            alert.addButton(withTitle: "OK")
                            alert.runModal()
                        }
                    }
                }
            }

            Divider()

            Button("Quit Scribe") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .task {
            // Wait for startup calendar sync to complete
            try? await Task.sleep(for: .seconds(3))
            await loadUpcoming()
        }
        .onAppear {
            // Reload every time menu opens
            Task { await loadUpcoming() }
        }
    }

    private func loadUpcoming() async {
        if let token = KeychainManager.shared.get(.googleOAuthToken) {
            await CalendarManager.shared.setGoogleToken(token)
        }
        var events = await CalendarManager.shared.getUpcomingMeetings(minutes: 1440)
        if events.count < 5 {
            events = Array((await CalendarManager.shared.getUpcomingMeetings(minutes: 4320)).prefix(7))
        }
        await MainActor.run { upcomingEvents = events }
    }

    private func openMeetingForEvent(_ event: CalendarManager.UpcomingMeeting) {
        // Create a meeting record for this calendar event and open it
        let meetingId = UUID()
        Task {
            let meeting = MeetingRecord(
                id: meetingId,
                title: event.title,
                calendarEventId: event.id,
                meetingURL: event.meetingURL
            )
            try? await MeetingStore.shared.createMeeting(meeting)
            NotificationCenter.default.post(name: .openMainWindow, object: nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                NotificationCenter.default.post(name: .openMeeting, object: meetingId)
            }
        }
    }

    private func formatEventTime(_ date: Date) -> String {
        ScribeDateFormatting.eventTime(date)
    }

    private var formattedDate: String {
        ScribeDateFormatting.dateTime(Date())
    }
}
