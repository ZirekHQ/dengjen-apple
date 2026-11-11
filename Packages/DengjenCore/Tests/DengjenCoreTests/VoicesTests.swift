import XCTest

@testable import DengjenCore

final class VoicesTests: XCTestCase {
    func testCatalogueJSONDecodes() throws {
        let json = """
            [{"key": "ku_TR-berfin_renas-medium", "name": "berfin_renas",
              "language": {"code": "ku_TR", "family": "ku", "name_english": "Kurdish",
                           "name_native": "Kurdî", "country_english": "Turkey"},
              "quality": "medium", "num_speakers": 1,
              "files": [{"path": "ku/a.onnx", "size": 60000000}, {"path": "ku/a.onnx.json", "size": 5000}]}]
            """
        let voices = try CatalogueVoice.decodeList(Data(json.utf8))
        XCTAssertEqual(voices.count, 1)
        XCTAssertEqual(voices[0].language.nameNative, "Kurdî")
        XCTAssertEqual(voices[0].size, 60_005_000)
        XCTAssertEqual(voices[0].displayName, "Berfin Renas (medium)")
    }

    func testCatalogueLanguageFieldsAreOptional() throws {
        let json = #"[{"key": "k", "name": "n", "language": {"code": "ku"}, "quality": "", "files": []}]"#
        let voice = try XCTUnwrap(CatalogueVoice.decodeList(Data(json.utf8)).first)
        XCTAssertEqual(voice.language.family, "")
        XCTAssertEqual(voice.displayName, "N")
    }

    func testInstalledVoiceBecomesASharedVoice() throws {
        let json = #"[{"key": "ku_TR-berfin_renas-medium", "model_type": "piper", "name": "berfin_renas", "language": "ku_TR", "description": ""}]"#
        let installed = try XCTUnwrap(InstalledVoice.decodeList(Data(json.utf8)).first)
        XCTAssertEqual(
            SharedVoice(installed: installed, voicesDirectory: "voices"),
            SharedVoice(
                identifier: "io.github.zirekhq.dengjen.ku_TR-berfin_renas-medium",
                key: "ku_TR-berfin_renas-medium",
                name: "Dengjen Berfin Renas",
                language: "ku-TR",
                directory: "voices/piper/ku_TR-berfin_renas-medium"))
    }

    func testVoiceListRoundTripsAndFindsTheConfig() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent(VoiceList.fileName)
        XCTAssertEqual(VoiceList.load(from: url), [])
        let voice = SharedVoice(identifier: "i", key: "k", name: "n", language: "ku-TR", directory: "d")
        try VoiceList.save([voice], to: url)
        XCTAssertEqual(VoiceList.load(from: url), [voice])

        XCTAssertNil(VoiceList.configFile(in: directory))
        for name in ["voice.json", "k.onnx", "k.onnx.json"] {
            try Data().write(to: directory.appendingPathComponent(name))
        }
        XCTAssertEqual(VoiceList.configFile(in: directory)?.lastPathComponent, "k.onnx.json")
    }
}
