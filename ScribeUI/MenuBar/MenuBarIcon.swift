import SwiftUI
import ScribeCore

public struct MenuBarIcon: View {
    let state: RecordingState
    @ObservedObject private var coordinator = RecordingCoordinator.shared

    public init(state: RecordingState) {
        self.state = state
    }

    public var body: some View {
        if coordinator.isRecording {
            // Filled/inverted version when scribing — subtle, not alarming
            Image(systemName: "waveform.circle.fill")
                .accessibilityLabel("Scribe — recording")
        } else {
            switch state {
            case .idle:
                Image(systemName: "waveform.circle")
                    .accessibilityLabel("Scribe — idle")
            case .recording:
                Image(systemName: "waveform.circle.fill")
                    .accessibilityLabel("Scribe — recording")
            case .processing:
                Image(systemName: "ellipsis.circle")
                    .accessibilityLabel("Scribe — processing")
            }
        }
    }
}
