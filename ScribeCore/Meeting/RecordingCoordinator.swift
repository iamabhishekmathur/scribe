@preconcurrency import AVFoundation
import Foundation
import os

private let logger = Logger(subsystem: "com.scribe.app", category: "Recording")

/// Wires together audio capture, transcription, and AI services for a recording session.
@MainActor
public final class RecordingCoordinator: ObservableObject {
    public static let shared = RecordingCoordinator()

    private let audioCaptureManager = AudioCaptureManager()
    private let transcriptionManager = TranscriptionManager()

    @Published public var isRecording = false
    @Published public var audioLevel: Float = 0
    @Published public var currentMeetingId: UUID?

    private var levelPollTask: Task<Void, Never>?

    private init() {}

    /// Start a full recording session: audio capture + transcription (if configured)
    public func startRecording(meetingId: UUID, title: String) async {
        guard !isRecording else {
            logger.warning("Already recording, ignoring start request")
            return
        }

        logger.info("Starting recording for meeting: \(meetingId.uuidString)")

        // Create meeting record
        let meeting = MeetingRecord(id: meetingId, title: title)
        try? await MeetingStore.shared.createMeeting(meeting)

        // Try to start audio capture
        var streams: AudioMixer.OutputStreams?
        do {
            streams = try await audioCaptureManager.startCapture()
            logger.info("Audio capture started (mic + system)")
            PermissionsManager.shared.markScreenRecordingGranted()
        } catch {
            logger.warning("Full capture failed (\(error.localizedDescription)), falling back to mic only")
            // Stop any partial capture state before retrying mic-only
            await audioCaptureManager.stopCapture()
            do {
                streams = try await audioCaptureManager.startMicOnly()
                logger.info("Audio capture started (mic only)")
            } catch {
                logger.error("Mic-only capture also failed: \(error.localizedDescription)")
            }
        }

        currentMeetingId = meetingId
        isRecording = true

        // Start polling audio level
        startLevelPolling()

        // Start transcription if audio is available and provider is configured
        if let streams {
            await startTranscriptionIfConfigured(audioStream: streams.transcription, meetingId: meetingId)
            logger.info("Recording session fully started with audio")
        } else {
            logger.warning("Recording session started without audio capture")
        }
    }

    /// Stop the recording session, trigger post-processing
    public func stopRecording() async {
        guard isRecording, let meetingId = currentMeetingId else {
            logger.warning("Not recording, ignoring stop request")
            return
        }

        logger.info("Stopping recording for meeting: \(meetingId.uuidString)")

        // Stop audio capture
        await audioCaptureManager.stopCapture()
        logger.info("Audio capture stopped")

        // Stop transcription
        await transcriptionManager.stop()
        logger.info("Transcription stopped")

        // Stop level polling
        levelPollTask?.cancel()
        levelPollTask = nil
        audioLevel = 0

        // End meeting in DB
        try? await MeetingStore.shared.endMeeting(id: meetingId)
        logger.info("Meeting ended in DB")

        // Notify UI to refresh
        NotificationCenter.default.post(name: Notification.Name("com.scribe.meetingUpdated"), object: nil)

        // Trigger post-meeting AI processing
        isRecording = false
        logger.info("Starting post-meeting processing...")

        // Note: Summarization is NOT triggered automatically — user picks template
        // per-meeting via the "Generate Summary" button. Meeting stays in "ended"
        // state until they explicitly generate a summary.
        Task.detached {
            do {
                try await EnrichmentService.shared.enrichAllNotes(meetingId: meetingId)
                await MainActor.run {
                    logger.info("Note enrichment complete")
                }
            } catch {
                await MainActor.run {
                    logger.error("Note enrichment failed: \(error.localizedDescription)")
                }
            }

            // Export as markdown backup (works even without summary)
            do {
                try await MarkdownExporter.shared.exportMeeting(id: meetingId)
            } catch {
                await MainActor.run {
                    logger.error("Markdown export failed: \(error.localizedDescription)")
                }
            }
        }

        currentMeetingId = nil
    }

    // MARK: - Private

    private func startTranscriptionIfConfigured(audioStream: sending AsyncStream<AVAudioPCMBuffer>, meetingId: UUID) async {
        let settings = AppSettings.shared
        let keychain = KeychainManager.shared
        let keychainKey = keychain.apiKeyForTranscriptionProvider(settings.transcriptionProvider)

        guard let apiKey = keychain.get(keychainKey), !apiKey.isEmpty else {
            logger.info("No transcription API key configured, skipping transcription")
            return
        }

        let provider = TranscriptionManager.createProvider(
            type: settings.transcriptionProvider,
            apiKey: apiKey
        )

        do {
            try await transcriptionManager.start(
                provider: provider,
                audioStream: audioStream,
                meetingId: meetingId
            )
            logger.info("Transcription started with \(settings.transcriptionProvider.rawValue)")
        } catch {
            logger.error("Failed to start transcription: \(error.localizedDescription)")
        }
    }

    private func startLevelPolling() {
        levelPollTask = Task { [weak self] in
            while !Task.isCancelled {
                if let self {
                    let level = await self.audioCaptureManager.audioLevel
                    self.audioLevel = level
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }
}
