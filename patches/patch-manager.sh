#!/usr/bin/env bash
# ============================================================================
# Nheko Patch Manager
# ============================================================================
# Usage:
#   ./patches/patch-manager.sh              # Interactive menu
#   ./patches/patch-manager.sh list         # List patches and their status
#   ./patches/patch-manager.sh apply all    # Apply all patches
#   ./patches/patch-manager.sh apply 0001   # Apply a specific patch
#   ./patches/patch-manager.sh revert all   # Revert all patches
#   ./patches/patch-manager.sh revert 0002  # Revert a specific patch
#   ./patches/patch-manager.sh fresh        # Full: update + clean + patch + build
#
# To add a new patch:
#   1. Generate your patch file with: git format-patch -1
#   2. Place it in patches/ with a descriptive name like 0005-my-feature.patch
#   3. Add a description entry in the PATCHES array below
#   4. If it adds new files, add entries in NEW_FILES array
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
NHEKO_DIR="${REPO_DIR}/nheko"
NEW_FILES_DIR="$SCRIPT_DIR/new-files"
BUILD_DIR="${REPO_DIR}/build"

# --------------------------------------------------------------------------
# Patch registry
#   Format: prefix|"Description"
# --------------------------------------------------------------------------
PATCHES=(
    "0001|Beeper bridge fake-DM cleanup (room names & avatars)"
    "0002|Cache refresh controller — LMDB accessors (Cache.cpp, Cache_p.h)"
    "0003|Cache refresh controller — CMakeLists.txt source list"
    "0004|Cache refresh controller — UserSettingsPage.qml button & overlay"
)

# --------------------------------------------------------------------------
# New files to install (from patches/new-files/ into nheko/)
# Format: src_relpath = dest_relpath (relative to nheko/)
# --------------------------------------------------------------------------
NEW_FILES=(
    "src/CacheRefreshController.h = src/CacheRefreshController.h"
    "src/CacheRefreshController.cpp = src/CacheRefreshController.cpp"
    "resources/qml/ui/CacheRefreshOverlay.qml = resources/qml/ui/CacheRefreshOverlay.qml"
)

# --------------------------------------------------------------------------
# CMake build flags — Hunter-based to avoid system dependency hell
# --------------------------------------------------------------------------
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

# --------------------------------------------------------------------------
# Color helpers
# --------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }

# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------

find_patch() {
    local prefix="$1"
    if [[ -f "$SCRIPT_DIR/$prefix" ]]; then
        echo "$SCRIPT_DIR/$prefix"
        return 0
    fi
    local matches=()
    while IFS= read -r -d '' f; do
        matches+=("$f")
    done < <(find "$SCRIPT_DIR" -maxdepth 1 -name "${prefix}*.patch" -print0 2>/dev/null || true)
    [[ ${#matches[@]} -eq 0 ]] && return 1
    echo "${matches[0]}"
}

is_applied() {
    local patch_file="$1"
    git apply --check "$patch_file" --reverse 2>/dev/null
}

new_files_installed() {
    for entry in "${NEW_FILES[@]}"; do
        local dest="${entry##*=}"
        dest="$(echo "$dest" | xargs)"
        [[ ! -f "$NHEKO_DIR/$dest" ]] && return 1
    done
    return 0
}

install_new_files() {
    info "Installing new files..."
    for entry in "${NEW_FILES[@]}"; do
        local src="${entry%%=*}"
        src="$(echo "$src" | xargs)"
        local dest="${entry##*=}"
        dest="$(echo "$dest" | xargs)"
        local src_path="$NEW_FILES_DIR/$src"
        local dest_path="$NHEKO_DIR/$dest"
        if [[ ! -f "$src_path" ]]; then
            warn "Source not found: $src_path — skipping"
            continue
        fi
        mkdir -p "$(dirname "$dest_path")"
        cp "$src_path" "$dest_path"
        ok "Installed $dest"
    done
}

remove_new_files() {
    info "Removing new files..."
    for entry in "${NEW_FILES[@]}"; do
        local dest="${entry##*=}"
        dest="$(echo "$dest" | xargs)"
        local dest_path="$NHEKO_DIR/$dest"
        if [[ -f "$dest_path" ]]; then
            rm "$dest_path"
            ok "Removed $dest"
        fi
    done
}

# Revert all previously applied patches (in reverse order)
revert_all_applied() {
    info "Checking for previously applied patches..."
    for ((idx = ${#PATCHES[@]} - 1; idx >= 0; idx--)); do
        local prefix="${PATCHES[$idx]%%|*}"
        local patch_file
        patch_file="$(find_patch "$prefix" 2>/dev/null || true)"
        if [[ -n "$patch_file" ]] && is_applied "$patch_file" 2>/dev/null; then
            info "Reverting $(basename "$patch_file")..."
            cd "$NHEKO_DIR"
            git apply --reverse "$patch_file" 2>/dev/null || true
            ok "Reverted $(basename "$patch_file")"
        fi
    done
    remove_new_files
}

# Update nheko submodule to latest upstream
update_nheko() {
    info "Updating nheko submodule..."

    # Init submodule if not yet done
    if [[ ! -f "$NHEKO_DIR/CMakeLists.txt" ]]; then
        cd "$REPO_DIR"
        git submodule update --init --recursive
    fi

    cd "$NHEKO_DIR"

    # Stash any local changes (like previously applied patches)
    if ! git diff --quiet HEAD 2>/dev/null; then
        warn "Stashing local changes in nheko..."
        git stash --quiet
    fi

    # Fetch and reset to upstream master
    info "Fetching latest nheko upstream..."
    git fetch origin 2>/dev/null || true
    git checkout master 2>/dev/null || git checkout main 2>/dev/null || true
    git reset --hard origin/master 2>/dev/null || git reset --hard origin/main 2>/dev/null || true

    ok "nheko is now at $(git log --oneline -1)"
    cd "$REPO_DIR"
}

# Remove build directory for clean build
clean_build() {
    if [[ -d "$BUILD_DIR" ]]; then
        info "Removing old build directory..."
        rm -rf "$BUILD_DIR"
    fi
}

# Run cmake configure
cmake_configure() {
    info "Configuring build with Hunter (bundled deps)..."
    cmake -S "$NHEKO_DIR" -B "$BUILD_DIR" "${CMAKE_FLAGS[@]}"
}

# Run cmake build
cmake_build() {
    info "Building nheko ($(nproc 2>/dev/null || echo 4) jobs)..."
    cmake --build "$BUILD_DIR" -- -j"$(nproc 2>/dev/null || echo 4)"
}

# --------------------------------------------------------------------------
# Commands
# --------------------------------------------------------------------------

cmd_list() {
    echo -e "\n${BOLD}Available Patches:${NC}\n"
    for entry in "${PATCHES[@]}"; do
        local prefix="${entry%%|*}"
        local desc="${entry#*|}"
        local patch_file
        patch_file="$(find_patch "$prefix" 2>/dev/null || true)"
        local status
        if [[ -n "$patch_file" ]] && is_applied "$patch_file" 2>/dev/null; then
            status="${GREEN}APPLIED${NC}"
        elif [[ -n "$patch_file" ]]; then
            status="${YELLOW}NOT APPLIED${NC}"
        else
            status="${RED}FILE MISSING${NC}"
        fi
        printf "  %-6s %-60s %b\n" "$prefix" "$desc" "$status"
    done
    echo ""
    if new_files_installed; then
        echo -e "  ${GREEN}New files: INSTALLED${NC}"
    else
        echo -e "  ${YELLOW}New files: NOT INSTALLED${NC}"
    fi
    echo ""
}

cmd_apply() {
    local target="${1:-}"

    if [[ "$target" == "all" ]]; then
        install_new_files
        for entry in "${PATCHES[@]}"; do
            local prefix="${entry%%|*}"
            cmd_apply "$prefix"
        done
        return
    fi

    local patch_file
    patch_file="$(find_patch "$target" 2>/dev/null || true)"
    if [[ -z "$patch_file" ]]; then
        error "No patch found matching '$target'"
        return 1
    fi

    if is_applied "$patch_file" 2>/dev/null; then
        warn "Patch '$(basename "$patch_file")' is already applied."
        return 0
    fi

    info "Applying $(basename "$patch_file")..."
    cd "$NHEKO_DIR"

    # Strip CRLF for Windows-generated patches
    local clean_patch="$patch_file.clean"
    if grep -q $'\r' "$patch_file" 2>/dev/null; then
        warn "Detected CRLF — converting to LF..."
        tr -d '\r' < "$patch_file" > "$clean_patch"
    else
        cp "$patch_file" "$clean_patch"
    fi

    if git apply --verbose "$clean_patch" 2>/dev/null; then
        ok "Applied $(basename "$patch_file")"
        rm -f "$clean_patch"
    else
        error "Failed to apply $(basename "$patch_file")"
        echo -e "${RED}$(git apply --check "$clean_patch" 2>&1)${NC}"
        rm -f "$clean_patch"
        return 1
    fi
}

cmd_revert() {
    local target="${1:-}"

    if [[ "$target" == "all" ]]; then
        for ((idx = ${#PATCHES[@]} - 1; idx >= 0; idx--)); do
            local prefix="${PATCHES[$idx]%%|*}"
            cmd_revert "$prefix"
        done
        remove_new_files
        return
    fi

    local patch_file
    patch_file="$(find_patch "$target" 2>/dev/null || true)"
    if [[ -z "$patch_file" ]]; then
        error "No patch found matching '$target'"
        return 1
    fi

    if ! is_applied "$patch_file" 2>/dev/null; then
        warn "Patch '$(basename "$patch_file")' is not applied."
        return 0
    fi

    info "Reverting $(basename "$patch_file")..."
    cd "$NHEKO_DIR"
    if git apply --reverse "$patch_file"; then
        ok "Reverted $(basename "$patch_file")"
    else
        error "Failed to revert $(basename "$patch_file")"
        return 1
    fi
}

# Full fresh workflow: update → clean → patch → build
cmd_fresh() {
    echo -e "${BOLD}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║        Fresh Patch + Build Workflow             ║${NC}"
    echo -e "${BOLD}╚══════════════════════════════════════════════════╝${NC}"
    echo ""

    # Step 1: Update nheko submodule to latest upstream
    echo -e "${BOLD}Step 1/5: Update nheko submodule${NC}"
    update_nheko
    echo ""

    # Step 2: Revert any stale patches
    echo -e "${BOLD}Step 2/5: Revert old patches${NC}"
    revert_all_applied
    echo ""

    # Step 3: Select and apply patches
    echo -e "${BOLD}Step 3/5: Select patches to apply${NC}"
    cmd_list
    echo ""
    read -rp "Enter patch prefixes to apply (space-separated, e.g. 0001 0002 0003 0004): " selected
    echo ""

    install_new_files
    local any_failed=false
    for prefix in $selected; do
        if ! cmd_apply "$prefix"; then
            any_failed=true
        fi
    done

    if [[ "$any_failed" == true ]]; then
        echo ""
        error "Some patches failed — aborting build."
        return 1
    fi
    echo ""

    # Step 4: Configure cmake with Hunter
    echo -e "${BOLD}Step 4/5: Configure cmake${NC}"
    clean_build
    cmake_configure
    echo ""

    # Step 5: Build
    echo -e "${BOLD}Step 5/5: Build${NC}"
    if cmake_build; then
        echo ""
        echo -e "${GREEN}${BOLD}✓ Complete! nheko built successfully with all patches.${NC}"
        echo "  Binary: $BUILD_DIR/nheko"
    else
        echo ""
        echo -e "${RED}${BOLD}✗ Build failed.${NC}"
        return 1
    fi
}

# --------------------------------------------------------------------------
# Interactive menu
# --------------------------------------------------------------------------
interactive_menu() {
    while true; do
        clear
        echo -e "${BOLD}╔════════════════════════════════════════════╗${NC}"
        echo -e "${BOLD}║         Nheko Patch Manager               ║${NC}"
        echo -e "${BOLD}╚════════════════════════════════════════════╝${NC}"
        echo ""
        cmd_list
        echo ""
        echo -e "${BOLD}Actions:${NC}"
        echo "  1) Apply all patches (no rebuild)"
        echo "  2) Revert all patches"
        echo "  3) FRESH: update nheko → clean → patch → build"
        echo "  4) Build only (if already patched)"
        echo "  5) Update nheko submodule only"
        echo "  6) List / refresh status"
        echo "  0) Exit"
        echo ""
        read -rp "Select an option [0-6]: " choice

        case "$choice" in
            1)
                cmd_apply "all"
                echo ""
                read -rp "Press Enter to continue..."
                ;;
            2)
                echo ""
                warn "This will revert ALL patches and remove new files."
                read -rp "Are you sure? (y/N): " confirm
                if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
                    cmd_revert "all"
                fi
                echo ""
                read -rp "Press Enter to continue..."
                ;;
            3)
                cmd_fresh || true
                echo ""
                read -rp "Press Enter to continue..."
                ;;
            4)
                echo ""
                if [[ ! -d "$BUILD_DIR" ]]; then
                    cmake_configure
                fi
                cmake_build || true
                echo ""
                read -rp "Press Enter to continue..."
                ;;
            5)
                echo ""
                update_nheko
                echo ""
                read -rp "Press Enter to continue..."
                ;;
            6)
                continue
                ;;
            0)
                echo "Goodbye!"
                exit 0
                ;;
            *)
                warn "Invalid option"
                sleep 1
                ;;
        esac
    done
}

# --------------------------------------------------------------------------
# Main
# --------------------------------------------------------------------------
main() {
    local cmd="${1:-}"
    local arg="${2:-}"

    case "$cmd" in
        list|status)   cmd_list ;;
        apply)         cmd_apply "$arg" ;;
        revert)        cmd_revert "$arg" ;;
        fresh)         cmd_fresh ;;
        update)        update_nheko ;;
        ""|menu|interactive) interactive_menu ;;
        *)
            echo "Usage: $0 {list|apply [all|<prefix>]|revert [all|<prefix>]|fresh|update|menu}"
            exit 1
            ;;
    esac
}

main "$@"
