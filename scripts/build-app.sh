#!/bin/sh
set -eu
identity=${CODE_SIGN_IDENTITY:-Apple Development: Yuya Fujiwara (55CYFEJC5B)}
swift build --build-system native -c release
# SwiftPM's executable resource accessor must use the macOS app resource directory.
perl -pi -e 's/Bundle\.main\.bundleURL/Bundle.main.resourceURL!/g' .build/release/GhosttyTerminal.build/DerivedSources/resource_bundle_accessor.swift .build/release/Puipui.build/DerivedSources/resource_bundle_accessor.swift
swift build --build-system native -c release
command rm -rf build/puipui.app
mkdir -p build/puipui.app/Contents/MacOS
command cp .build/release/Puipui build/puipui.app/Contents/MacOS/puipui
command cp Resources/Info.plist build/puipui.app/Contents/Info.plist
mkdir -p build/puipui.app/Contents/Resources
command cp LICENSE build/puipui.app/Contents/Resources/LICENSE.txt
command cp Resources/ThirdPartyNotices.txt build/puipui.app/Contents/Resources/ThirdPartyNotices.txt
command cp Resources/AppIcon.icns build/puipui.app/Contents/Resources/AppIcon.icns
ditto .build/release/GhosttyKit_GhosttyTerminal.bundle build/puipui.app/Contents/Resources/GhosttyKit_GhosttyTerminal.bundle
ditto .build/release/Puipui_Puipui.bundle build/puipui.app/Contents/Resources/Puipui_Puipui.bundle
mkdir -p build/puipui.app/Contents/Frameworks
framework=build/puipui.app/Contents/Frameworks/Sparkle.framework
ditto .build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework "$framework"
codesign --force --timestamp --options runtime --sign "$identity" "$framework/Versions/B/XPCServices/Installer.xpc"
codesign --force --timestamp --options runtime --preserve-metadata=entitlements --sign "$identity" "$framework/Versions/B/XPCServices/Downloader.xpc"
codesign --force --timestamp --options runtime --sign "$identity" "$framework/Versions/B/Autoupdate"
codesign --force --timestamp --options runtime --sign "$identity" "$framework/Versions/B/Updater.app"
codesign --force --timestamp --options runtime --sign "$identity" "$framework"
codesign --force --timestamp --options runtime --sign "$identity" build/puipui.app
codesign --verify --deep --strict build/puipui.app
printf '%s\n' 'Built build/puipui.app'
