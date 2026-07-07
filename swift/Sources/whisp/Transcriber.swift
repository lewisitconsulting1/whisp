import FluidAudio
import Foundation

/// Parakeet TDT 0.6B v3 on the Neural Engine via FluidAudio.
/// The ANE does not tolerate concurrent inference on the same compiled graph —
/// callers must serialize (AppController's `busy` flag does this).
final class Transcriber {
    private let asr: AsrManager

    private init(asr: AsrManager) {
        self.asr = asr
    }

    static func load() async throws -> Transcriber {
        print("loading Parakeet TDT 0.6B v3 (first run downloads the CoreML models)...")
        let t0 = Date()
        let models = try await AsrModels.downloadAndLoad(version: .v3)
        let asr = AsrManager(config: .default, models: models)
        let transcriber = Transcriber(asr: asr)
        // 1s of silence triggers ANE graph compilation so the first real
        // dictation doesn't pay the warmup cost
        _ = try? await transcriber.transcribe([Float](repeating: 0, count: Int(AudioRecorder.sampleRate)))
        print(String(format: "model ready in %.1fs", Date().timeIntervalSince(t0)))
        return transcriber
    }

    func transcribe(_ samples: [Float]) async throws -> String {
        var state = try TdtDecoderState()  // fresh state: each dictation is independent
        let result = try await asr.transcribe(samples, decoderState: &state)
        return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func transcribe(fileURL: URL) async throws -> String {
        var state = try TdtDecoderState()
        let result = try await asr.transcribe(fileURL, decoderState: &state)
        return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
