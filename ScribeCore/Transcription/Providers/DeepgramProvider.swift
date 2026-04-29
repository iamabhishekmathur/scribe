import Foundation
@preconcurrency import Starscream
import os

private let logger = Logger(subsystem: "com.scribe.app", category: "DeepgramProvider")

/// Mutable state guarded by the provider's lock. Held inside `OSAllocatedUnfairLock`
/// so it can be touched safely from sync event callbacks AND async tasks.
private struct ProviderState {
    var socket: WebSocket?
    var isConnected: Bool = false
    var shouldStayConnected: Bool = false
    var keepAliveTask: Task<Void, Never>?
    var reconnectTask: Task<Void, Never>?
}

/// Deepgram real-time transcription via WebSocket.
/// Streams 16kHz mono PCM audio, receives JSON transcription results with diarization.
///
/// Resilience:
/// - Sends a `KeepAlive` JSON frame every `keepAliveInterval` to prevent server-side idle close.
/// - On unexpected mid-stream disconnect, automatically reconnects with exponential backoff
///   (`initialReconnectDelay` doubling up to `maxReconnectDelay`) until the user calls `disconnect()`.
/// - Audio sent during a reconnect window is dropped (the stream is real-time — buffering would
///   accumulate latency and Deepgram would reject stale samples anyway).
public final class DeepgramProvider: TranscriptionProvider, @unchecked Sendable {
    private let apiKey: String
    private let model: String
    private let language: String
    private let diarize: Bool

    // Tunables (exposed for tests)
    let keepAliveInterval: TimeInterval
    let initialReconnectDelay: TimeInterval
    let maxReconnectDelay: TimeInterval

    private let state = OSAllocatedUnfairLock(initialState: ProviderState())
    private var resultsContinuation: AsyncStream<TranscriptionResult>.Continuation?

    public var isConnected: Bool {
        state.withLock { $0.isConnected }
    }

    public let results: AsyncStream<TranscriptionResult>

    public init(
        apiKey: String,
        model: String = "nova-2",
        language: String = "en",
        diarize: Bool = true,
        keepAliveInterval: TimeInterval = 5.0,
        initialReconnectDelay: TimeInterval = 1.0,
        maxReconnectDelay: TimeInterval = 10.0
    ) {
        self.apiKey = apiKey
        self.model = model
        self.language = language
        self.diarize = diarize
        self.keepAliveInterval = keepAliveInterval
        self.initialReconnectDelay = initialReconnectDelay
        self.maxReconnectDelay = maxReconnectDelay

        var continuation: AsyncStream<TranscriptionResult>.Continuation?
        self.results = AsyncStream { continuation = $0 }
        self.resultsContinuation = continuation
    }

    // MARK: - Public API

    public func connect() async throws {
        state.withLock { $0.shouldStayConnected = true }

        try await establishConnection()
        startKeepAlive()
    }

    public func sendAudio(_ data: Data) async throws {
        let sock: WebSocket? = state.withLock { s in
            s.isConnected ? s.socket : nil
        }
        // Drop during reconnect window rather than throwing — caller is the realtime
        // audio loop and noisy throws would just spam logs.
        sock?.write(data: data)
    }

    public func disconnect() async {
        let (sock, kaTask, rcTask) = state.withLock { s -> (WebSocket?, Task<Void, Never>?, Task<Void, Never>?) in
            s.shouldStayConnected = false
            let oldSock = s.socket
            let oldKA = s.keepAliveTask
            let oldRC = s.reconnectTask
            s.socket = nil
            s.keepAliveTask = nil
            s.reconnectTask = nil
            s.isConnected = false
            return (oldSock, oldKA, oldRC)
        }

        kaTask?.cancel()
        rcTask?.cancel()

        if let sock {
            if let closeData = "{\"type\": \"CloseStream\"}".data(using: .utf8) {
                sock.write(data: closeData)
            }
            sock.disconnect()
        }
        resultsContinuation?.finish()
    }

    // MARK: - Connection establishment

    private func buildURL() throws -> URL {
        var params = [
            "model=\(model)",
            "language=\(language)",
            "punctuate=true",
            "interim_results=true",
            "utterance_end_ms=1000",
            "vad_events=true",
            "encoding=linear16",
            "sample_rate=16000",
            "channels=1",
        ]
        if diarize {
            params.append("diarize=true")
        }
        let query = params.joined(separator: "&")
        guard let url = URL(string: "wss://api.deepgram.com/v1/listen?\(query)") else {
            throw TranscriptionError.connectionFailed("Invalid URL")
        }
        return url
    }

    /// Open a WebSocket and resolve once `.connected` arrives. Sets up the long-lived event
    /// handler that handles results, keepalive replies, and triggers reconnect on disconnect.
    private func establishConnection() async throws {
        let url = try buildURL()
        var request = URLRequest(url: url)
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")

        let socket = WebSocket(request: request)

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            // Continuation guard local to this attempt — captured into the event closure.
            let resumeBox = ResumeBox()

            socket.onEvent = { [weak self] event in
                guard let self else { return }
                switch event {
                case .connected:
                    self.state.withLock { s in
                        s.isConnected = true
                        s.socket = socket
                    }
                    logger.info("Deepgram connected")
                    resumeBox.resumeOnce { cont.resume() }

                case .disconnected(let reason, let code):
                    self.handleSocketDrop(label: "disconnected (code=\(code), reason=\(reason))",
                                          resumeBox: resumeBox,
                                          cont: cont,
                                          reasonForResume: reason)

                case .text(let text):
                    self.handleMessage(text)

                case .error(let error):
                    self.handleSocketDrop(label: "socket error: \(error?.localizedDescription ?? "unknown")",
                                          resumeBox: resumeBox,
                                          cont: cont,
                                          reasonForResume: error?.localizedDescription ?? "Unknown")

                case .cancelled:
                    self.handleSocketDrop(label: "socket cancelled",
                                          resumeBox: resumeBox,
                                          cont: cont,
                                          reasonForResume: "Cancelled")

                default:
                    break
                }
            }

            socket.connect()
        }
    }

    // MARK: - Socket-drop handling

    /// Common handling for any event that ends a socket lifecycle: disconnected/error/cancelled.
    /// Resumes the pending connect continuation if it's still pending; otherwise (mid-stream
    /// drop) schedules a reconnect.
    private func handleSocketDrop(
        label: String,
        resumeBox: ResumeBox,
        cont: CheckedContinuation<Void, Error>,
        reasonForResume: String
    ) {
        let (wasOpen, stillWanted) = state.withLock { s -> (Bool, Bool) in
            let prev = s.isConnected
            s.isConnected = false
            return (prev, s.shouldStayConnected)
        }

        let didResume = resumeBox.resumeOnce {
            cont.resume(throwing: TranscriptionError.connectionFailed(reasonForResume))
        }
        if !didResume && wasOpen && stillWanted {
            logger.warning("Deepgram \(label, privacy: .public) — reconnecting")
            scheduleReconnect()
        }
    }

    // MARK: - Reconnect

    private func scheduleReconnect() {
        let initial = initialReconnectDelay
        let maxDelay = maxReconnectDelay

        let newTask: Task<Void, Never> = Task { [weak self] in
            guard let self else { return }
            var delay = initial
            while !Task.isCancelled {
                let stillWanted = self.state.withLock { $0.shouldStayConnected }
                guard stillWanted else { return }

                logger.info("Deepgram reconnect attempt in \(delay)s")
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                if Task.isCancelled { return }

                let stillWanted2 = self.state.withLock { $0.shouldStayConnected }
                guard stillWanted2 else { return }

                do {
                    try await self.establishConnection()
                    logger.info("Deepgram reconnected after backoff")
                    return
                } catch {
                    logger.error("Deepgram reconnect failed: \(error.localizedDescription)")
                    delay = min(delay * 2, maxDelay)
                }
            }
        }

        // Atomically swap in the new reconnect task and cancel any prior one.
        let prior = state.withLock { s -> Task<Void, Never>? in
            let old = s.reconnectTask
            s.reconnectTask = newTask
            return old
        }
        prior?.cancel()
    }

    // MARK: - Keep-alive

    private func startKeepAlive() {
        let interval = keepAliveInterval
        let newTask: Task<Void, Never> = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                if Task.isCancelled { return }
                guard let self else { return }
                let snapshot: (Bool, WebSocket?, Bool) = self.state.withLock { s in
                    (s.isConnected, s.socket, s.shouldStayConnected)
                }
                let (connected, sock, stillWanted) = snapshot
                guard stillWanted else { return }
                if connected, let sock {
                    sock.write(string: "{\"type\":\"KeepAlive\"}")
                }
            }
        }

        let prior = state.withLock { s -> Task<Void, Never>? in
            let old = s.keepAliveTask
            s.keepAliveTask = newTask
            return old
        }
        prior?.cancel()
    }

    // MARK: - Message Parsing

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        guard let type = json["type"] as? String, type == "Results" else { return }
        parseResults(json)
    }

    private func parseResults(_ json: [String: Any]) {
        guard let channelObj = json["channel"] as? [String: Any],
              let alternatives = channelObj["alternatives"] as? [[String: Any]],
              let first = alternatives.first,
              let transcript = first["transcript"] as? String,
              !transcript.isEmpty else {
            return
        }

        let isFinal = json["is_final"] as? Bool ?? false
        let confidence = first["confidence"] as? Double
        let start = json["start"] as? Double ?? 0
        let duration = json["duration"] as? Double ?? 0

        var speaker: String?
        var speakerIndex: Int?
        if let words = first["words"] as? [[String: Any]], let firstWord = words.first {
            if let idx = firstWord["speaker"] as? Int {
                speakerIndex = idx
                speaker = "Speaker \(idx)"
            }
        }

        let result = TranscriptionResult(
            text: transcript,
            startTime: start,
            endTime: start + duration,
            speaker: speaker,
            speakerIndex: speakerIndex,
            confidence: confidence,
            isFinal: isFinal
        )

        resultsContinuation?.yield(result)
    }
}

/// One-shot resume guard for an async continuation. Internal helper — multiple
/// WebSocket events can race to resolve the same continuation; only the first wins.
private final class ResumeBox: @unchecked Sendable {
    private let lock = NSLock()
    private var resumed = false

    /// Returns true if this call performed the resume.
    @discardableResult
    func resumeOnce(_ block: () -> Void) -> Bool {
        lock.lock()
        if resumed {
            lock.unlock()
            return false
        }
        resumed = true
        lock.unlock()
        block()
        return true
    }
}
