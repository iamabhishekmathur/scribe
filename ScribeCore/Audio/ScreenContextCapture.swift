import ScreenCaptureKit
import Foundation
import CoreGraphics

/// Captures periodic screenshots during screen sharing and sends to Vision LLM
/// for context extraction. Stores only extracted text, not images.
public actor ScreenContextCapture {
    private var captureTask: Task<Void, Never>?
    private var _isCapturing = false
    public var isCapturing: Bool { _isCapturing }

    private let captureInterval: TimeInterval
    private let meetingId: UUID

    public init(meetingId: UUID, captureInterval: TimeInterval = 15.0) {
        self.meetingId = meetingId
        self.captureInterval = captureInterval
    }

    /// Start periodic screen capture and context extraction
    public func start() async {
        guard !_isCapturing else { return }
        _isCapturing = true

        captureTask = Task { [weak self] in
            while !Task.isCancelled {
                if let self {
                    await self.captureAndExtract()
                }
                try? await Task.sleep(for: .seconds(self?.captureInterval ?? 15))
            }
        }
    }

    public func stop() {
        captureTask?.cancel()
        captureTask = nil
        _isCapturing = false
    }

    private func captureAndExtract() async {
        do {
            guard let imageData = try await captureScreen() else { return }

            let provider = await LLMManager.shared.provider
            guard provider.supportsVision else { return }

            let extractedText = try await provider.completeWithImage(
                messages: [
                    LLMMessage(role: .system, content: """
                        Extract all visible text and describe visual content from this screenshot. \
                        Include: slide text, document content, code snippets, diagram descriptions, \
                        UI elements, and any other relevant information. Be thorough but concise.
                        """),
                    LLMMessage(role: .user, content: "What is shown on screen?")
                ],
                imageData: imageData
            )

            guard !extractedText.isEmpty else { return }

            let context = ScreenContext(
                meetingId: meetingId,
                timestamp: Date().timeIntervalSinceReferenceDate,
                extractedText: extractedText,
                sourceDescription: "Screen capture"
            )
            try await MeetingStore.shared.addScreenContext(context)
        } catch {
            // Skip failed captures silently
        }
    }

    private func captureScreen() async throws -> Data? {
        let content = try await SCShareableContent.current
        guard let display = content.displays.first else { return nil }

        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.width = Int(display.width) / 2  // Half resolution to save bandwidth
        config.height = Int(display.height) / 2
        config.pixelFormat = kCVPixelFormatType_32BGRA

        let image = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        )

        // Convert CGImage to PNG data
        let rep = NSBitmapImageRep(cgImage: image)
        return rep.representation(using: .png, properties: [:])
    }
}
