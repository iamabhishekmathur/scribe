import Foundation
@preconcurrency import AVFoundation

/// OpenAI Whisper API transcription via REST (chunked approach).
/// Buffers audio into ~5 second chunks, sends as WAV to the Whisper API.
public final class OpenAIWhisperProvider: TranscriptionProvider, @unchecked Sendable {
    private let apiKey: String
    private let model: String
    private var resultsContinuation: AsyncStream<TranscriptionResult>.Continuation?
    private var _isConnected = false

    // Audio buffering
    private var audioBuffer = Data()
    private let chunkDurationSeconds: Double = 5.0
    private let sampleRate: Double = 16000
    private let bytesPerSample = 2 // 16-bit PCM
    private var chunkStartTime: TimeInterval = 0

    public var isConnected: Bool { _isConnected }

    public let results: AsyncStream<TranscriptionResult>

    public init(apiKey: String, model: String = "whisper-1") {
        self.apiKey = apiKey
        self.model = model

        var continuation: AsyncStream<TranscriptionResult>.Continuation?
        self.results = AsyncStream { continuation = $0 }
        self.resultsContinuation = continuation
    }

    public func connect() async throws {
        let url = URL(string: "https://api.openai.com/v1/models/\(model)")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranscriptionError.connectionFailed("Invalid response")
        }

        switch httpResponse.statusCode {
        case 200:
            _isConnected = true
        case 401:
            throw TranscriptionError.invalidAPIKey
        case 429:
            throw TranscriptionError.rateLimited
        default:
            throw TranscriptionError.serverError("HTTP \(httpResponse.statusCode)")
        }
    }

    public func sendAudio(_ data: Data) async throws {
        guard _isConnected else {
            throw TranscriptionError.notConnected
        }

        audioBuffer.append(data)

        let chunkBytes = Int(chunkDurationSeconds * sampleRate) * bytesPerSample
        if audioBuffer.count >= chunkBytes {
            let chunk = audioBuffer.prefix(chunkBytes)
            audioBuffer.removeFirst(chunkBytes)
            let startTime = chunkStartTime
            chunkStartTime += chunkDurationSeconds

            await transcribeChunk(Data(chunk), startTime: startTime)
        }
    }

    public func disconnect() async {
        let remaining = audioBuffer
        let startTime = chunkStartTime
        audioBuffer = Data()
        _isConnected = false

        if !remaining.isEmpty {
            await transcribeChunk(remaining, startTime: startTime)
        }

        resultsContinuation?.finish()
    }

    // MARK: - Whisper API

    private func transcribeChunk(_ pcmData: Data, startTime: TimeInterval) async {
        let wavData = createWAVData(from: pcmData)
        let duration = Double(pcmData.count) / (sampleRate * Double(bytesPerSample))

        let url = URL(string: "https://api.openai.com/v1/audio/transcriptions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        func field(_ name: String, value: String) {
            body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".data(using: .utf8)!)
        }

        // File field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(wavData)
        body.append("\r\n".data(using: .utf8)!)

        field("model", value: model)
        field("response_format", value: "verbose_json")
        field("language", value: "en")

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return
            }

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let text = json["text"] as? String, !text.isEmpty {

                let result = TranscriptionResult(
                    text: text.trimmingCharacters(in: .whitespaces),
                    startTime: startTime,
                    endTime: startTime + duration,
                    isFinal: true
                )
                resultsContinuation?.yield(result)
            }
        } catch {
            // Skip failed chunks
        }
    }

    private func createWAVData(from pcmData: Data) -> Data {
        let sampleRate = UInt32(self.sampleRate)
        let channels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate = sampleRate * UInt32(channels) * UInt32(bitsPerSample / 8)
        let blockAlign = channels * (bitsPerSample / 8)
        let dataSize = UInt32(pcmData.count)
        let fileSize = 36 + dataSize

        var wav = Data()
        wav.append(contentsOf: "RIFF".utf8)
        wav.append(withUnsafeBytes(of: fileSize.littleEndian) { Data($0) })
        wav.append(contentsOf: "WAVE".utf8)
        wav.append(contentsOf: "fmt ".utf8)
        wav.append(withUnsafeBytes(of: UInt32(16).littleEndian) { Data($0) })
        wav.append(withUnsafeBytes(of: UInt16(1).littleEndian) { Data($0) })
        wav.append(withUnsafeBytes(of: channels.littleEndian) { Data($0) })
        wav.append(withUnsafeBytes(of: sampleRate.littleEndian) { Data($0) })
        wav.append(withUnsafeBytes(of: byteRate.littleEndian) { Data($0) })
        wav.append(withUnsafeBytes(of: blockAlign.littleEndian) { Data($0) })
        wav.append(withUnsafeBytes(of: bitsPerSample.littleEndian) { Data($0) })
        wav.append(contentsOf: "data".utf8)
        wav.append(withUnsafeBytes(of: dataSize.littleEndian) { Data($0) })
        wav.append(pcmData)

        return wav
    }
}
