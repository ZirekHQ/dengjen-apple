import AVFoundation
import DengjenCore
import os

private let log = Logger(subsystem: "io.github.zirekhq.dengjen", category: "speech")

/// Creates the audio unit when the system loads the extension.
public final class AudioUnitFactory: NSObject, AUAudioUnitFactory {
    private var audioUnit: AUAudioUnit?

    public func beginRequest(with context: NSExtensionContext) {}

    @objc public func createAudioUnit(with componentDescription: AudioComponentDescription) throws
        -> AUAudioUnit
    {
        let unit = try DengjenSynthesisAudioUnit(
            componentDescription: componentDescription, options: [])
        audioUnit = unit
        return unit
    }
}

/// The speech synthesis provider: offers the installed Dengjen voices to the system and renders
/// each request's SSML through the engine.
///
/// The engine runs on `synthesisQueue` and streams audio into `samples`; the render block only
/// reads from `samples`, so it never waits on the engine.
public final class DengjenSynthesisAudioUnit: AVSpeechSynthesisProviderAudioUnit {
    /// Piper's medium and high voices speak at 22050 Hz; other voices are resampled to it.
    static let outputSampleRate = 22_050.0

    private let outputBus: AUAudioUnitBus
    private var busArray: AUAudioUnitBusArray!
    private let samples = SampleQueue()
    private let synthesisQueue = DispatchQueue(label: "io.github.zirekhq.dengjen.synthesis")
    /// The voice last loaded; only touched on `synthesisQueue`.
    private var loadedVoice: (identifier: String, voice: EngineVoice)?

    public override init(
        componentDescription: AudioComponentDescription,
        options: AudioComponentInstantiationOptions = []
    ) throws {
        guard
            let format = AVAudioFormat(
                standardFormatWithSampleRate: Self.outputSampleRate, channels: 1)
        else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(kAudioUnitErr_FormatNotSupported))
        }
        outputBus = try AUAudioUnitBus(format: format)
        try super.init(componentDescription: componentDescription, options: options)
        busArray = AUAudioUnitBusArray(audioUnit: self, busType: .output, busses: [outputBus])
    }

    public override var outputBusses: AUAudioUnitBusArray { busArray }

    public override var speechVoices: [AVSpeechSynthesisProviderVoice] {
        get {
            sharedVoices().map {
                AVSpeechSynthesisProviderVoice(
                    name: $0.name, identifier: $0.identifier,
                    primaryLanguages: [$0.language], supportedLanguages: [$0.language])
            }
        }
        set {}
    }

    public override func synthesizeSpeechRequest(_ speechRequest: AVSpeechSynthesisProviderRequest) {
        let generation = samples.start()
        let segments = SSML.segments(from: speechRequest.ssmlRepresentation)
        let identifier = speechRequest.voice.identifier
        let outputRate = outputBus.format.sampleRate
        synthesisQueue.async { [weak self] in
            guard let self else { return }
            self.render(segments, voiceIdentifier: identifier, outputRate: outputRate, generation: generation)
            self.samples.finish(generation: generation)
        }
    }

    public override func cancelSpeechRequest() {
        samples.cancel()
    }

    public override var internalRenderBlock: AUInternalRenderBlock {
        let samples = self.samples
        return { actionFlags, _, frameCount, _, outputData, _, _ in
            let buffers = UnsafeMutableAudioBufferListPointer(outputData)
            guard let first = buffers.first, let data = first.mData else {
                return kAudioUnitErr_InvalidParameter
            }
            let capacity = min(Int(frameCount), Int(first.mDataByteSize) / MemoryLayout<Float>.size)
            let destination = data.assumingMemoryBound(to: Float.self)
            let (count, complete) = samples.read(into: destination, capacity: capacity)
            // Frames not yet synthesized stay silent, in case a host ignores mDataByteSize.
            if count < capacity {
                (destination + count).initialize(repeating: 0, count: capacity - count)
            }
            let byteSize = UInt32(count * MemoryLayout<Float>.size)
            for index in buffers.indices {
                if index > 0, let channel = buffers[index].mData {
                    channel.copyMemory(from: data, byteCount: Int(byteSize))
                }
                buffers[index].mDataByteSize = byteSize
            }
            if complete {
                actionFlags.pointee = .offlineUnitRenderAction_Complete
            }
            return noErr
        }
    }

    // MARK: - Synthesis

    private func render(
        _ segments: [SpeechSegment], voiceIdentifier: String, outputRate: Double,
        generation: UInt64
    ) {
        guard let voice = engineVoice(for: voiceIdentifier) else { return }
        for segment in segments {
            guard samples.isCurrent(generation) else { return }
            switch segment {
            case .pause(let milliseconds):
                samples.append(PCM.silence(milliseconds: milliseconds, sampleRate: outputRate), generation: generation)
            case .text(let text, let prosody):
                do {
                    try voice.speak(text, settings: prosody.engineSettings) { [samples] bytes in
                        let chunk = PCM.resample(
                            PCM.floats(fromInt16LE: bytes), from: voice.sampleRate, to: outputRate)
                        return samples.append(chunk, generation: generation)
                    }
                } catch {
                    log.error("Speaking failed: \(error.localizedDescription, privacy: .public)")
                    return
                }
            }
        }
    }

    /// The engine voice for `identifier`, loading it if another voice (or none) is loaded.
    private func engineVoice(for identifier: String) -> EngineVoice? {
        if let loadedVoice, loadedVoice.identifier == identifier {
            return loadedVoice.voice
        }
        loadedVoice = nil
        guard let container = AppGroup.containerURL(),
            let shared = sharedVoices().first(where: { $0.identifier == identifier }),
            let config = VoiceList.configFile(
                in: container.appendingPathComponent(shared.directory, isDirectory: true))
        else {
            log.error("Voice \(identifier, privacy: .public) is not installed")
            return nil
        }
        do {
            let voice = try EngineVoice(configFile: config)
            loadedVoice = (identifier, voice)
            return voice
        } catch {
            log.error("Loading \(identifier, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func sharedVoices() -> [SharedVoice] {
        guard let container = AppGroup.containerURL() else { return [] }
        return VoiceList.load(from: AppGroup.voiceListURL(in: container))
    }
}
