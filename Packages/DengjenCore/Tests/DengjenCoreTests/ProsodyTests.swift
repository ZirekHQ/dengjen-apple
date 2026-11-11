import XCTest

@testable import DengjenCore

final class ProsodyTests: XCTestCase {
    func testNeutralProsodyIsTheEngineDefaults() {
        XCTAssertEqual(Prosody.neutral.engineSettings, EngineSettings(rate: 10, pitch: 50, volume: 100))
    }

    func testEngineSettingsClampToTheEngineRange() {
        XCTAssertEqual(Prosody(rate: 0.1, pitch: 0.1, volume: -1).engineSettings, EngineSettings(rate: 0, pitch: 0, volume: 0))
        XCTAssertEqual(Prosody(rate: 9, pitch: 3, volume: 2).engineSettings, EngineSettings(rate: 100, pitch: 100, volume: 100))
        XCTAssertEqual(Prosody(rate: 3).engineSettings.rate, 50)
        XCTAssertEqual(Prosody(rate: .nan).engineSettings.rate, 0)
    }

    func testRateValues() {
        XCTAssertEqual(ProsodyValue.rate("x-fast", inherited: 1), 2)
        XCTAssertEqual(ProsodyValue.rate("150%", inherited: 2), 1.5)
        XCTAssertEqual(ProsodyValue.rate("+50%", inherited: 2), 3)
        XCTAssertEqual(ProsodyValue.rate("-50%", inherited: 2), 1)
        XCTAssertEqual(ProsodyValue.rate("0.8", inherited: 2), 0.8)
        XCTAssertEqual(ProsodyValue.rate("quick", inherited: 2), 2)
        XCTAssertEqual(ProsodyValue.rate("-200%", inherited: 1), 0)
    }

    func testPitchValues() {
        XCTAssertEqual(ProsodyValue.pitch("high", inherited: 1), 1.15)
        XCTAssertEqual(ProsodyValue.pitch("+12st", inherited: 1), 2, accuracy: 1e-9)
        XCTAssertEqual(ProsodyValue.pitch("-12st", inherited: 1), 0.5, accuracy: 1e-9)
        XCTAssertEqual(ProsodyValue.pitch("200Hz", inherited: 1.1), 1.1)
        XCTAssertEqual(ProsodyValue.pitch("+10%", inherited: 1), 1.1, accuracy: 1e-9)
    }

    func testVolumeValues() {
        XCTAssertEqual(ProsodyValue.volume("silent", inherited: 1), 0)
        XCTAssertEqual(ProsodyValue.volume("50", inherited: 1), 0.5)
        XCTAssertEqual(ProsodyValue.volume("-20", inherited: 0.5), 0.3, accuracy: 1e-9)
        XCTAssertEqual(ProsodyValue.volume("-6dB", inherited: 1), 0.501, accuracy: 0.001)
        XCTAssertEqual(ProsodyValue.volume("+6dB", inherited: 1), 1)
        XCTAssertEqual(ProsodyValue.volume("50%", inherited: 1), 0.5)
        XCTAssertEqual(ProsodyValue.volume("loudish", inherited: 0.4), 0.4)
    }
}
