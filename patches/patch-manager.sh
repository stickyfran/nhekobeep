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
    "0007-beeper-mxid-network-badge.patch"
    "0008-custom-labels-cpp.patch"
)

NEW_FILES=(
    "src/CacheRefreshController.h"
    "src/CacheRefreshController.cpp"
    "resources/qml/ui/CacheRefreshOverlay.qml"
)

CMAKE_FLAGS=(
    -DCMAKE_BUILD_TYPE=Release
    -DUSE_BUNDLED_LMDBXX=ON
    -DUSE_BUNDLED_MTXCLIENT=ON
    -DQT_NO_PRIVATE_MODULE_WARNING=ON
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

    # ── Apply QML changes for Beeper context menu ──
    local QML_ROOMLIST="${NHEKO_DIR}/resources/qml/RoomList.qml"
    if ! grep -q "CustomLabelListModel" "$QML_ROOMLIST" 2>/dev/null; then
        info "Patching RoomList.qml (Custom Labels sub-menu)..."
        sed -i \
          '/onObjectRemoved: (index, object) => tagsMenu.removeItem(object)/a\
\n                \/\/ Custom Beeper labels from user settings\
               MenuSeparator {\
                   visible: CustomLabelListModel.rowCount() > 0\
               }\
               Instantiator {\
                   model: CustomLabelListModel\
\
                   delegate: MenuItem {\
                       property string t: model.tag\
\
                       checkable: true\
                       checked: roomContextMenu.tags !== undefined \&\& roomContextMenu.tags.includes(t)\
                       text: model.displayName\
\
                       onTriggered: Rooms.toggleTag(roomContextMenu.roomid, t, checked)\
                   }\
\
                   onObjectAdded: (index, object) => {\
                       var insertIdx = index + tagsMenu.count - 1;\
                       tagsMenu.insertItem(insertIdx, object);\
                   }\
                   onObjectRemoved: (index, object) => tagsMenu.removeItem(object)\
               }' "$QML_ROOMLIST"
        ok "  Custom Labels sub-menu added"
    else
        ok "  RoomList.qml already patched for custom labels"
    fi

    # ── Apply QML changes for Beeper Custom Labels settings ──
    local QML_SETTINGS="${NHEKO_DIR}/resources/qml/pages/UserSettingsPage.qml"
    if ! grep -q "CustomBeeperLabels" "$QML_SETTINGS" 2>/dev/null; then
        info "Patching UserSettingsPage.qml (Custom Labels settings)..."
        sed -i \
          '/^    }$/a\
\n            \/\/ --- Custom Beeper Labels section ---\
           Rectangle {\
               Layout.fillWidth: true\
               Layout.preferredHeight: 1\
               color: palette.buttonText\
               opacity: 0.3\
           }\
\
           Label {\
               Layout.fillWidth: true\
               font.pointSize: fontMetrics.font.pointSize * 1.3\
               font.weight: Font.DemiBold\
               text: qsTr("Custom Beeper Labels")\
               color: palette.text\
           }\
\
           Label {\
               Layout.fillWidth: true\
               wrapMode: Text.WordWrap\
               text: qsTr("Define custom names and icons for tags.")\
               color: palette.buttonText\
           }\
\
           ColumnLayout {\
               id: customLabelsContainer\
               objectName: "CustomBeeperLabels"\
               Layout.fillWidth: true\
               spacing: Nheko.paddingSmall\
\
               Repeater {\
                   model: CustomLabelListModel\
\
                   delegate: RowLayout {\
                       Layout.fillWidth: true\
                       spacing: Nheko.paddingSmall\
\
                       TextField {\
                           Layout.fillWidth: true\
                           text: model.displayName\
                           placeholderText: qsTr("Display Name")\
                           onTextChanged: CustomLabelListModel.updateLabel(\
                               index, model.tag, text, model.iconKey)\
                       }\
\
                       ComboBox {\
                           id: iconCombo\
                           Layout.preferredWidth: 120\
                           model: CustomLabelListModel.availableIcons()\
                           currentIndex: {\
                               var icons = CustomLabelListModel.availableIcons();\
                               return Math.max(0, icons.indexOf(model.iconKey));\
                           }\
                           onCurrentIndexChanged: {\
                               if (currentIndex >= 0) {\
                                   var icons = CustomLabelListModel.availableIcons();\
                                   CustomLabelListModel.updateLabel(\
                                       index, model.tag, model.displayName,\
                                       icons[currentIndex]);\
                               }\
                           }\
                       }\
\
                       Label {\
                           text: model.tag\
                           color: palette.buttonText\
                           font.pixelSize: fontMetrics.font.pixelSize * 0.85\
                           Layout.preferredWidth: 80\
                           elide: Text.ElideRight\
                       }\
\
                       ImageButton {\
                           Layout.preferredWidth: 22\
                           Layout.preferredHeight: 22\
                           image: ":/icons/icons/ui/delete.svg"\
                           ToolTip.text: qsTr("Remove label")\
                           ToolTip.visible: hovered\
                           hoverEnabled: true\
                           onClicked: CustomLabelListModel.removeLabel(index)\
                       }\
                   }\
               }\
\
               Button {\
                   text: qsTr("Add Custom Label")\
                   Layout.alignment: Qt.AlignLeft\
                   onClicked: addCustomLabelDialog.open()\
               }\
           }\
\
           Dialog {\
               id: addCustomLabelDialog\
               title: qsTr("Add Custom Label")\
               standardButtons: Dialog.Ok | Dialog.Cancel\
               modal: true\
\
               ColumnLayout {\
                   spacing: Nheko.paddingMedium\
                   Label { text: qsTr("Tag:") }\
                   TextField {\
                       id: newTagField\
                       placeholderText: "u.mylabel"\
                       Layout.fillWidth: true\
                   }\
                   Label { text: qsTr("Display Name:") }\
                   TextField {\
                       id: newNameField\
                       placeholderText: qsTr("My Label")\
                       Layout.fillWidth: true\
                   }\
               }\
\
               onAccepted: {\
                   if (newTagField.text \&\& newNameField.text) {\
                       CustomLabelListModel.addLabel(\
                           newTagField.text, newNameField.text,\
                           ":/icons/icons/ui/tag.svg");\
                   }\
               }\
           }' "$QML_SETTINGS"
        ok "  Custom Labels settings section added"
    else
        ok "  UserSettingsPage.qml already patched for custom labels"
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
