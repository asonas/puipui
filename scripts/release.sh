#!/bin/sh
set -eu
git diff --quiet HEAD -- . || { echo 'Commit tracked changes before building a release.' >&2; exit 1; }

export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
export CODE_SIGN_IDENTITY=${CODE_SIGN_IDENTITY:-Developer ID Application: Yuya Fujiwara (QYP65434UW)}
profile=${NOTARY_PROFILE:-YoruMimizukuNotary}
account=as.ason.puipui
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)
arch=$(uname -m)
case "$CODE_SIGN_IDENTITY" in
    'Developer ID Application:'*) ;;
    *) echo 'Release signing requires a Developer ID Application identity.' >&2; exit 1 ;;
esac
case "$version" in
    ''|*[!0-9.]*) echo 'Release version must contain only digits and dots.' >&2; exit 1 ;;
esac
output="build/releases/$version"
mkdir -p build/releases
mkdir "$output"
stage=$(mktemp -d "$PWD/build/release-stage.XXXXXX")
trap 'command rm -rf "$stage"' EXIT HUP INT TERM

notarize() {
    artifact=$1
    report=$2
    xcrun notarytool submit "$artifact" --keychain-profile "$profile" --wait --output-format json > "$report"
    status=$(plutil -extract status raw -o - "$report")
    if [ "$status" != Accepted ]; then
        echo "Notarization failed: $status. See $report." >&2
        exit 1
    fi
}

sh scripts/build-app.sh
tools=.build/artifacts/sparkle/Sparkle/bin
expected=$(/usr/libexec/PlistBuddy -c 'Print SUPublicEDKey' build/puipui.app/Contents/Info.plist)
actual=$("$tools/generate_keys" --account "$account" -p)
if [ "$expected" != "$actual" ]; then
    echo 'Sparkle signing key does not match the public key in the app.' >&2
    exit 1
fi
ditto -c -k --keepParent build/puipui.app "$stage/puipui.zip"
notarize "$stage/puipui.zip" "$output/app-notarization.json"
xcrun stapler staple build/puipui.app
xcrun stapler validate build/puipui.app
spctl --assess --type execute --verbose=2 build/puipui.app

mkdir "$stage/volume"
ditto build/puipui.app "$stage/volume/puipui.app"
ln -s /Applications "$stage/volume/Applications"
dmg="$output/puipui-$version-$arch.dmg"
hdiutil create -volname puipui -srcfolder "$stage/volume" -fs APFS -format ULFO "$dmg"
codesign --timestamp --sign "$CODE_SIGN_IDENTITY" "$dmg"
notarize "$dmg" "$output/dmg-notarization.json"
xcrun stapler staple "$dmg"
xcrun stapler validate "$dmg"
hdiutil verify "$dmg"
spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg"
"$tools/generate_appcast" --account "$account" --maximum-deltas 0 \
    --download-url-prefix "https://github.com/asonas/puipui/releases/download/v$version/" "$output"
signature=$(xmllint --xpath 'string(//*[local-name()="enclosure"]/@*[local-name()="edSignature"])' "$output/appcast.xml")
"$tools/sign_update" --account "$account" --verify "$dmg" "$signature"
source_dir="$stage/source"
mkdir -p "$source_dir/puipui" "$source_dir/libghostty-spm" "$source_dir/ghostty"
git archive --format=tar HEAD -o "$stage/puipui.tar"
tar -xf "$stage/puipui.tar" -C "$source_dir/puipui"
git -C .build/checkouts/libghostty-spm archive --format=tar HEAD -o "$stage/libghostty-spm.tar"
tar -xf "$stage/libghostty-spm.tar" -C "$source_dir/libghostty-spm"
gh api 'repos/ghostty-org/ghostty/tarball/v1.3.1' > "$stage/ghostty.tar.gz"
tar -xzf "$stage/ghostty.tar.gz" -C "$source_dir/ghostty" --strip-components=1
ax https://deps.files.ghostty.org/gettext-0.24.tar.gz -f --max-bytes 100000000 -m 90 -o "$source_dir/gettext-0.24.tar.gz"
command cp docs/third-party-sources.md "$source_dir/README.md"
source_archive="$output/puipui-$version-source.tar.gz"
tar -czf "$source_archive" -C "$source_dir" .
shasum -a 256 "$dmg" "$source_archive" | sed "s|$output/||" > "$output/SHA256SUMS"
printf 'Release artifacts: %s\n' "$output"
printf '%s\n' 'Nothing has been uploaded. Publish the DMG, source archive, appcast.xml, and SHA256SUMS together in a stable GitHub Release.'
