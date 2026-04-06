import Foundation
import Starscream

/// AssemblyAI real-time transcription via WebSocket.
/// Sends base64-encoded PCM audio, receives JSON results.
public final class AssemblyAIProvider: TranscriptionProvider, @unchecked Sendable {
    private let apiKey: String
    private var socket: WebSocket?
    private var resultsContinuation: AsyncStream<TranscriptionResult>.Continuation?
    private var _isConnected = false

    public var isConnected: Bool { _isConnected }

    public let results: AsyncStream<TranscriptionResult>

    public init(apiKey: String) {
        self.apiKey = apiKey

        var continuation: AsyncStream<TranscriptionResult>.Continuation?
        self.results = AsyncStream { continuation = $0 }
        self.resultsContinuation = continuation
    }

    public func connect() async throws {
        let params = "sample_rate=16000&encoding=pcm_s16le"
        guard let url = URL(string: "wss://api.assemblyai.com/v2/realtime/ws?\(params)") else {
            throw TranscriptionError.connectionFailed("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "Authorization")

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

        let base64Audio = data.base64EncodedString()
        let message = "{\"audio_data\": \"\(base64Audio)\"}"
        socket.write(string: message)
    }

    public func disconnect() async {
        socket?.write(string: "{\"terminate_session\": true}")
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

        guard let messageType = json["message_type"] as? String else { return }

        switch messageType {
        case "FinalTranscript", "PartialTranscript":
            parseTranscript(json, isFinal: messageType == "FinalTranscript")
        default:
            break
        }
    }

    private func parseTranscript(_ json: [String: Any], isFinal: Bool) {
        guard let transcript = json["text"] as? String, !transcript.isEmpty else { return }

        let audioStart = (json["audio_start"] as? Double ?? 0) / 1000.0
        let audioEnd = (json["audio_end"] as? Double ?? 0) / 1000.0
        let confidence = json["confidence"] as? Double

        let result = TranscriptionResult(
            text: transcript,
            startTime: audioStart,
            endTime: audioEnd,
            confidence: confidence,
            isFinal: isFinal
        )

        resultsContinuation?.yield(result)
    }
}
