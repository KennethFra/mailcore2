#!/bin/bash
# Rebuilds bin/MailCore2.xcframework.zip: the 2020 framework from
# bin/MailCore2-2020-09-24.xcframework.zip plus an arm64 iOS Simulator slice.
# The device and macOS frameworks are copied unchanged.
set -euo pipefail
unset SDKROOT IPHONEOS_DEPLOYMENT_TARGET

ROOT="$(cd "$(dirname "$0")" && pwd)"
REPO="$(dirname "$ROOT")"
SOURCES="$ROOT/sources"
OUTPUT="$ROOT/output"
LOGS="$ROOT/logs"

# MailCore 5fb0f930 matches the public headers of the 2020 framework.
MAILCORE_REVISION=5fb0f93010ff7af426e72e9066db8cb19b8154be
LIBETPAN_REVISION=5164ba2ebd3c7cbc7a9230aad32bdf8e24e207de
CTEMPLATE_REVISION=2c6ff9ae7d0ae1b973e57dd19859b95282776194
TIDY_REVISION=71aaa8669c664447743bba73e07d70c291548dca
SASL_URL=https://github.com/cyrusimap/cyrus-sasl/releases/download/cyrus-sasl-2.1.26/cyrus-sasl-2.1.26.tar.gz
SASL_SHA256=8fbc5136512b59bb793657f36fadda6359cae3b08f01fd16b3d406f1345b7bc3
DEVICE_SHA256=f1d17949bc6445314b1d7a8cffc7d1d8a848077387f48c6b31a88f5e4d1f725f

SIMULATOR_SETTINGS=(
    -sdk iphonesimulator ARCHS=arm64 ONLY_ACTIVE_ARCH=YES EXCLUDED_ARCHS=
    IPHONEOS_DEPLOYMENT_TARGET=15.0 ENABLE_BITCODE=NO CODE_SIGNING_ALLOWED=NO
    ENABLE_USER_SCRIPT_SANDBOXING=NO
)

checkout() {
    local dir="$SOURCES/$1"
    [[ -d "$dir/.git" ]] || git clone -q "$2" "$dir"
    git -C "$dir" checkout -q --force --detach "$3"
    git -C "$dir" clean -q -fdx
}

rm -rf "$OUTPUT" "$LOGS"
mkdir -p "$SOURCES" "$OUTPUT" "$LOGS"
EXTERNALS="$OUTPUT/externals"

echo "Original framework"
ditto -x -k "$REPO/bin/MailCore2-2020-09-24.xcframework.zip" "$OUTPUT/original"
ORIGINAL="$OUTPUT/original/MailCore2.xcframework"
[[ "$(shasum -a 256 "$ORIGINAL/ios-arm64_armv7/MailCore.framework/MailCore" | awk '{print $1}')" == "$DEVICE_SHA256" ]]

echo "ctemplate and tidy"
for spec in "ctemplate https://github.com/dinhviethoa/ctemplate.git $CTEMPLATE_REVISION ctemplate.xcodeproj ctemplate-ios libctemplate-ios.a ctemplate-ios" \
            "tidy-html5 https://github.com/dinhviethoa/tidy-html5.git $TIDY_REVISION Tidy.xcodeproj tidy libtidy.a tidy-html5-ios"; do
    read -r name url revision project scheme library external <<< "$spec"
    checkout "$name" "$url" "$revision"
    xcodebuild -project "$SOURCES/$name/build-mac/$project" -scheme "$scheme" -configuration Release \
        -destination 'generic/platform=iOS Simulator' -derivedDataPath "$OUTPUT/$name" \
        "${SIMULATOR_SETTINGS[@]}" build > "$LOGS/$name.log" 2>&1
    products="$OUTPUT/$name/Build/Products/Release-iphonesimulator"
    mkdir -p "$EXTERNALS/$external/lib"
    cp "$products/$library" "$EXTERNALS/$external/lib/"
    rsync -aL "$products/include/" "$EXTERNALS/$external/include/"
done

echo "Cyrus SASL"
SASL_ARCHIVE="$SOURCES/cyrus-sasl-2.1.26.tar.gz"
SASL_SOURCE="$OUTPUT/sasl-source"
SASL="$EXTERNALS/libsasl-ios"
[[ -f "$SASL_ARCHIVE" ]] || curl -fsSL --retry 2 "$SASL_URL" -o "$SASL_ARCHIVE"
[[ "$(shasum -a 256 "$SASL_ARCHIVE" | awk '{print $1}')" == "$SASL_SHA256" ]]
mkdir -p "$SASL_SOURCE"
tar -xzf "$SASL_ARCHIVE" -C "$SASL_SOURCE" --strip-components=1
patch -s -d "$SASL_SOURCE" -p1 < "$ROOT/patches/sasl-arm64-simulator.patch"
# makemd5 generates a header during the build, so it has to run on the Mac.
xcrun --sdk macosx clang "$SASL_SOURCE/include/makemd5.c" -o "$SASL_SOURCE/include/makemd5-host"
SASL_FLAGS="-target arm64-apple-ios15.0-simulator -isysroot $(xcrun --sdk iphonesimulator --show-sdk-path)"
(
    cd "$SASL_SOURCE"
    # 2.1.26 is older C that current Clang rejects without these two flags.
    CC="$(xcrun --sdk iphonesimulator --find clang)" CPPFLAGS="$SASL_FLAGS" LDFLAGS="$SASL_FLAGS" \
    CFLAGS="$SASL_FLAGS -Os -Wno-error=implicit-function-declaration -Wno-error=incompatible-function-pointer-types" \
    ./configure --build=arm64-apple-darwin --host=aarch64-apple-darwin --prefix="$SASL" \
        --enable-shared=no --enable-static=yes --without-pam --without-openssl --enable-otp=no \
        --enable-digest=no --with-des=no --enable-login --disable-macos-framework --disable-saslauthd \
        > "$LOGS/sasl-configure.log" 2>&1
    make -j 8 > "$LOGS/sasl.log" 2>&1
    for dir in lib include plugins; do make -C "$dir" install >> "$LOGS/sasl.log" 2>&1; done
)

echo "libetpan"
checkout libetpan https://github.com/dinhviethoa/libetpan.git "$LIBETPAN_REVISION"
(
    cd "$SOURCES/libetpan"
    git apply "$ROOT/patches/libetpan-clang-forward-declaration.patch" "$ROOT/patches/libetpan-ios-system-availability.patch"
    # The Xcode project expects the autotools output; the bundled copy has stale version headers.
    tar xzf build-mac/autogen-result.tar.gz
    for file in build-windows/libetpan_version.h libetpan-config.h.in src/main/libetpan_version.h.in; do
        git show "HEAD:$file" > "$file"
    done
    ./configure --with-expat=no --with-curl=no --enable-debug > "$LOGS/libetpan-configure.log" 2>&1
    make stamp-prepare-target libetpan-config.h >> "$LOGS/libetpan-configure.log" 2>&1
    md5 build-mac/autogen-result.tar.gz > build-mac/autogen-result.md5
    ln -sfn "$SASL" build-mac/libsasl-ios
)
xcodebuild -project "$SOURCES/libetpan/build-mac/libetpan.xcodeproj" -scheme 'libetpan ios' -configuration Release \
    -destination 'generic/platform=iOS Simulator' -derivedDataPath "$OUTPUT/libetpan" \
    "${SIMULATOR_SETTINGS[@]}" build > "$LOGS/libetpan.log" 2>&1
products="$OUTPUT/libetpan/Build/Products/Release-iphonesimulator"
mkdir -p "$EXTERNALS/libetpan-ios/lib"
cp "$products/libetpan-ios.a" "$EXTERNALS/libetpan-ios/lib/"
rsync -aL "$products/include/" "$EXTERNALS/libetpan-ios/include/"

echo "MailCore"
checkout mailcore2 https://github.com/MailCore/mailcore2.git "$MAILCORE_REVISION"
MAILCORE="$SOURCES/mailcore2"
mkdir -p "$MAILCORE/Externals"
cp -R "$EXTERNALS/." "$MAILCORE/Externals/"
# Marks the dependencies as installed so the build doesn't download prebuilt ones.
cp "$MAILCORE/scripts/deps-versions.plist" "$MAILCORE/scripts/installed-deps-versions.plist"
xcodebuild -project "$MAILCORE/build-mac/mailcore2.xcodeproj" -target "mailcore ios" -configuration Release \
    SYMROOT="$OUTPUT/mailcore/products" OBJROOT="$OUTPUT/mailcore/intermediates" \
    VALID_ARCHS=arm64 "${SIMULATOR_SETTINGS[@]}" build > "$LOGS/mailcore.log" 2>&1

echo "Package"
SIMULATOR="$OUTPUT/simulator/MailCore.framework"
ditto "$OUTPUT/mailcore/products/Release-iphonesimulator/MailCore.framework" "$SIMULATOR"
xcrun lipo -create "$SIMULATOR/MailCore" "$ORIGINAL/ios-x86_64-simulator/MailCore.framework/MailCore" -output "$SIMULATOR/MailCore"
codesign --force --sign - --timestamp=none "$SIMULATOR"
xcodebuild -create-xcframework \
    -framework "$ORIGINAL/ios-arm64_armv7/MailCore.framework" \
    -framework "$SIMULATOR" \
    -framework "$ORIGINAL/macos-x86_64/MailCore.framework" \
    -output "$OUTPUT/MailCore2.xcframework" > "$LOGS/package.log" 2>&1
diff -r "$ORIGINAL/ios-arm64_armv7" "$OUTPUT/MailCore2.xcframework/ios-arm64_armv7"
diff -r "$ORIGINAL/macos-x86_64" "$OUTPUT/MailCore2.xcframework/macos-x86_64"
(cd "$OUTPUT" && ditto -c -k --keepParent MailCore2.xcframework MailCore2.xcframework.zip)
xcrun lipo -archs "$OUTPUT/MailCore2.xcframework/ios-arm64_x86_64-simulator/MailCore.framework/MailCore"
echo "Built $OUTPUT/MailCore2.xcframework.zip"
