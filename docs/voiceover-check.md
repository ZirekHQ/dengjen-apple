# VoiceOver check

The Apple step is done when VoiceOver on a Mac reads Kurmanji with a Dengjen voice. Run this on an Apple silicon Mac with macOS 13.4 or later, using a signed build: the notarized DMG from the Release workflow, or a build from Xcode with your team set in Signing & Capabilities. An unsigned build has no App Group and cannot install voices.

Record the macOS version, the build, and the result of each step in the issue.

## Install

1. Open the DMG and drag Dengjen to Applications, then open it. Gatekeeper should not warn about a notarized build.
2. Turn VoiceOver on (Command-F5) and leave it on for the whole check.
3. In the Dengjen window, check that VoiceOver reads the heading, the instructions, the "Show all languages" toggle, Refresh, and each voice row with its name, language and size.
4. Install **Berfin Renas (medium)**. VoiceOver should read the progress as a percentage, and the row should then offer Remove.

## Choose the voice

5. System Settings, Accessibility, Spoken Content, System voice: "Dengjen Berfin Renas" should be listed (under Kurdish or under the voice list's "Manage Voices"). Choose it and press Play sample.
6. VoiceOver Utility (Option-Command-F8), Speech, Voices: set the default voice to Dengjen Berfin Renas.

## Listen

7. In TextEdit, type `Silav, navê min Berfin e. Ez ji Amedê me.` and read it with VoiceOver (VO-A). It should sound like Kurmanji with no gaps between sentences.
8. Read a long paragraph and press Control halfway through. Speech should stop within about one sentence.
9. Change the speaking rate in VoiceOver Utility to fast and to slow, and read again. The rate should follow.
10. Read `12:30`, `28.10.2026` and `3,5 kg`. They should come out as Kurmanji words, not digits.
11. Move through Finder and the menu bar with VO-arrow keys for a minute and listen for stutters, silence or a crash.

## If something fails

- No voice in Spoken Content: run `pluginkit -m -p com.apple.AudioUnit-Speech` and check that `io.github.zirekhq.dengjen.speech` is listed. Log out and in once after the first install.
- Silence or a crash: run `log stream --predicate 'subsystem == "io.github.zirekhq.dengjen"'` while reproducing it, and attach the output.
