# Set up signed releases

`.github/workflows/release.yaml` signs the app with a Developer ID, notarizes it and publishes `Dengjen.dmg` when a `vX.Y.Z` tag is pushed. It needs an Apple Developer Program membership and six repository secrets. You do these steps once.

## 1. Join the Apple Developer Program

Enroll at <https://developer.apple.com/programs/enroll/> (USD 99 a year; an organization needs a D-U-N-S number, an individual does not). Note the 10-character **Team ID** shown under Membership details.

## 2. Create the Developer ID Application certificate

1. On a Mac, open Keychain Access, then Certificate Assistant, then "Request a Certificate From a Certificate Authority". Save the request to disk.
2. At <https://developer.apple.com/account/resources/certificates/add>, choose **Developer ID Application** (the G2 sub-CA) and upload the request.
3. Download the certificate and double-click it, so it lands in your login keychain next to its private key.
4. In Keychain Access, select the certificate and its key, then File, Export Items, and save a `.p12` with a strong password.

## 3. Create an App Store Connect API key for notarization

At <https://appstoreconnect.apple.com/access/integrations/api>, create a team key with the **Developer** role. Download the `.p8` (you can only download it once) and note its **Key ID** and the **Issuer ID** at the top of the page.

## 4. Register the App Group

At <https://developer.apple.com/account/resources/identifiers/list/applicationGroup>, register `<TeamID>.io.github.zirekhq.dengjen`. On macOS a Developer ID app may use a team-prefixed group without a provisioning profile. Registering the group anyway keeps the identifier reserved.

## 5. Add the repository secrets

In this repository, open Settings, then Secrets and variables, then Actions, and add:

| Secret | Value |
|---|---|
| `APPLE_TEAM_ID` | the Team ID from step 1 |
| `APPLE_DEVELOPER_ID_P12` | `base64 -i developer-id.p12` |
| `APPLE_DEVELOPER_ID_P12_PASSWORD` | the `.p12` password |
| `APPLE_NOTARY_KEY_P8` | `base64 -i AuthKey_XXXXXXXXXX.p8` |
| `APPLE_NOTARY_KEY_ID` | the Key ID from step 3 |
| `APPLE_NOTARY_ISSUER_ID` | the Issuer ID from step 3 |

Delete the local `.p12` and `.p8` copies once they are stored in a password manager.

## 6. Cut a release

1. Make `libdengjen.lock` point at a dengjen release (`source=release`, `version`, and the `sha256` from that release's `SHA256SUMS-apple.txt`).
2. Run the Release workflow by hand first (Actions, Release, Run workflow). It builds, signs and notarizes, and uploads the DMG as a workflow artifact without publishing anything.
3. Run the [VoiceOver check](voiceover-check.md) on that DMG.
4. Tag and push: `git tag -a v0.1.0 -m "Dengjen for macOS 0.1.0" && git push origin v0.1.0`. The workflow then attaches the DMG and `SHA256SUMS.txt` to a GitHub Release.
