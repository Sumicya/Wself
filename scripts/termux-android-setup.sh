#!/usr/bin/env bash
# Termux Android SDK + NDK setup for building this project on-device.
#
# This avoids raw.githubusercontent.com and dl.google.com (often blocked/DNS
# broken in China) by pulling the aarch64 SDK/NDK from the community
# `lzhiyong/termux-ndk` GitHub releases.
#
# Usage:
#   bash scripts/termux-android-setup.sh [PROFILE]
#
# PROFILE defaults to ~/.bashrc (the file environment vars are appended to).
# Pass /dev/null to only export for the current shell (no persistent changes).
#
# Optional env:
#   GH_MIRROR       e.g. https://ghproxy.net/https://github.com  (if github.com is slow/blocked)
#   SDK_PLATFORMS   e.g. "platform-tools platforms;android-35 build-tools;35.0.0" (only if sdkmanager works)
set -euo pipefail

: "${PROFILE:=${HOME}/.bashrc}"
: "${GH_MIRROR:=https://github.com}"
: "${ANDROID_HOME:=${HOME}/Android/Sdk}"
: "${NDK_VERSION:=android-ndk-r29}"

JAVA_HOME_TERMUX="$PREFIX/lib/jvm/java-21-openjdk"
NDK_HOME="$ANDROID_HOME/ndk/$NDK_VERSION"
NDK_TOOLCHAINS="$NDK_HOME/toolchains/llvm/prebuilt/linux-aarch64"

# --- write persistent env ----------------------------------------------------
env_block="$(cat <<EOF

# WCX / Termux Android build environment
export JAVA_HOME="$JAVA_HOME_TERMUX"
export ANDROID_HOME="$ANDROID_HOME"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export ANDROID_NDK_HOME="$NDK_HOME"
export ANDROID_NDK_ROOT="$NDK_HOME"
export ANDROID_NDK_TOOLCHAINS="$NDK_TOOLCHAINS"
export PATH="\$PATH:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$NDK_HOME:$NDK_TOOLCHAINS/bin"
EOF
)"

if [[ "$PROFILE" != "/dev/null" ]]; then
  mkdir -p "$(dirname "$PROFILE")"
  if ! grep -q "WCX / Termux Android build environment" "$PROFILE" 2>/dev/null; then
    printf '%s\n' "$env_block" >> "$PROFILE"
  fi
fi

export JAVA_HOME="$JAVA_HOME_TERMUX"
export ANDROID_HOME
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export ANDROID_NDK_HOME="$NDK_HOME"
export ANDROID_NDK_ROOT="$NDK_HOME"
export ANDROID_NDK_TOOLCHAINS="$NDK_TOOLCHAINS"
export PATH="$PATH:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$NDK_HOME:$NDK_TOOLCHAINS/bin"

echo "==> Target env:"
echo "    ANDROID_HOME=$ANDROID_HOME"
echo "    ANDROID_NDK_HOME=$ANDROID_NDK_HOME"
echo "    JAVA_HOME=$JAVA_HOME"

# --- Termux packages -----------------------------------------------------------
echo "==> Installing Termux build packages: aapt aapt2 aidl android-tools apksigner d8 jq unzip wget"
pkg update
pkg install aapt aapt2 aidl android-tools apksigner d8 jq unzip wget -y

# --- Android SDK (aarch64 build from lzhiyong) ----------------------------------
mkdir -p "$ANDROID_HOME"
SDK_ZIP="$ANDROID_HOME/android-sdk-aarch64.zip"
if [[ ! -d "$ANDROID_HOME/cmdline-tools" ]]; then
  echo "==> Downloading Android SDK (aarch64) from lzhiyong/termux-ndk"
  wget --tries=100 --retry-connrefused --waitretry=5 \
    -O "$SDK_ZIP" \
    "$GH_MIRROR/lzhiyong/termux-ndk/releases/download/android-sdk/android-sdk-aarch64.zip"
  unzip -qo "$SDK_ZIP" -d "$ANDROID_HOME"
  rm -f "$SDK_ZIP"
fi

# The lzhiyong archive historically extracts to <root>/android-sdk/*; normalize.
if [[ -d "$ANDROID_HOME/android-sdk" ]]; then
  shopt -s dotglob
  mv "$ANDROID_HOME/android-sdk/"* "$ANDROID_HOME/"
  rmdir "$ANDROID_HOME/android-sdk"
  shopt -u dotglob
fi

# Wrap sdkmanager into PATH (the archive's bin scripts reference its own root).
if [[ ! -e "$PREFIX/bin/sdkmanager" ]]; then
  cat > "$PREFIX/bin/sdkmanager" <<EOF
#!/data/data/com.termux/files/usr/bin/bash
exec "$ANDROID_HOME/tools/bin/sdkmanager" --sdk_root="$ANDROID_HOME" "\$@"
EOF
  chmod +x "$PREFIX/bin/sdkmanager"
fi

# --- Android NDK (aarch64 from lzhiyong) -----------------------------------------
mkdir -p "$ANDROID_HOME/ndk"
if [[ ! -d "$NDK_HOME" ]]; then
  echo "==> Downloading $NDK_VERSION (aarch64) from lzhiyong/termux-ndk"
  NDK_TAR="$ANDROID_HOME/$NDK_VERSION-aarch64.tar.xz"
  wget --tries=100 --retry-connrefused --waitretry=5 \
    -O "$NDK_TAR" \
    "$GH_MIRROR/lzhiyong/termux-ndk/releases/download/android-ndk/$NDK_VERSION-aarch64.tar.xz"
  xz -d -f "$NDK_TAR"
  tar -xf "$ANDROID_HOME/$NDK_VERSION-aarch64.tar" -C "$ANDROID_HOME/ndk" || true
  rm -f "$ANDROID_HOME/$NDK_VERSION-aarch64.tar"*
fi

# --- Gradle aapt2 override --------------------------------------------------------
mkdir -p "$HOME/.gradle"
if ! grep -q "android.aapt2FromMavenOverride" "$HOME/.gradle/gradle.properties" 2>/dev/null; then
  printf '\n# Termux: use the repo aapt2 instead of the Maven/x86_64 one\nandroid.aapt2FromMavenOverride=%s/bin/aapt2\n' "$PREFIX" >> "$HOME/.gradle/gradle.properties"
fi

# --- optional SDK components ------------------------------------------------------
if [[ -n "${SDK_PLATFORMS:-}" ]]; then
  echo "==> Installing SDK components: $SDK_PLATFORMS"
  echo y | sdkmanager "$SDK_PLATFORMS"
fi

echo
echo "==> Done. In a new shell run:"
echo "    cd ~/Wself && ./gradlew -PcompileSdk=36 -PtargetSdk=36 assembleStandardRelease"
echo
echo "    (Fall back to -PcompileSdk=35 -PtargetSdk=35 if AGP says API 36 is missing.)"
