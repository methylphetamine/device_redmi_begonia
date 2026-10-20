#!/usr/bin/env bash
#
# Sync the Lunaris AOSP tree, overlay this device tree, and build the begonia
# ROM. The generated zip path is written to $GITHUB_OUTPUT when available.
#
set -eo pipefail

: "${ROM_DIR:?ROM_DIR is required}"
: "${DEVICE_SRC:?DEVICE_SRC is required}"
: "${ROM_MANIFEST_URL:?ROM_MANIFEST_URL is required}"
: "${ROM_BRANCH:?ROM_BRANCH is required}"
: "${LUNCH_TARGET:?LUNCH_TARGET is required}"
: "${MAKE_TARGET:?MAKE_TARGET is required}"
: "${KERNEL_REPO:?KERNEL_REPO is required}"
: "${KERNEL_BRANCH:?KERNEL_BRANCH is required}"
: "${VENDOR_REPO:?VENDOR_REPO is required}"
: "${VENDOR_BRANCH:?VENDOR_BRANCH is required}"

WITH_GMS="${WITH_GMS:-false}"

export PATH="$HOME/bin:$PATH"
export LC_ALL="${LC_ALL:-C}"
export LINEAGE_BUILDTYPE="${LINEAGE_BUILDTYPE:-UNOFFICIAL}"
export CCACHE_DIR="${CCACHE_DIR:-$HOME/.ccache}"
export CCACHE_MAXSIZE="${CCACHE_MAXSIZE:-8G}"
if command -v ccache >/dev/null 2>&1; then
    export USE_CCACHE=1
    CCACHE_EXEC="$(command -v ccache)"
    export CCACHE_EXEC
fi

mkdir -p "$HOME" "$ROM_DIR" "$CCACHE_DIR" "$ROM_DIR/out/ci"
cd "$ROM_DIR"

git config --global user.name "GitHub Actions"
git config --global user.email "actions@github.com"
git config --global color.ui false
git lfs install --skip-repo >/dev/null 2>&1 || true

echo "==> Initializing Lunaris manifest: $ROM_MANIFEST_URL ($ROM_BRANCH)"
repo init -u "$ROM_MANIFEST_URL" -b "$ROM_BRANCH" --git-lfs --depth=1

echo "==> Adding begonia dependencies"
mkdir -p .repo/local_manifests
cat > .repo/local_manifests/begonia.xml <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<manifest>
  <remote name="begonia-gh" fetch="https://github.com/" sync-j="4" />

  <project path="kernel/xiaomi/mt6785"
           name="${KERNEL_REPO}"
           remote="begonia-gh"
           revision="${KERNEL_BRANCH}"
           clone-depth="1" />

  <project path="vendor/redmi/begonia"
           name="${VENDOR_REPO}"
           remote="begonia-gh"
           revision="${VENDOR_BRANCH}"
           clone-depth="1" />

  <project path="vendor/redmi/begonia-ims"
           name="begonia-dev/android_vendor_redmi_begonia-ims"
           remote="begonia-gh"
           revision="14.0"
           clone-depth="1" />

  <project path="hardware/mediatek"
           name="LineageOS/android_hardware_mediatek"
           remote="begonia-gh"
           revision="lineage-23.2"
           clone-depth="1" />

  <project path="hardware/xiaomi"
           name="LineageOS/android_hardware_xiaomi"
           remote="begonia-gh"
           revision="lineage-23.2"
           clone-depth="1" />

  <project path="device/mediatek/sepolicy_vndr"
           name="LineageOS/android_device_mediatek_sepolicy_vndr"
           remote="begonia-gh"
           revision="lineage-23.2"
           clone-depth="1" />
</manifest>
EOF

echo "==> Syncing source (this is the long step)"
if ! repo sync -c -j"$(nproc)" --force-sync --no-clone-bundle --no-tags; then
    echo "==> repo sync failed; retrying once after 30 seconds" >&2
    sleep 30
    repo sync -c -j"$(nproc)" --force-sync --no-clone-bundle --no-tags
fi

echo "==> Overlaying device tree from $DEVICE_SRC"
mkdir -p device/redmi/begonia
rsync -a --delete --exclude .git "$DEVICE_SRC/" device/redmi/begonia/

DEVICE_MAKEFILE="$ROM_DIR/device/redmi/begonia/lineage_begonia.mk"
if [ -f "$DEVICE_MAKEFILE" ]; then
    if [ "$WITH_GMS" = "true" ]; then
        sed -i 's/^WITH_GMS := .*/WITH_GMS := true/' "$DEVICE_MAKEFILE"
    else
        sed -i 's/^WITH_GMS := .*/WITH_GMS := false/' "$DEVICE_MAKEFILE"
    fi
    if grep -q '^WITH_PIXEL_LAUNCHER' "$DEVICE_MAKEFILE"; then
        sed -i 's/^WITH_PIXEL_LAUNCHER := .*/WITH_PIXEL_LAUNCHER := false/' "$DEVICE_MAKEFILE"
    else
        sed -i '/^WITH_GMS := /a WITH_PIXEL_LAUNCHER := false' "$DEVICE_MAKEFILE"
    fi
fi
echo "==> Build variant: WITH_GMS=$WITH_GMS, WITH_PIXEL_LAUNCHER=false"

echo "==> Configuring build environment"
# shellcheck disable=SC1091
source build/envsetup.sh
lunch "$LUNCH_TARGET"

echo "==> Building target: $MAKE_TARGET"
LOG="$ROM_DIR/out/build.log"
set -o pipefail
m "$MAKE_TARGET" 2>&1 | tee "$LOG"

PRODUCT_OUT="$ROM_DIR/out/target/product/begonia"
ROM_ZIP=$(find "$PRODUCT_OUT" -maxdepth 1 -type f -name '*.zip' -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -n1 | cut -d' ' -f2- || true)
if [ -z "${ROM_ZIP:-}" ] || [ ! -f "$ROM_ZIP" ]; then
    echo "::error::Build finished but no ROM zip was found in $PRODUCT_OUT"
    find "$PRODUCT_OUT" -maxdepth 1 -type f -printf '%f\n' 2>/dev/null || true
    exit 1
fi

SHA256=$(sha256sum "$ROM_ZIP" | awk '{print $1}')
SIZE_BYTES=$(stat -c '%s' "$ROM_ZIP")
BUILD_INFO="$ROM_DIR/out/ci/build-info.txt"
{
    echo "device=begonia"
    echo "rom=lunaris"
    echo "rom_branch=$ROM_BRANCH"
    echo "device_repo=$(git -C "$DEVICE_SRC" remote get-url origin 2>/dev/null || echo unknown)"
    echo "device_commit=$(git -C "$DEVICE_SRC" rev-parse HEAD 2>/dev/null || echo unknown)"
    echo "kernel=$KERNEL_REPO@$KERNEL_BRANCH"
    echo "kernel_commit=$(git -C kernel/xiaomi/mt6785 rev-parse HEAD 2>/dev/null || echo unknown)"
    echo "vendor=$VENDOR_REPO@$VENDOR_BRANCH"
    echo "vendor_commit=$(git -C vendor/redmi/begonia rev-parse HEAD 2>/dev/null || echo unknown)"
    echo "lunch_target=$LUNCH_TARGET"
    echo "make_target=$MAKE_TARGET"
    echo "with_gms=$WITH_GMS"
    echo "with_pixel_launcher=false"
    echo "rom_zip=$ROM_ZIP"
    echo "size_bytes=$SIZE_BYTES"
    echo "sha256=$SHA256"
    echo "built_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} | tee "$BUILD_INFO"

if [ -n "${GITHUB_OUTPUT:-}" ]; then
    {
        echo "rom_zip=$ROM_ZIP"
        echo "sha256=$SHA256"
        echo "size_bytes=$SIZE_BYTES"
        echo "build_info=$BUILD_INFO"
    } >> "$GITHUB_OUTPUT"
fi

echo "==> ROM zip: $ROM_ZIP"
echo "==> SHA256: $SHA256"
