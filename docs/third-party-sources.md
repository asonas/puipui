# Third-party source and rebuilding

puipui is MIT licensed. Bundled dependencies retain their own terms, reproduced in `Resources/ThirdPartyNotices.txt` and the app's `Contents/Resources/ThirdPartyNotices.txt`.

Ghostty includes GNU gettext's libintl. Each release includes a source archive containing puipui, the pinned libghostty-spm wrapper and its patches, Ghostty 1.3.1, and gettext 0.24. This archive provides source for rebuilding the app with a modified library; it is separate from the DMG and is not a Sparkle update.

## Rebuild with a modified library

Use macOS, Xcode, and the Zig version required by Ghostty's `build.zig.zon` (0.15.2 for this release). Other dependencies are fetched by the upstream build tools.

1. Extract the source archive and `gettext-0.24.tar.gz`. Make changes to gettext. In `ghostty/pkg/libintl/build.zig.zon`, replace the `gettext` dependency's `url` and `hash` fields with a `path` pointing to the extracted source directory.
2. From `libghostty-spm`, run `./build.sh --platforms macos --source ../ghostty --skip-tests`. This applies the included patches and builds `BinaryTarget/GhosttyKit.xcframework`.
3. Copy `Package.local.swift` over the wrapper's `Package.swift` to select the local framework. In puipui's `Package.swift`, replace the remote libghostty-spm package declaration with `.package(path: "../libghostty-spm")`.
4. Build puipui with `sh scripts/build-app.sh`, setting `CODE_SIGN_IDENTITY` to your own certificate. For a local ad hoc build, use `CODE_SIGN_IDENTITY=-` and omit the `--timestamp` options from the build script. Launch `build/puipui.app`.

The maintainer's Developer ID certificate and Sparkle private key are not required to rebuild or run a modified app. The public update feed distributes official builds; redistributed modified builds should configure their own feed and update-signing keys.

The archive preserves upstream copyright notices. When upgrading a dependency, refresh its notices from the exact source version.
