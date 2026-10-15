#!/bin/sh
set -eu
swift build --build-system native -c release
# SwiftPM's executable resource accessor must use the macOS app resource directory.
perl -pi -e 's/Bundle\.main\.bundleURL/Bundle.main.resourceURL!/g' .build/release/GhosttyTerminal.build/DerivedSources/resource_bundle_accessor.swift .build/release/Puipui.build/DerivedSources/resource_bundle_accessor.swift
swift build --build-system native -c release
mkdir -p build/Puipui.app/Contents/MacOS
command cp .build/release/Puipui build/Puipui.app/Contents/MacOS/Puipui
command cp Resources/Info.plist build/Puipui.app/Contents/Info.plist
mkdir -p build/Puipui.app/Contents/Resources
ditto .build/release/GhosttyKit_GhosttyTerminal.bundle build/Puipui.app/Contents/Resources/GhosttyKit_GhosttyTerminal.bundle
ditto .build/release/Puipui_Puipui.bundle build/Puipui.app/Contents/Resources/Puipui_Puipui.bundle
codesign --force --sign 'Apple Development: Yuya Fujiwara (55CYFEJC5B)' build/Puipui.app
codesign --verify --strict build/Puipui.app
printf '%s\n' 'Built build/Puipui.app'
