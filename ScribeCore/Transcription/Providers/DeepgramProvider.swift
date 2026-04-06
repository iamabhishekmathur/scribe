import Foundation
import Starscream

/// Deepgram real-time transcription via WebSocket.
/// Streams 16kHz mono PCM audio, receives JSON transcription results with diarization.
public final class DeepgramProvider: TranscriptionProvider, @unchecked Sendable {
    private let apiKey: String
    private var socket: WebSocket?
    private var resultsContinuation: AsyncStream<TranscriptionResult>.Continuation?
    private var _isConnected = false

    private let model: String
    private let language: String
    private let diarize: Bool

    public var isConnected: Bool { _isConnected }

    public let results: AsyncStream<TranscriptionResult>

    public init(
        apiKey: String,
        model: String = "nova-2",
        language: String = "en",
        diarize: Bool = true
    ) {
        self.apiKey = apiKey
        self.model = model
        self.language = language
        self.diarize = diarize

        var continuation: AsyncStream<TranscriptionResult>.Continuation?
        self.results = AsyncStream { continuation = $0 }
        self.resultsContinuation = continuation
    }

    public func connect() async throws {
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

        var request = URLRequest(url: url)
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")

        let socket = WebSocket(request: request)
        self.socket = socket

        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            var resumed = false

            socket.onEvent = { [weak self] event in
                guard let self else { return }
                switch event {
                case .connected:
                    self._isConnected = true
                    if !resumed {
                        resumed = true
                        cont.resume()
                    }

                case .disconnected(let reason, _):
                    self._isConnected = false
                    if !resumed {
                        resumed = true
                        cont.resume(throwing: TranscriptionError.connectionFailed(reason))
                    }

                case .text(let text):
                    self.handleMessage(text)

                case .error(let error):
                    self._isConnected = false
                    if !resumed {
                        resumed = true
                        cont.resume(throwing: TranscriptionError.connectionFailed(error?.localizedDescription ?? "Unknown"))
                    }

                case .cancelled:
                    self._isConnected = false
                    if !resumed {
                        resumed = true
                        cont.resume(throwing: TranscriptionError.connectionFailed("Cancelled"))
                    }

                default:
                    break
                }
            }

            socket.connect()
        }
    }

    public func sendAudio(_ data: Data) async throws {
        guard _isConnected, let socket else {
            throw TranscriptionError.notConnected
        }
        socket.write(data: data)
    }

    public func disconnect() async {
        if let closeData = "{\"type\": \"CloseStream\"}".data(using: .utf8) {
            socket?.write(data: closeData)
        }
        socket?.disconnect()
        socket = nil
        _isConnected = false
        resultsContinuation?.finish()
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
