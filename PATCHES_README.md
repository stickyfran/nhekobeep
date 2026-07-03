# Nheko Patch System — nhekobeep

## Project Structure

```
nhekobeep/
├── nheko/                      # Submodule → Nheko-Reborn/nheko
├── patches/
│   ├── 0001-beeper-bridge-fake-dm-cleanup.patch
│   ├── 0002-cache-refresh-accessors.patch
│   ├── 0003-cache-refresh-cmakelists.patch
│   ├── patch-manager.sh        # One-shot build script
│   └── new-files/              # New source files
├── PATCHES_README.md
└── plans/
```

## Quick Start

```bash
git clone --recurse-submodules https://github.com/stickyfran/nhekobeep.git
cd nhekobeep
./patches/patch-manager.sh
```

This will:
1. Update `nheko/` submodule to latest upstream
2. Clean old build directory
3. Apply all patches + new files
4. Configure cmake
5. Build

## Build Dependencies (Arch Linux)

These errors appeared during build — each with its fix:

### `fatal error: lmdb++.h: No existe el fichero o el directorio`

**Cause**: `lmdb++` (the C++ bindings for LMDB) is not installed.

**Fix (Arch)**:
```bash
yay -S lmdbxx
# or from AUR manually:
git clone https://aur.archlinux.org/lmdbxx.git
cd lmdbxx && makepkg -si
```

### `'Creator' is not a member of 'mtx::events::state'`
### `'StateEvent' in namespace 'mtx::events' does not name a template type`
### `'user_level()' expects 1 argument, 2 provided`

**Cause**: The system `mtxclient` library version installed via pacman is too new/incompatible with this nheko commit (`b13a0c8`). The mtxclient API changed between versions.

**Fix**: Force cmake to use the bundled mtxclient:
```bash
cmake -S nheko -B build \
  -DCMAKE_BUILD_TYPE=Release \
  -DHUNTER_ENABLED=ON \
  -DUSE_BUNDLED_MTXCLIENT=ON \
  -DUSE_BUNDLED_LMDB=ON \
  -DUSE_BUNDLED_LMDBXX=ON \
  -DUSE_BUNDLED_SPDLOG=ON \
  -DUSE_BUNDLED_FMT=ON
```

If Hunter fails with `Unexpected empty string`:
```bash
rm -rf ~/.hunter build
# Then retry the cmake command above
```

### `fatal error: 'nlohmann/json.hpp' not found`

**Fix**:
```bash
sudo pacman -S nlohmann-json
```

### `fatal error: 'spdlog/spdlog.h' not found`

**Fix**:
```bash
sudo pacman -S spdlog
```

### All required system packages (Arch)

```bash
sudo pacman -S \
  qt6-base qt6-declarative qt6-svg qt6-multimedia \
  lmdb cmake ninja gcc \
  spdlog fmt nlohmann-json \
  cmark libolm \
  qt6-keychain \
  libevent libcurl \
  gstreamer gst-plugins-base \
  openssl
```

## Patch Index

| # | File | Description |
|---|------|-------------|
| 0001 | `0001-beeper-bridge-fake-dm-cleanup.patch` | Beeper bridge DM detection — fixes room names/avatars for bridged chats (Instagram, WhatsApp, etc.). Applied via `git apply` to `Cache.cpp`. |
| 0002 | `0002-cache-refresh-accessors.patch` | Adds public accessor methods to `Cache` class (`env()`, `roomsDb()`, `openMembersDb()`, `openStatesDb()`, `localUserId()`) + `friend class CacheRefreshController`. Applied to `Cache.cpp` and `Cache_p.h`. |
| 0003 | `0003-cache-refresh-cmakelists.patch` | Registers `CacheRefreshController.cpp/.h` and `CacheRefreshOverlay.qml` in `CMakeLists.txt`. |
| — | (QML changes via `sed` in patch-manager.sh) | The 0004 patch was corrupt (Windows CRLF), so `patch-manager.sh` applies UserSettingsPage changes directly with `sed`. |
| — | `new-files/src/CacheRefreshController.h` | QML singleton exposing `startCacheRefresh()` + signals. |
| — | `new-files/src/CacheRefreshController.cpp` | Background worker: profile fetching, LMDB writes, avatar download, batching. |
| — | `new-files/resources/qml/ui/CacheRefreshOverlay.qml` | Modal overlay: spinner, progress bar, blocking MouseArea. |

## CacheRefreshController Architecture

```
QML Button → CacheRefreshController::startCacheRefresh()
                ↓
          [QThread Worker]
                ↓
    1. Read all rooms from LMDB, sort by activity
    2. Detect Beeper bridge rooms (3 members, @*bot*:beeper.*)
    3. Process top 1000 rooms in batches of 50
    4. Per batch: fetch profiles (HTTP), update LMDB, download avatars
    5. 200ms delay between batches to avoid rate limiting
                ↓
          Signals: progressUpdated(current, total)
                   refreshFinished(success, message)
```

## Adding New Patches

1. Make changes in `nheko/`
2. Generate patch: `cd nheko && git diff -- src/YourFile.cpp > ../patches/0005-desc.patch`
3. Register in `patch-manager.sh` under `PATCH_FILES` array
4. If new files: add to `NEW_FILES` array and place in `patches/new-files/`
