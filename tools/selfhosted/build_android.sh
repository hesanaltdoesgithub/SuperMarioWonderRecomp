#!/usr/bin/env bash
# Build the Wonder Android APK from your own dump, entirely on this machine (docs/BUILD.md, Linux steps 2-6 + Android).
# Used by .github/workflows/android-apk-selfhosted.yml, and runnable by hand:
#
#   bash tools/selfhosted/build_android.sh <dump folder> [jobs] [pack_data: 0|1]
#
# <dump folder> holds prod.keys, title.keys and the 1.0.0 .xci/.nsp. Nothing from it, and nothing built from it,
# is uploaded anywhere: the APK and data zip stay in $WONDER_PRIVATE/wonder (default ~/wonder-recomp-private/wonder).
# Every stage is resumable: re-run after a crash or a power-off and finished stages are skipped.
set -euo pipefail

DUMP="${1:?usage: build_android.sh <dump folder> [jobs] [pack_data]}"
DUMP="${DUMP/#\~/$HOME}"
JOBS="${2:-auto}"
PACK="${3:-0}"
P="${WONDER_PRIVATE:-$HOME/wonder-recomp-private}"
T="$P/third_party"
root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root"

# The repository's scripts all use ./private: point it at the persistent folder outside the checkout.
if [ -e private ] && [ ! -L private ]; then
    echo "./private exists and is not a link; move it into $P first" >&2; exit 1
fi
ln -sfn "$P" private
W=private/wonder
mkdir -p "$W" private/build

# Toolchain from setup.sh
for f in "$T/vk-android/Include/vulkan/vulkan.h" "$T/dotnet/dotnet" "$P/venv/bin/python" \
         "$T/android-sdk/ndk/28.2.13676358" "$HOME/.android/debug.keystore"; do
    [ -e "$f" ] || { echo "missing $f: run bash tools/selfhosted/setup.sh once first" >&2; exit 1; }
done
export JAVA_HOME="${JAVA_HOME:-/usr/lib/jvm/java-21-openjdk}"
export ANDROID_HOME="$T/android-sdk" VULKAN_SDK="$T/vk-android"
export DOTNET_ROOT="$T/dotnet" PATH="$T/dotnet:$JAVA_HOME/bin:$PATH" DOTNET_CLI_TELEMETRY_OPTOUT=1
PY="$P/venv/bin/python"

# Parallel jobs: about 2 GB of RAM per compile of the generated code, never more than the cores.
if [ "$JOBS" = auto ]; then
    mem_gb=$(( $(awk '/MemTotal/ {print $2}' /proc/meminfo) / 1024 / 1024 ))
    JOBS=$(( mem_gb / 2 ))
    cores=$(nproc)
    [ "$JOBS" -le "$cores" ] || JOBS=$cores
    [ "$JOBS" -ge 1 ] || JOBS=1
fi
free_gb=$(( $(df -Pk "$P/" | awk 'NR==2 {print $4}') / 1024 / 1024 ))
echo "jobs: $JOBS   RAM: $(( $(awk '/MemTotal/ {print $2}' /proc/meminfo) / 1024 / 1024 )) GB   free disk at $P: ${free_gb} GB"
[ "$free_gb" -ge 25 ] || echo "WARNING: under 25 GB free; the build may run out of disk"

stage() { echo; echo "===== $1 ($(date +%H:%M))"; }
done_mark() { touch "$W/.done_$1"; }
is_done() { [ -f "$W/.done_$1" ]; }

stage "1/6 import the game (keys + XCI/NSP -> exefs, romfs)"
if ! is_done import; then
    ls "$DUMP"/prod.keys >/dev/null
    conts=()
    for c in "$DUMP"/*.xci "$DUMP"/*.nsp; do [ -f "$c" ] && conts+=( "$c" ); done
    [ "${#conts[@]}" -ge 1 ] || { echo "no .xci or .nsp in $DUMP" >&2; exit 1; }
    tk=(); [ -f "$DUMP/title.keys" ] && tk=( "$DUMP/title.keys" )
    CC=clang CXX=clang++ cmake -S android/wonder/importer -B private/build/importer -G Ninja
    ninja -C private/build/importer
    private/build/importer/nximport --exefs --out "$W" "$DUMP/prod.keys" "${tk[@]}" "${conts[@]}"
    done_mark import
else echo "already done"; fi

stage "2/6 recompile the CPU code (main: ~2.4 GB RAM, slow on a weak CPU)"
if ! is_done recomp; then
    "$PY" -m recomp "$W/exefs/main" "$W/gen/main" --name main --base 0x4000000000
    "$PY" -m recomp "$W/exefs/sdk"  "$W/gen/sdk"  --name sdk  --base 0x4010000000
    done_mark recomp
else echo "already done"; fi

stage "3/6 build the shader translator"
H=private/build/spirv_harness/bin/Release/net10.0/spirv_harness.dll
if [ ! -f "$H" ]; then dotnet build tools/maxwell/spirv_harness/SpirvHarness.csproj -c Release -m:2; else echo "already done"; fi

stage "4/6 extract and translate the shaders"
if ! is_done shaders; then
    rm -rf "$W/shaders_extracted" "$W/spirv"
    JOBS=$JOBS PY="$PY" tools/extract_shaders.sh "$W"
    dotnet "$H" --batch "$W/shaders_extracted" --out "$W/spirv" --jobs "$JOBS" --no-val
    n=$(ls "$W"/spirv/*.spv | wc -l)
    echo "shaders: $n (expected 12751)"
    [ -f "$W/spirv/results.tsv" ] || { echo "no results.tsv" >&2; exit 1; }
    done_mark shaders
else echo "already done"; fi
mkdir -p "$W/fonts"; cp android/wonder/assets/fonts/shared_5.ttf "$W/fonts/"

stage "5/6 build the APK (the long one; resumes where it stopped)"
CMAKE_BUILD_PARALLEL_LEVEL=$JOBS bash android/build_apk.sh --game wonder

stage "6/6 data zip"
if [ "$PACK" = 1 ]; then
    "$PY" tools/pack_phone_wonder.py --root "$W" --out "$W/Wonder-data.zip"
else
    echo "skipped (the app can also import the game on the phone from prod.keys + the XCI)"
fi

echo
echo "APK: $(readlink -f "$W/apk/wonder.apk")"
[ "$PACK" = 1 ] && echo "data: $(readlink -f "$W/Wonder-data.zip")"
echo "For your own use only: never upload or share these files."
