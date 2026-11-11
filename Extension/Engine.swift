import DengjenCore
import Foundation
import Libdengjen

/// A failed `libdengjen` call.
struct EngineError: LocalizedError {
    let code: Int32
    let message: String

    var errorDescription: String? { message }
}

/// Collects one `libdengjenSpeak` call's audio and error for its C callback.
private final class SpeakContext {
    let onAudio: (UnsafeRawBufferPointer) -> Bool
    var errorMessage: String?

    init(onAudio: @escaping (UnsafeRawBufferPointer) -> Bool) {
        self.onAudio = onAudio
    }
}

/// One loaded Dengjen voice over the `libdengjen` C API. Not thread-safe: the audio unit uses it
/// from its synthesis queue only.
final class EngineVoice {
    let sampleRate: Double
    private let handle: OpaquePointer

    init(configFile: URL) throws {
        var error = ExternError()
        let loaded: OpaquePointer? = configFile.path.withCString {
            libdengjenLoadVoiceFromConfigPath($0, &error)
        }
        try Self.check(&error)
        guard let loaded else {
            throw EngineError(code: NULL_POINTER, message: "Could not load \(configFile.path)")
        }
        var info = AudioInfo()
        libdengjenGetAudioInfo(loaded, &info, &error)
        do {
            try Self.check(&error)
        } catch {
            libdengjenUnloadDengjenVoice(loaded)
            throw error
        }
        handle = loaded
        sampleRate = Double(info.sample_rate)
    }

    deinit {
        libdengjenUnloadDengjenVoice(handle)
    }

    /// Speaks `text`, handing each chunk of 16-bit mono PCM to `onAudio` as it is ready. Returns
    /// early once `onAudio` returns false; the engine stops between sentences.
    func speak(
        _ text: String, settings: EngineSettings,
        onAudio: @escaping (UnsafeRawBufferPointer) -> Bool
    ) throws {
        let context = Unmanaged.passRetained(SpeakContext(onAudio: onAudio))
        defer { context.release() }

        var params = SynthesisParams()
        params.struct_size = UInt32(MemoryLayout<SynthesisParams>.stride)
        params.mode = SYNTH_MODE_LAZY
        params.rate = settings.rate
        params.volume = settings.volume
        params.pitch = settings.pitch
        params.appended_silence_ms = 0
        params.nonblocking = 0
        params.user_data = context.toOpaque()
        params.callback = { event, userData in
            var keepGoing = true
            if let userData {
                let context = Unmanaged<SpeakContext>.fromOpaque(userData).takeUnretainedValue()
                switch event.event_type {
                case SYNTH_EVENT_SPEECH:
                    if let data = event.data, event.len > 0 {
                        keepGoing = context.onAudio(
                            UnsafeRawBufferPointer(start: data, count: Int(event.len)))
                    }
                case SYNTH_EVENT_ERROR:
                    if let message = event.error_ptr?.pointee.message {
                        context.errorMessage = String(cString: message)
                    } else {
                        context.errorMessage = "Speech synthesis failed"
                    }
                default:
                    break
                }
            }
            // The callback owns the event, including its error message.
            libdengjenFreeSynthesisEvent(event)
            // 0 asks for the next chunk; anything else ends the stream.
            return keepGoing ? 0 : 1
        }

        var error = ExternError()
        text.withCString { libdengjenSpeak(handle, $0, &params, &error) }
        try Self.check(&error)
        if let message = context.takeUnretainedValue().errorMessage {
            throw EngineError(code: OPERATION_ERROR, message: message)
        }
    }

    private static func check(_ error: inout ExternError) throws {
        guard error.code != 0 else { return }
        let code = error.code
        let message = error.message.map { String(cString: $0) } ?? "Engine error \(code)"
        if let pointer = error.message {
            libdengjenFreeString(pointer)
        }
        error = ExternError()
        throw EngineError(code: code, message: message)
    }
}
