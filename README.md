# dengjen-apple

Dengjen as a system voice on macOS: VoiceOver, Spoken Content and any app that uses the system speech synthesizer can speak Kurmanji with a Dengjen voice.

It is a Swift host app with an `AVSpeechSynthesisProviderAudioUnit` extension (macOS 13.4 or later, Apple silicon) over `Libdengjen.xcframework` from [ZirekHQ/dengjen](https://github.com/ZirekHQ/dengjen). The macOS build ships as a signed, notarized DMG outside the Mac App Store, so it stays GPL-3.0. iOS waits on [#3](https://github.com/ZirekHQ/dengjen-apple/issues/3).

## Use

1. Open Dengjen and install a voice, such as Berfin Renas (Kurmanji).
2. Choose it in System Settings, Accessibility, Spoken Content, System voice, or in VoiceOver Utility, Speech.

## How it works

- **Host app** (`App/`): a voice manager over the `LibdengjenVoices` C API. It downloads and verifies Piper voices from the [Piper voice catalogue](https://huggingface.co/rhasspy/piper-voices) into the shared App Group, writes the installed voices to `speech-voices.json` there and calls `AVSpeechSynthesisProviderVoice.updateSpeechVoices()`.
- **Speech extension** (`Extension/`): offers those voices to the system. For each request it turns the SSML into text, pauses and prosody (rate, pitch, volume), speaks it through the `Libdengjen` C API on a background queue, and streams the audio to the render block. A cancel drops the queued audio and stops the engine at the next sentence.
- **DengjenCore** (`Packages/DengjenCore/`): the pure Swift logic both share: SSML parsing, the prosody-to-engine mapping, PCM conversion, the sample queue and the voice list. `swift test` covers it.

Kurmanji voices use the engine's built-in Kurmanji phonemizer, so the extension needs no eSpeak-ng data.

## Build

Needs macOS on Apple silicon, Xcode 16 or later and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen llvm protobuf
scripts/fetch-libdengjen.sh   # puts Libdengjen.xcframework into Frameworks/, as pinned in libdengjen.lock
xcodegen generate             # writes Dengjen.xcodeproj
open Dengjen.xcodeproj
```

`libdengjen.lock` pins either a dengjen release (downloaded and checked against its SHA-256) or a commit, which `fetch-libdengjen.sh` builds from source with Rust; that needs `rustup`. Set your team in Signing & Capabilities to run the app: the App Group, and with it voice installs, only works in a signed build.

```sh
swift test --package-path Packages/DengjenCore
```

## Releases

Pushing a `vX.Y.Z` tag runs `.github/workflows/release.yaml`: it builds, signs with a Developer ID, notarizes, and attaches `Dengjen.dmg` to a GitHub Release. The secrets it needs are listed at the top of that file.

## Contributing

Every screen must work with VoiceOver. Contributions are accepted under the [Dengjen CLA](https://github.com/ZirekHQ/dengjen/blob/main/CLA.md).

## Licence

GPL-3.0-or-later, the same as the engine. See [LICENSE](LICENSE).
