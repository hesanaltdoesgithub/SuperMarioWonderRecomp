#!/usr/bin/env bash
# One-time setup of the Android build toolchain on your own Linux machine (tested target: Arch / CachyOS).
# Run it yourself, in a terminal, once:   bash tools/selfhosted/setup.sh
#
# Everything except the pacman packages goes into $WONDER_PRIVATE/third_party (default ~/wonder-recomp-private),
# outside the repository and outside the Actions runner's work folder, so it survives re-checkouts.
# Nothing here touches your game dump or keys.
set -euo pipefail

P="${WONDER_PRIVATE:-$HOME/wonder-recomp-private}"
T="$P/third_party"
mkdir -p "$T" "$P/wonder" "$P/build"

echo "== system packages (pacman, needs sudo once)"
sudo pacman -S --needed clang cmake ninja patch git curl python unzip zip jdk21-openjdk spirv-tools

export JAVA_HOME=/usr/lib/jvm/java-21-openjdk

echo "== Vulkan headers 1.4.357"
if [ ! -f "$T/Vulkan-Headers-1.4.357/include/vulkan/vulkan.h" ]; then
    curl -fL https://github.com/KhronosGroup/Vulkan-Headers/archive/refs/tags/v1.4.357.tar.gz | tar -xz -C "$T"
fi
# build_apk.sh wants a folder with Include/ (capital I)
mkdir -p "$T/vk-android"
rm -rf "$T/vk-android/Include"
cp -r "$T/Vulkan-Headers-1.4.357/include" "$T/vk-android/Include"

echo "== .NET SDK 10.0.401 (shader translator)"
if [ ! -x "$T/dotnet/dotnet" ]; then
    mkdir -p "$T/dotnet"
    curl -fL https://builds.dotnet.microsoft.com/dotnet/Sdk/10.0.401/dotnet-sdk-10.0.401-linux-x64.tar.gz | tar -xz -C "$T/dotnet"
fi

echo "== Ryujinx shader translator source (Ryubing, MIT, a82350bb77)"
if [ ! -d "$T/ryubing/src" ]; then
    mkdir -p "$T/ryubing"
    curl -fL https://codeberg.org/Software_arch/Ryubing/archive/a82350bb77.tar.gz | tar -xz -C "$T/ryubing" --strip-components=1
fi

echo "== Python venv"
if [ ! -x "$P/venv/bin/python" ]; then python3 -m venv "$P/venv"; fi
"$P/venv/bin/pip" install --upgrade pip
"$P/venv/bin/pip" install capstone lz4 zstandard fonttools

echo "== Android command-line tools, NDK 28.2, build-tools 35, platform 35"
A="$T/android-sdk"
if [ ! -x "$A/cmdline-tools/latest/bin/sdkmanager" ]; then
    mkdir -p "$A/cmdline-tools"
    curl -fL -o "$T/cmdline-tools.zip" https://dl.google.com/android/repository/commandlinetools-linux-13114758_latest.zip
    rm -rf "$A/cmdline-tools/latest" "$A/cmdline-tools/cmdline-tools"
    unzip -q "$T/cmdline-tools.zip" -d "$A/cmdline-tools"
    mv "$A/cmdline-tools/cmdline-tools" "$A/cmdline-tools/latest"
    rm "$T/cmdline-tools.zip"
fi
export ANDROID_HOME="$A"
echo "-- Read and accept the Android SDK licences:"
"$A/cmdline-tools/latest/bin/sdkmanager" --licenses
"$A/cmdline-tools/latest/bin/sdkmanager" "ndk;28.2.13676358" "build-tools;35.0.0" "platforms;android-35"

echo "== debug signing key (build_apk.sh signs with ~/.android/debug.keystore)"
if [ ! -f "$HOME/.android/debug.keystore" ]; then
    mkdir -p "$HOME/.android"
    "$JAVA_HOME/bin/keytool" -genkeypair -keystore "$HOME/.android/debug.keystore" -storepass android -keypass android \
        -alias androiddebugkey -dname "CN=Android Debug,O=Android,C=US" -keyalg RSA -keysize 2048 -validity 10000
fi

echo
echo "Setup done. Toolchain in: $T"
echo "Next: put prod.keys, title.keys and your Wonder 1.0.0 .xci (or .nsp) in one folder, e.g. ~/wonder,"
echo "then run the 'Build Android APK (self-hosted)' workflow, or locally: bash tools/selfhosted/build_android.sh ~/wonder"
