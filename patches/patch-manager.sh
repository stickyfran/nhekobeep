#!/usr/bin/env bash
# ============================================================================
# Nheko Patch Manager
# ============================================================================
# Usage:
#   ./patches/patch-manager.sh              # Interactive menu
#   ./patches/patch-manager.sh list         # List patches and their status
#   ./patches/patch-manager.sh apply all    # Apply all patches
#   ./patches/patch-manager.sh apply 0001   # Apply a specific patch by prefix
#   ./patches/patch-manager.sh revert all   # Revert all patches
#   ./patches/patch-manager.sh revert 0002  # Revert a specific patch
#
# To add a new patch:
#   1. Generate your patch file with: git format-patch -1
#   2. Place it in patches/ with a descriptive name like 0005-my-feature.patch
#   3. Add a description entry in the PATCHES array below
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
NEW_FILES_DIR="$SCRIPT_DIR/new-files"

# --------------------------------------------------------------------------
# Patch registry
# Format: prefix|"Description"|"New file dest mappings (optional)"
#   prefix: used to match patch files starting with this prefix
#   description: shown in the menu
#   new-files: optional semicolon-separated list of src=dest for new files
# --------------------------------------------------------------------------
PATCHES=(
    "0001|Beeper bridge fake-DM cleanup (room names & avatars)"
    "0002|Cache refresh controller — LMDB accessors (Cache.cpp, Cache_p.h)"
    "0003|Cache refresh controller — CMakeLists.txt source list"
    "0004|Cache refresh controller — UserSettingsPage.qml button & overlay"
)

# --------------------------------------------------------------------------
# New files to install (from patches/new-files/ into the repository)
# Format: src_relpath (relative to new-files/) = dest_relpath (relative to repo)
# --------------------------------------------------------------------------
NEW_FILES=(
    "src/CacheRefreshController.h = src/CacheRefreshController.h"
    "src/CacheRefreshController.cpp = src/CacheRefreshController.cpp"
    "resources/qml/ui/CacheRefreshOverlay.qml = resources/qml/ui/CacheRefreshOverlay.qml"
)

# --------------------------------------------------------------------------
# Color helpers
# --------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }

# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------

# Find patch file by prefix
find_patch() {
    local prefix="$1"
    # Try exact filename first
    if [[ -f "$SCRIPT_DIR/$prefix" ]]; then
        echo "$SCRIPT_DIR/$prefix"
        return 0
    fi
    # Try prefix match
    local matches=()
    while IFS= read -r -d '' f; do
        matches+=("$f")
    done < <(find "$SCRIPT_DIR" -maxdepth 1 -name "${prefix}*.patch" -print0 2>/dev/null || true)

    if [[ ${#matches[@]} -eq 0 ]]; then
        return 1
    fi
    echo "${matches[0]}"
}

# Check if a patch is applied (dry-run)
is_applied() {
    local patch_file="$1"
    if git apply --check "$patch_file" --reverse 2>/dev/null; then
        return 0  # Already applied (reverse check succeeds = patch was applied)
    else
        return 1  # Not applied
    fi
}

# Check if new files are installed
new_files_installed() {
    for entry in "${NEW_FILES[@]}"; do
        local src="${entry%%=*}"
        src="$(echo "$src" | xargs)"  # trim
        local dest="${entry##*=}"
        dest="$(echo "$dest" | xargs)"  # trim
        if [[ ! -f "$REPO_DIR/$dest" ]]; then
            return 1
        fi
    done
    return 0
}

# Install new files
install_new_files() {
    info "Installing new files..."
    for entry in "${NEW_FILES[@]}"; do
        local src="${entry%%=*}"
        src="$(echo "$src" | xargs)"
        local dest="${entry##*=}"
        dest="$(echo "$dest" | xargs)"

        local src_path="$NEW_FILES_DIR/$src"
        local dest_path="$REPO_DIR/$dest"

        if [[ ! -f "$src_path" ]]; then
            warn "Source not found: $src_path — skipping"
            continue
        fi

        mkdir -p "$(dirname "$dest_path")"
        cp "$src_path" "$dest_path"
        ok "Installed $dest"
    done
}

# Remove new files
remove_new_files() {
    info "Removing new files..."
    for entry in "${NEW_FILES[@]}"; do
        local dest="${entry##*=}"
        dest="$(echo "$dest" | xargs)"
        local dest_path="$REPO_DIR/$dest"

        if [[ -f "$dest_path" ]]; then
            rm "$dest_path"
            ok "Removed $dest"
        fi
    done
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
        # Install new files first
        install_new_files

        # Apply each patch in order
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
    cd "$REPO_DIR"

    # Strip CRLF if present (patches created on Windows may have \r\n)
    local clean_patch="$patch_file.clean"
    if grep -q $'\r' "$patch_file" 2>/dev/null; then
        warn "Detected CRLF in patch — converting to LF..."
        tr -d '\r' < "$patch_file" > "$clean_patch"
    else
        cp "$patch_file" "$clean_patch"
    fi

    local apply_output
    apply_output=$(git apply --verbose "$clean_patch" 2>&1) || true
    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        ok "Applied $(basename "$patch_file")"
        rm -f "$clean_patch"
    else
        error "Failed to apply $(basename "$patch_file") (exit code: $exit_code)"
        echo ""
        echo -e "${YELLOW}--- git apply output: ---${NC}"
        echo "$apply_output"
        echo -e "${YELLOW}-------------------------${NC}"
        echo ""

        local check_output
        check_output=$(git apply --check "$clean_patch" 2>&1) || true
        echo -e "${RED}--- git apply --check output: ---${NC}"
        echo "$check_output"
        echo -e "${RED}----------------------------------${NC}"
        echo ""

        echo -e "${BLUE}Debug:${NC}"
        echo "  File: $(basename "$patch_file") ($(wc -c < "$patch_file") bytes)"
        echo "  PWD: $(pwd)"
        echo "  CRLF lines: $(grep -c $'\r' "$patch_file" 2>/dev/null || echo 0)"
        echo "  First hunk header: $(grep '^@@' "$patch_file" | head -1)"

        rm -f "$clean_patch"
        return 1
    fi
}

cmd_revert() {
    local target="${1:-}"

    if [[ "$target" == "all" ]]; then
        # Revert patches in reverse order
        for ((idx = ${#PATCHES[@]} - 1; idx >= 0; idx--)); do
            local prefix="${PATCHES[$idx]%%|*}"
            cmd_revert "$prefix"
        done

        # Remove new files
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
        warn "Patch '$(basename "$patch_file")' is not applied — nothing to revert."
        return 0
    fi

    info "Reverting $(basename "$patch_file")..."
    cd "$REPO_DIR"
    if git apply --reverse "$patch_file"; then
        ok "Reverted $(basename "$patch_file")"
    else
        error "Failed to revert $(basename "$patch_file")"
        return 1
    fi
}

# --------------------------------------------------------------------------
# Interactive menu
# --------------------------------------------------------------------------
interactive_menu() {
    # Build config directory
    local BUILD_DIR="${REPO_DIR}/build"

    while true; do
        clear
        echo -e "${BOLD}╔════════════════════════════════════════════╗${NC}"
        echo -e "${BOLD}║         Nheko Patch Manager               ║${NC}"
        echo -e "${BOLD}╚════════════════════════════════════════════╝${NC}"
        echo ""
        cmd_list
        echo ""
        echo -e "${BOLD}Actions:${NC}"
        echo "  1) Apply all patches"
        echo "  2) Revert all patches"
        echo "  3) Apply selected patches + Build"
        echo "  4) Build only (if already patched)"
        echo "  5) List / refresh status"
        echo "  0) Exit"
        echo ""
        read -rp "Select an option [0-5]: " choice

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
                echo ""
                echo -e "${BOLD}Select patches to include (space-separated list, e.g.: 0001 0002 0004)${NC}"
                echo -e "  Available:"
                for entry in "${PATCHES[@]}"; do
                    local prefix="${entry%%|*}"
                    local desc="${entry#*|}"
                    local applied=""
                    local patch_file
                    patch_file="$(find_patch "$prefix" 2>/dev/null || true)"
                    if [[ -n "$patch_file" ]] && is_applied "$patch_file" 2>/dev/null; then
                        applied=" ${GREEN}[already applied]${NC}"
                    fi
                    echo -e "    ${prefix} — ${desc}${applied}"
                done
                echo ""
                read -rp "Enter prefixes (e.g. 0001 0003 0004): " selected
                echo ""

                # Install new files if any selected patch needs them
                install_new_files

                local any_failed=false
                for prefix in $selected; do
                    if ! cmd_apply "$prefix"; then
                        any_failed=true
                    fi
                done

                if [[ "$any_failed" == false ]]; then
                    echo ""
                    echo -e "${GREEN}Patches applied successfully.${NC}"
                    echo ""
                    echo -e "${BOLD}Starting build...${NC}"
                    echo ""

                    cd "$REPO_DIR"
                    if [[ ! -d "$BUILD_DIR" ]]; then
                        echo "Creating build directory..."
                        cmake -S"${REPO_DIR}/nheko" -B"$BUILD_DIR" -DCMAKE_BUILD_TYPE=Release
                    fi

                    cmake --build "$BUILD_DIR" -- -j"$(nproc 2>/dev/null || echo 4)"
                    local build_exit=$?

                    echo ""
                    if [[ $build_exit -eq 0 ]]; then
                        echo -e "${GREEN}Build completed successfully!${NC}"
                    else
                        echo -e "${RED}Build failed (exit code: $build_exit).${NC}"
                    fi
                else
                    echo ""
                    echo -e "${YELLOW}Some patches failed — skipping build.${NC}"
                fi

                echo ""
                read -rp "Press Enter to continue..."
                ;;
            4)
                echo ""
                cd "$REPO_DIR"
                if [[ ! -d "$BUILD_DIR" ]]; then
                    echo "Creating build directory..."
                    cmake -S"${REPO_DIR}/nheko" -B"$BUILD_DIR" -DCMAKE_BUILD_TYPE=Release
                fi
                cmake --build "$BUILD_DIR" -- -j"$(nproc 2>/dev/null || echo 4)"
                local build_exit=$?
                if [[ $build_exit -eq 0 ]]; then
                    echo -e "${GREEN}Build completed successfully!${NC}"
                else
                    echo -e "${RED}Build failed (exit code: $build_exit).${NC}"
                fi
                echo ""
                read -rp "Press Enter to continue..."
                ;;
            5)
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
        list|status)
            cmd_list
            ;;
        apply)
            cmd_apply "$arg"
            ;;
        revert)
            cmd_revert "$arg"
            ;;
        ""|menu|interactive)
            interactive_menu
            ;;
        *)
            echo "Usage: $0 {list|apply [all|<prefix>]|revert [all|<prefix>]|menu}"
            exit 1
            ;;
    esac
}

main "$@"
