import Foundation

/// Converts the engine's audio into what an audio unit renders.
public enum PCM {
    /// Mono 16-bit little-endian samples, as libdengjen's speech events carry them, as floats in
    /// `-1...1`. A trailing odd byte is ignored.
    public static func floats(fromInt16LE bytes: UnsafeRawBufferPointer) -> [Float] {
        let count = bytes.count / 2
        var out = [Float](repeating: 0, count: count)
        for index in 0..<count {
            let low = UInt16(bytes[index * 2])
            let high = UInt16(bytes[index * 2 + 1])
            let sample = Int16(bitPattern: low | (high << 8))
            out[index] = Float(sample) / 32768
        }
        return out
    }

    public static func floats(fromInt16LE bytes: [UInt8]) -> [Float] {
        bytes.withUnsafeBytes { floats(fromInt16LE: $0) }
    }

    /// Silence of the given length.
    public static func silence(milliseconds: Int, sampleRate: Double) -> [Float] {
        let frames = Int((Double(max(milliseconds, 0)) * sampleRate / 1000).rounded())
        return [Float](repeating: 0, count: frames)
    }

    /// Linear resampling from `sourceRate` to `targetRate`. Speech voices and the output bus
    /// almost always share a rate, so this is only a fallback and favours simplicity.
    public static func resample(_ samples: [Float], from sourceRate: Double, to targetRate: Double)
        -> [Float]
    {
        guard sourceRate > 0, targetRate > 0, sourceRate != targetRate, !samples.isEmpty else {
            return samples
        }
        let ratio = sourceRate / targetRate
        let count = Int((Double(samples.count) / ratio).rounded(.down))
        guard count > 0 else { return [] }
        var out = [Float](repeating: 0, count: count)
        let last = samples.count - 1
        for index in 0..<count {
            let position = Double(index) * ratio
            let lower = min(Int(position), last)
            let upper = min(lower + 1, last)
            let weight = Float(position - Double(lower))
            out[index] = samples[lower] * (1 - weight) + samples[upper] * weight
        }
        return out
    }
}

/// The audio of the current speech request, written by the synthesis thread and read by the
/// render block.
///
/// Every request gets a new generation from `start()`. Writes that carry an older generation are
/// dropped, so a request that was cancelled or replaced can never leak audio into the next one.
public final class SampleQueue: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [Float] = []
    private var readIndex = 0
    private var finished = true
    private var generation: UInt64 = 0

    public init() {}

    /// Clears the queue for a new request and returns that request's generation.
    @discardableResult
    public func start() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        generation &+= 1
        samples.removeAll(keepingCapacity: true)
        readIndex = 0
        finished = false
        return generation
    }

    /// Drops any queued audio and ends the current request.
    public func cancel() {
        lock.lock()
        defer { lock.unlock() }
        generation &+= 1
        samples.removeAll(keepingCapacity: true)
        readIndex = 0
        finished = true
    }

    /// Whether `generation` is still the request being spoken.
    public func isCurrent(_ generation: UInt64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return generation == self.generation && !finished
    }

    /// Queues audio for `generation`; returns false, and queues nothing, once that request is
    /// over.
    @discardableResult
    public func append(_ newSamples: [Float], generation: UInt64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard generation == self.generation, !finished else { return false }
        samples.append(contentsOf: newSamples)
        return true
    }

    /// Marks the end of `generation`'s audio.
    public func finish(generation: UInt64) {
        lock.lock()
        defer { lock.unlock() }
        if generation == self.generation {
            finished = true
        }
    }

    /// Copies up to `capacity` samples into `destination`. `complete` is true once the request is
    /// finished and every sample has been read.
    public func read(into destination: UnsafeMutablePointer<Float>, capacity: Int)
        -> (count: Int, complete: Bool)
    {
        lock.lock()
        defer { lock.unlock() }
        let count = min(max(capacity, 0), samples.count - readIndex)
        if count > 0 {
            samples.withUnsafeBufferPointer { source in
                guard let base = source.baseAddress else { return }
                destination.update(from: base + readIndex, count: count)
            }
            readIndex += count
        }
        if readIndex >= samples.count {
            samples.removeAll(keepingCapacity: true)
            readIndex = 0
        } else if readIndex >= 1 << 16 {
            samples.removeFirst(readIndex)
            readIndex = 0
        }
        return (count, finished && samples.isEmpty)
    }
}
