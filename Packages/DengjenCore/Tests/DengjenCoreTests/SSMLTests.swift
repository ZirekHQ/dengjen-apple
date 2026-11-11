import XCTest

@testable import DengjenCore

final class SSMLTests: XCTestCase {
    func testPlainSpeakElementIsOneNeutralSegment() {
        XCTAssertEqual(
            SSML.segments(from: "<speak>Silav  li\n te</speak>"),
            [.text("Silav li te", .neutral)])
    }

    func testTextThatIsNotXMLIsSpokenWithoutTags() {
        XCTAssertEqual(
            SSML.segments(from: "Silav <b>heval & </b>"),
            [.text("Silav heval &", .neutral)])
    }

    func testEmptyInputHasNoSegments() {
        XCTAssertEqual(SSML.segments(from: ""), [])
        XCTAssertEqual(SSML.segments(from: "<speak> </speak>"), [])
    }

    func testProsodyAppliesToItsTextAndNests() {
        let segments = SSML.segments(
            from: """
                <speak>yek <prosody rate="200%">du <prosody pitch="+10%">sê</prosody></prosody> çar</speak>
                """)
        XCTAssertEqual(
            segments,
            [
                .text("yek", .neutral),
                .text("du", Prosody(rate: 2)),
                .text("sê", Prosody(rate: 2, pitch: 1.1)),
                .text("çar", .neutral),
            ])
    }

    func testBreaksBecomePausesAndMerge() {
        let segments = SSML.segments(
            from: #"<speak>yek<break time="300ms"/><break time="0.2s"/>du<break strength="strong"/></speak>"#)
        XCTAssertEqual(
            segments,
            [.text("yek", .neutral), .pause(milliseconds: 500), .text("du", .neutral), .pause(milliseconds: 750)])
    }

    func testSubSpeaksItsAlias() {
        XCTAssertEqual(
            SSML.segments(from: #"<speak>Ez <sub alias="doktor">Dr.</sub> im</speak>"#),
            [.text("Ez doktor im", .neutral)])
    }

    func testNamespacedSpeakElementIsRead() {
        let ssml = #"<speak xmlns="http://www.w3.org/2001/10/synthesis" version="1.0" xml:lang="ku-TR"><s>Silav</s><s>heval</s></speak>"#
        XCTAssertEqual(SSML.segments(from: ssml), [.text("Silav heval", .neutral)])
    }

    func testEntitiesAreDecoded() {
        XCTAssertEqual(SSML.segments(from: "<speak>a &amp; b &lt; c</speak>"), [.text("a & b < c", .neutral)])
    }

    func testPauseLengths() {
        XCTAssertEqual(SSML.pauseMilliseconds(time: "1.5s", strength: nil), 1500)
        XCTAssertEqual(SSML.pauseMilliseconds(time: "99999s", strength: nil), SSML.maxPauseMilliseconds)
        XCTAssertEqual(SSML.pauseMilliseconds(time: "-5ms", strength: nil), 0)
        XCTAssertEqual(SSML.pauseMilliseconds(time: "soon", strength: "none"), 0)
        XCTAssertEqual(SSML.pauseMilliseconds(time: nil, strength: nil), 500)
    }
}
