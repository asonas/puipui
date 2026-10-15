# Releases

puipui distributes a Developer ID signed, notarized DMG through GitHub Releases. Sparkle reads `appcast.xml` from the latest stable release and verifies each update against the public key embedded in the app.

## Signing prerequisites

Install `gh` and `ax` for collecting corresponding source. Commit the release changes before building so the source archive matches the app. The maintainer's keychain must contain:

- `Developer ID Application: Yuya Fujiwara (QYP65434UW)` and its private key.
- The `YoruMimizukuNotary` notarytool profile. This existing profile authenticates the same Apple Developer team and can notarize puipui.
- The Sparkle Ed25519 key under account `as.ason.puipui`. Its public key must match `SUPublicEDKey` in `Resources/Info.plist`.

Keep the Sparkle private key available across releases. Do not generate a replacement for an existing update channel or commit private signing material. The release script checks the public-key match before submitting the app.

## Build a release

Update `CFBundleShortVersionString` and increment `CFBundleVersion` in `Resources/Info.plist`. Sparkle compares build numbers to identify newer releases. Run from the repository root on the target architecture; current distribution is built on Apple Silicon.

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift test
sh scripts/release.sh
```

Override `CODE_SIGN_IDENTITY` or `NOTARY_PROFILE` only when using another configured signing environment. The script signs nested Sparkle executables before signing the app, enables the hardened runtime, notarizes and staples the app, then creates and notarizes an APFS DMG. It verifies Gatekeeper acceptance and the Sparkle archive signature.

Outputs are stored in `build/releases/<version>/`: the DMG, corresponding source archive, `appcast.xml`, `SHA256SUMS`, and notarization reports. The script refuses to overwrite an existing version directory. Preserve completed artifacts; move a failed attempt aside before retrying. Building does not upload a release.

## Publish

Review the DMG by mounting it and launching its app. Check the dashboard, terminal, and update menu. For a later release, also exercise an update from the previously published app. A successful signature check alone does not prove the installation path works.

Publish the DMG, source archive, `appcast.xml`, and `SHA256SUMS` together in a stable GitHub Release at `asonas/puipui`, using tag `v<version>` on the verified source commit. The appcast embeds a version-specific DMG URL; the app's feed URL is:

```text
https://github.com/asonas/puipui/releases/latest/download/appcast.xml
```

Create a draft first, inspect its assets and release notes, then publish it as the latest release. Do not overwrite a published DMG: its signature and checksum must remain stable. The feed contains a full installer for the current release, with no delta updates. If a future release raises system requirements, preserve the last compatible appcast entry for older systems.

After publishing, download the assets from GitHub, check the checksum and signature, and use **Check for Updates…** from the previous release. Until the first stable release is public, update checks cannot retrieve the feed.

See Sparkle's [publishing guide](https://sparkle-project.org/documentation/publishing/) and Apple's [notarization documentation](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) for the underlying distribution requirements.
