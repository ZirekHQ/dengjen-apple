import Foundation

/// How one stretch of text should sound, as multipliers of the voice's defaults.
public struct Prosody: Equatable, Sendable {
    /// Speaking speed; 1 is the voice's normal speed.
    public var rate: Double
    /// Pitch; 1 is the voice's normal pitch.
    public var pitch: Double
    /// Loudness from 0 (silent) to 1 (the voice's full volume).
    public var volume: Double

    public static let neutral = Prosody()

    public init(rate: Double = 1, pitch: Double = 1, volume: Double = 1) {
        self.rate = rate
        self.pitch = pitch
        self.volume = volume
    }

    /// The engine's `0...100` settings for this prosody.
    public var engineSettings: EngineSettings {
        EngineSettings(
            rate: EngineSettings.percent((rate - EngineSettings.speedRange.lowerBound)
                / span(EngineSettings.speedRange)),
            pitch: EngineSettings.percent((pitch - EngineSettings.pitchRange.lowerBound)
                / span(EngineSettings.pitchRange)),
            volume: EngineSettings.percent(volume)
        )
    }

    private func span(_ range: ClosedRange<Double>) -> Double {
        range.upperBound - range.lowerBound
    }
}

/// The `rate`, `pitch` and `volume` fields of libdengjen's `SynthesisParams`.
public struct EngineSettings: Equatable, Sendable {
    /// The engine's speed setting spans 0.5x at 0 to 5.5x at 100, so normal speed is 10.
    public static let speedRange: ClosedRange<Double> = 0.5...5.5
    /// The engine's pitch setting spans 0.5x at 0 to 1.5x at 100, so normal pitch is 50.
    public static let pitchRange: ClosedRange<Double> = 0.5...1.5

    public var rate: UInt8
    public var pitch: UInt8
    public var volume: UInt8

    public init(rate: UInt8, pitch: UInt8, volume: UInt8) {
        self.rate = rate
        self.pitch = pitch
        self.volume = volume
    }

    static func percent(_ fraction: Double) -> UInt8 {
        guard fraction.isFinite else { return 0 }
        return UInt8((fraction * 100).rounded().clamped(to: 0...100))
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

/// Reads SSML `<prosody>` attribute values.
enum ProsodyValue {
    /// Applies an SSML `rate` value to the inherited speed.
    static func rate(_ value: String, inherited: Double) -> Double {
        switch value.trimmed.lowercased() {
        case "x-slow": return 0.5
        case "slow": return 0.75
        case "medium", "default": return 1
        case "fast": return 1.5
        case "x-fast": return 2
        default: return scaled(value, inherited: inherited)
        }
    }

    /// Applies an SSML `pitch` value to the inherited pitch. Absolute hertz values are ignored,
    /// because the voice's base frequency is unknown here.
    static func pitch(_ value: String, inherited: Double) -> Double {
        let text = value.trimmed.lowercased()
        switch text {
        case "x-low": return 0.7
        case "low": return 0.85
        case "medium", "default": return 1
        case "high": return 1.15
        case "x-high": return 1.3
        default: break
        }
        if text.hasSuffix("st"), let semitones = Double(text.dropLast(2)) {
            return inherited * pow(2, semitones / 12)
        }
        if text.hasSuffix("hz") {
            return inherited
        }
        return scaled(text, inherited: inherited)
    }

    /// Applies an SSML `volume` value to the inherited volume, clamped to `0...1`.
    static func volume(_ value: String, inherited: Double) -> Double {
        let text = value.trimmed.lowercased()
        let result: Double
        switch text {
        case "silent": result = 0
        case "x-soft": result = 0.4
        case "soft": result = 0.7
        case "medium", "loud", "x-loud", "default": result = 1
        default:
            if text.hasSuffix("db"), let decibels = Double(text.dropLast(2)) {
                result = inherited * pow(10, decibels / 20)
            } else if text.hasSuffix("%") {
                result = scaled(text, inherited: inherited)
            } else if let number = Double(text) {
                // A bare number is SSML's 0-100 scale, relative when signed.
                let isRelative = text.hasPrefix("+") || text.hasPrefix("-")
                result = isRelative ? inherited + number / 100 : number / 100
            } else {
                result = inherited
            }
        }
        return result.clamped(to: 0...1)
    }

    /// `+10%` and `-10%` change the inherited value; `150%` and a bare `1.5` replace it with a
    /// multiple of the default. Anything unreadable keeps the inherited value.
    private static func scaled(_ value: String, inherited: Double) -> Double {
        let text = value.trimmed
        let isRelative = text.hasPrefix("+") || text.hasPrefix("-")
        if text.hasSuffix("%"), let percent = Double(text.dropLast()) {
            let result = isRelative ? inherited * (1 + percent / 100) : percent / 100
            return max(result, 0)
        }
        if let number = Double(text), number >= 0, !isRelative {
            return number
        }
        return inherited
    }
}

extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
