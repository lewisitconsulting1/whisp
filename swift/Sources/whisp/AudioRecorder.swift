import AVFoundation

/// Records microphone audio and returns 16 kHz mono Float32 samples.
final class AudioRecorder {
    static let sampleRate: Double = 16000

    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private var samples: [Float] = []
    private var lastVoiceAt: Date?
    private var heardVoice = false
    private let lock = NSLock()
    /// RMS above this counts as speech; quiet-room noise floor is ~0.002–0.01
    private let voiceThreshold: Float = 0.015
    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false
    )!

    func start() throws {
        samples.removeAll(keepingCapacity: true)
        lastVoiceAt = nil
        heardVoice = false
        let input = engine.inputNode
        let hwFormat = input.outputFormat(forBus: 0)
        let converter = AVAudioConverter(from: hwFormat, to: targetFormat)!
        self.converter = converter

        input.installTap(onBus: 0, bufferSize: 4096, format: hwFormat) { [weak self] buffer, _ in
            guard let self else { return }
            let ratio = AudioRecorder.sampleRate / hwFormat.sampleRate
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
            guard let out = AVAudioPCMBuffer(pcmFormat: self.targetFormat, frameCapacity: capacity) else { return }
            var consumed = false
            var err: NSError?
            converter.convert(to: out, error: &err) { _, status in
                if consumed {
                    status.pointee = .noDataNow
                    return nil
                }
                consumed = true
                status.pointee = .haveData
                return buffer
            }
            guard err == nil, let ch = out.floatChannelData else { return }
            let chunk = Array(UnsafeBufferPointer(start: ch[0], count: Int(out.frameLength)))
            var energy: Float = 0
            for v in chunk { energy += v * v }
            let rms = chunk.isEmpty ? 0 : (energy / Float(chunk.count)).squareRoot()
            self.lock.lock()
            self.samples.append(contentsOf: chunk)
            if rms > self.voiceThreshold {
                self.lastVoiceAt = Date()
                self.heardVoice = true
            }
            self.lock.unlock()
        }
        engine.prepare()
        try engine.start()
    }

    func stop() -> [Float] {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        converter = nil
        lock.lock()
        defer { lock.unlock() }
        return samples
    }

    /// For hands-free auto-stop: has speech been heard yet, and how long has
    /// it been silent since the last speech?
    func voiceStatus() -> (heardVoice: Bool, silenceSeconds: Double, duration: Double) {
        lock.lock()
        defer { lock.unlock() }
        let duration = Double(samples.count) / Self.sampleRate
        guard heardVoice, let last = lastVoiceAt else { return (false, 0, duration) }
        return (true, Date().timeIntervalSince(last), duration)
    }
}
