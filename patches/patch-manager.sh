#!/usr/bin/env bash
# ============================================================================
# Nheko Patch Manager — One-shot build
# ============================================================================
# Usage:
#   ./patches/patch-manager.sh         # Full: update → clean → patch → build
#   ./patches/patch-manager.sh build   # Build only (skip patch/update)
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
NHEKO_DIR="${REPO_DIR}/nheko"
NEW_FILES_DIR="$SCRIPT_DIR/new-files"
BUILD_DIR="${REPO_DIR}/build"

# ── Patch files (applied in order) ──────────────────────────────────────────
PATCH_FILES=(
    "0001-beeper-bridge-fake-dm-cleanup.patch"
    "0002-cache-refresh-accessors.patch"
    "0003-cache-refresh-cmakelists.patch"
)

NEW_FILES=(
    "src/CacheRefreshController.h"
    "src/CacheRefreshController.cpp"
    "resources/qml/ui/CacheRefreshOverlay.qml"
)

CMAKE_FLAGS=(
    -DCMAKE_BUILD_TYPE=Release
    -DHUNTER_ENABLED=ON
    -DBUILD_SHARED_LIBS=OFF
    -DUSE_BUNDLED_LMDB=ON
    -DUSE_BUNDLED_LMDBXX=ON
    -DUSE_BUNDLED_MTXCLIENT=ON
    -DUSE_BUNDLED_SPDLOG=ON
    -DUSE_BUNDLED_FMT=ON
    -DUSE_BUNDLED_JSON=ON
    -DUSE_BUNDLED_COEURL=ON
    -DUSE_BUNDLED_LIBCURL=ON
    -DUSE_BUNDLED_OPENSSL=OFF
)

# ── Colors ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'
info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }

# ── 1. Update nheko submodule ──────────────────────────────────────────────
update_nheko() {
    info "Initializing + updating nheko submodule..."
    cd "$REPO_DIR"
    git submodule update --init --recursive 2>/dev/null || true
    cd "$NHEKO_DIR"
    git stash --quiet 2>/dev/null || true
    git fetch origin 2>/dev/null || true
    git reset --hard origin/master 2>/dev/null || git reset --hard origin/main 2>/dev/null || true
    ok "nheko at $(git log --oneline -1 2>/dev/null)"
}

# ── 2. Remove previous build ────────────────────────────────────────────────
clean_build() {
    if [[ -d "$BUILD_DIR" ]]; then
        info "Removing old build directory..."
        rm -rf "$BUILD_DIR"
        ok "Build directory cleaned"
    fi
}

# ── 3. Apply all patches ────────────────────────────────────────────────────
apply_patches() {
    info "Reverting any previously applied patches..."
    cd "$NHEKO_DIR"
    for f in "${PATCH_FILES[@]}"; do
        git apply --reverse "$SCRIPT_DIR/$f" 2>/dev/null || true
    done

    # Remove stale new files
    for f in "${NEW_FILES[@]}"; do
        rm -f "$NHEKO_DIR/$f" 2>/dev/null || true
    done

    # Install new files
    info "Installing new files..."
    for f in "${NEW_FILES[@]}"; do
        local src="$NEW_FILES_DIR/$f"
        local dst="$NHEKO_DIR/$f"
        if [[ -f "$src" ]]; then
            mkdir -p "$(dirname "$dst")"
            cp "$src" "$dst"
            ok "  $f"
        fi
    done

    # ── Apply QML changes directly (bypass corrupt patch file issues) ──
    local QML="${NHEKO_DIR}/resources/qml/pages/UserSettingsPage.qml"
    if ! grep -q "Force Cache Sync" "$QML" 2>/dev/null; then
        info "Patching UserSettingsPage.qml (Force Cache Sync button)..."
        sed -i \
          '/anchors.rightMargin: anchors.leftMargin$/a\
\n            \/\/ --- Force Cache Sync button ---\
            Rectangle {\
                Layout.fillWidth: true\
                Layout.preferredHeight: cacheButtonRow.implicitHeight + Nheko.paddingLarge * 2\
                color: palette.alternateBase\
                radius: 8\
                visible: !CacheRefreshController.inProgress\
\
                ColumnLayout {\
                    id: cacheButtonRow\
                    anchors.centerIn: parent\
                    spacing: Nheko.paddingSmall\
\
                    Label {\
                        Layout.alignment: Qt.AlignHCenter\
                        color: palette.text\
                        font.pointSize: fontMetrics.font.pointSize * 0.9\
                        text: qsTr("If contacts or rooms appear with incorrect names or avatars, use this to force a refresh.")\
                        horizontalAlignment: Text.AlignHCenter\
                        wrapMode: Text.WordWrap\
                        Layout.fillWidth: true\
                        Layout.maximumWidth: 400\
                    }\
\
                    Button {\
                        Layout.alignment: Qt.AlignHCenter\
                        implicitWidth: 220\
                        implicitHeight: 40\
                        text: qsTr("Force Cache Sync")\
\
                        contentItem: Label {\
                            color: palette.highlightedText\
                            font.bold: true\
                            font.pointSize: fontMetrics.font.pointSize * 1.05\
                            horizontalAlignment: Text.AlignHCenter\
                            verticalAlignment: Text.AlignVCenter\
                            text: parent.text\
                        }\
\
                        background: Rectangle {\
                            color: parent.hovered ? Nheko.theme.highlight : Nheko.theme.highlight\
                            opacity: parent.hovered ? 1.0 : 0.85\
                            radius: 6\
                        }\
\
                        onClicked: {\
                            CacheRefreshController.startCacheRefresh();\
                        }\
                    }\
                }\
            }\
\n            \/\/ --- Section separator ---\
            Rectangle {\
                Layout.fillWidth: true\
                Layout.preferredHeight: 1\
                Layout.topMargin: Nheko.paddingMedium\
                color: palette.buttonText\
                opacity: 0.3\
            }' "$QML"
        ok "  Force Cache Sync button added"

        # Add overlay at end of file
        sed -i '/^    }$/a\
\n    \/\/ Overlay that blocks the UI during cache refresh.\
    CacheRefreshOverlay {\
        anchors.fill: parent\
    }' "$QML"
        ok "  CacheRefreshOverlay added"
    else
        ok "  UserSettingsPage.qml already patched"
    fi

    # Apply remaining patch files
    for f in "${PATCH_FILES[@]}"; do
        local pf="$SCRIPT_DIR/$f"
        if [[ ! -f "$pf" ]]; then
            warn "  Patch $f not found, skipping"
            continue
        fi
        info "Applying $f..."

        # Strip CRLF → LF (Windows line endings break git apply on Linux)
        local tmpf
        tmpf=$(mktemp)
        tr -d '\r' < "$pf" > "$tmpf"

        if git apply "$tmpf" 2>/dev/null; then
            ok "  $f"
            rm -f "$tmpf"
        else
            local err
            err=$(git apply --check "$tmpf" 2>&1 || true)
            rm -f "$tmpf"
            error "  $f failed: $err"
            exit 1
        fi
    done
}

# ── 4. Configure cmake with Hunter ──────────────────────────────────────────
configure_cmake() {
    info "Configuring cmake with Hunter (bundled deps)..."
    cmake -S "$NHEKO_DIR" -B "$BUILD_DIR" "${CMAKE_FLAGS[@]}"
    ok "cmake configured"
}

# ── 5. Build ────────────────────────────────────────────────────────────────
do_build() {
    local njobs
    njobs=$(nproc 2>/dev/null || echo 4)
    info "Building nheko ($njobs jobs)..."
    cmake --build "$BUILD_DIR" -- -j"$njobs"
}

# ── Main ────────────────────────────────────────────────────────────────────
main() {
    if [[ "${1:-}" == "build" ]]; then
        # Build only (skip update/clean/patch)
        if [[ ! -d "$BUILD_DIR" ]]; then
            configure_cmake
        fi
        do_build
        echo -e "\n${GREEN}${BOLD}Done!${NC}"
        exit 0
    fi

    # Full workflow
    echo ""
    echo -e "${BOLD}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║       Nheko Patch + Build (auto)                ║${NC}"
    echo -e "${BOLD}╚══════════════════════════════════════════════════╝${NC}"
    echo ""

    echo -e "${BOLD}[1/5] Updating nheko${NC}"
    update_nheko
    echo ""

    echo -e "${BOLD}[2/5] Cleaning${NC}"
    clean_build
    echo ""

    echo -e "${BOLD}[3/5] Applying patches${NC}"
    apply_patches
    echo ""

    echo -e "${BOLD}[4/5] Configuring cmake${NC}"
    configure_cmake
    echo ""

    echo -e "${BOLD}[5/5] Building${NC}"
    if do_build; then
        echo ""
        echo -e "${GREEN}${BOLD}✓ Complete! Binary: $BUILD_DIR/nheko${NC}"
    else
        echo ""
        echo -e "${RED}${BOLD}✗ Build failed${NC}"
        exit 1
    fi
}

main "$@"
