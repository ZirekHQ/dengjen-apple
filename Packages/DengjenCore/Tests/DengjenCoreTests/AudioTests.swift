import XCTest

@testable import DengjenCore

final class AudioTests: XCTestCase {
    func testInt16LittleEndianBecomesFloats() {
        let floats = PCM.floats(fromInt16LE: [0x00, 0x00, 0x00, 0x40, 0x00, 0x80, 0xFF, 0x7F, 0x01])
        XCTAssertEqual(floats.count, 4)
        XCTAssertEqual(floats[0], 0)
        XCTAssertEqual(floats[1], 0.5)
        XCTAssertEqual(floats[2], -1)
        XCTAssertEqual(floats[3], 32767 / 32768)
    }

    func testSilenceLength() {
        XCTAssertEqual(PCM.silence(milliseconds: 100, sampleRate: 22050).count, 2205)
        XCTAssertEqual(PCM.silence(milliseconds: -1, sampleRate: 22050).count, 0)
    }

    func testResampleKeepsSameRateAndHalvesLength() {
        let samples: [Float] = [0, 1, 2, 3]
        XCTAssertEqual(PCM.resample(samples, from: 22050, to: 22050), samples)
        XCTAssertEqual(PCM.resample(samples, from: 2, to: 1), [0, 2])
        XCTAssertEqual(PCM.resample(samples, from: 1, to: 2), [0, 0.5, 1, 1.5, 2, 2.5, 3, 3])
        XCTAssertEqual(PCM.resample([], from: 1, to: 2), [])
    }

    func testQueueReadsInOrderAndCompletesAfterFinish() {
        let queue = SampleQueue()
        let generation = queue.start()
        XCTAssertTrue(queue.append([1, 2, 3], generation: generation))
        var buffer = [Float](repeating: 0, count: 2)
        var result = buffer.withUnsafeMutableBufferPointer { queue.read(into: $0.baseAddress!, capacity: 2) }
        XCTAssertEqual(result.count, 2)
        XCTAssertFalse(result.complete)
        XCTAssertEqual(buffer, [1, 2])
        queue.finish(generation: generation)
        result = buffer.withUnsafeMutableBufferPointer { queue.read(into: $0.baseAddress!, capacity: 2) }
        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(result.complete)
        XCTAssertEqual(buffer[0], 3)
    }

    func testStaleGenerationsCannotWrite() {
        let queue = SampleQueue()
        let first = queue.start()
        let second = queue.start()
        XCTAssertFalse(queue.append([9], generation: first))
        XCTAssertFalse(queue.isCurrent(first))
        XCTAssertTrue(queue.isCurrent(second))
        queue.finish(generation: first)
        XCTAssertTrue(queue.isCurrent(second))
        queue.cancel()
        XCTAssertFalse(queue.isCurrent(second))
        XCTAssertFalse(queue.append([1], generation: second))
        var buffer: [Float] = [0]
        let result = buffer.withUnsafeMutableBufferPointer { queue.read(into: $0.baseAddress!, capacity: 1) }
        XCTAssertEqual(result.count, 0)
        XCTAssertTrue(result.complete)
    }

    func testQueueCompactsAfterLongReads() {
        let queue = SampleQueue()
        let generation = queue.start()
        queue.append([Float](repeating: 1, count: (1 << 16) + 10), generation: generation)
        var buffer = [Float](repeating: 0, count: 1 << 16)
        _ = buffer.withUnsafeMutableBufferPointer { queue.read(into: $0.baseAddress!, capacity: 1 << 16) }
        let rest = buffer.withUnsafeMutableBufferPointer { queue.read(into: $0.baseAddress!, capacity: 1 << 16) }
        XCTAssertEqual(rest.count, 10)
    }
}
