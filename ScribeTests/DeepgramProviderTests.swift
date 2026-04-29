import Testing
@testable import ScribeCore
import Foundation

@Suite("DeepgramProvider resilience")
struct DeepgramProviderTests {

    @Test("sendAudio is a no-op when not connected (does not throw)")
    func sendAudioSilentDrop() async throws {
        let provider = DeepgramProvider(apiKey: "test-key")
        #expect(provider.isConnected == false)

        // Regression: previously threw .notConnected which spammed logs from the realtime
        // audio loop. The fix is to drop silently during reconnect / before-connect windows.
        try await provider.sendAudio(Data([0x00, 0x01, 0x02]))
    }

    @Test("disconnect is safe when never connected")
    func disconnectIdempotent() async {
        let provider = DeepgramProvider(apiKey: "test-key")
        await provider.disconnect()
        await provider.disconnect()
        #expect(provider.isConnected == false)
    }

    @Test("Custom resilience tunables are stored")
    func tunablesStored() {
        let provider = DeepgramProvider(
            apiKey: "k",
            keepAliveInterval: 2.5,
            initialReconnectDelay: 0.5,
            maxReconnectDelay: 4.0
        )
        #expect(provider.keepAliveInterval == 2.5)
        #expect(provider.initialReconnectDelay == 0.5)
        #expect(provider.maxReconnectDelay == 4.0)
    }

    @Test("Default tunables match expected resilience profile")
    func defaultTunables() {
        let provider = DeepgramProvider(apiKey: "k")
        // Deepgram closes idle WS at ~10s without traffic — 5s keepalive gives 2x headroom.
        #expect(provider.keepAliveInterval == 5.0)
        #expect(provider.initialReconnectDelay == 1.0)
        #expect(provider.maxReconnectDelay == 10.0)
    }
}
