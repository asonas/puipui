#!/bin/sh
set -eu
swift build --build-system native -c release
# SwiftPM's executable resource accessor must use the macOS app resource directory.
perl -pi -e 's/Bundle\.main\.bundleURL/Bundle.main.resourceURL!/g' .build/release/GhosttyTerminal.build/DerivedSources/resource_bundle_accessor.swift .build/release/Puipui.build/DerivedSources/resource_bundle_accessor.swift
swift build --build-system native -c release
mkdir -p build/puipui.app/Contents/MacOS
command cp .build/release/Puipui build/puipui.app/Contents/MacOS/puipui
command cp Resources/Info.plist build/puipui.app/Contents/Info.plist
mkdir -p build/puipui.app/Contents/Resources
command cp Resources/AppIcon.icns build/puipui.app/Contents/Resources/AppIcon.icns
ditto .build/release/GhosttyKit_GhosttyTerminal.bundle build/puipui.app/Contents/Resources/GhosttyKit_GhosttyTerminal.bundle
ditto .build/release/Puipui_Puipui.bundle build/puipui.app/Contents/Resources/Puipui_Puipui.bundle
codesign --force --sign 'Apple Development: Yuya Fujiwara (55CYFEJC5B)' build/puipui.app
codesign --verify --strict build/puipui.app
printf '%s\n' 'Built build/puipui.app'
