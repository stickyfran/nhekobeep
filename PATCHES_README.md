# Nheko Patch System — nhekobeep

## Project Structure

```
nhekobeep/
├── nheko/                      # Submodule → Nheko-Reborn/nheko
├── patches/
│   ├── 0000-unified-nhekobeep.patch  # Single unified patch (all changes)
│   ├── patch-manager.sh        # One-shot build script
│   ├── new-files/              # New source files
│   └── archive/                # Previous individual patches (reference)
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
3. Apply unified patch + copy new files
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

## Unified Patch System

All changes are consolidated into a **single** patch file to avoid overlay errors:

| Patch | Description | Modified Files |
|-------|-------------|----------------|
| `0000-unified-nhekobeep.patch` | All Beeper integration + scroll perf + custom labels | 16 files (see below) |

### What's included:

| Source File | Features |
|-------------|----------|
| `CMakeLists.txt` | Registers all new source + QML files |
| `src/Cache.cpp` | Beeper fake DM detection + cache accessors (`env()`, `roomsDb()`, etc.) |
| `src/Cache_p.h` | `friend CacheRefreshController`, `friend BeeperReinitWorker`, accessor declarations |
| `src/ChatPage.h` | `friend class BeeperReinitController` |
| `src/UserSettingsPage.h` | `CustomLabel` struct, `CustomLabelListModel` class, settings methods |
| `src/UserSettingsPage.cpp` | Custom label persistence + `CustomLabelListModel` implementation |
| `src/timeline/RoomlistModel.h` | `BeeperNetworkRole`, `BeeperNetworkColorRole`, `networkCache` |
| `src/timeline/RoomlistModel.cpp` | MXID-based network detection, prewarm, network cache |
| `src/timeline/CommunitiesModel.cpp` | Custom label name/icon overrides in tag rendering |
| `src/AvatarProvider.h/.cpp` | `prewarm()` function for avatar cache |
| `resources/qml/RoomList.qml` | Brand-color badge + `reuseItems`/`cacheBuffer` + custom labels sub-menu |
| `resources/qml/pages/UserSettingsPage.qml` | Force Cache Sync + Beeper Reinit + Custom Labels UI |
| `resources/qml/Avatar.qml` | `effectivePixelSize` + opacity animations |
| `src/MxcImageProvider.cpp` | WebP storage format |
| `src/main.cpp` | `QPixmapCache` increased to 50 MB |

### New files (copied separately):
| File | Description |
|------|-------------|
| `src/CacheRefreshController.h/.cpp` | Background worker: profile fetching, LMDB writes, avatar download |
| `src/BeeperBridge.h` | Bridge detection helpers |
| `src/BeeperReinitController.h/.cpp` | Full cache re-init controller |
| `resources/qml/ui/CacheRefreshOverlay.qml` | Cache refresh modal overlay |
| `resources/qml/ui/BeeperReinitOverlay.qml` | Re-init modal overlay |

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

## Adding Changes

**Important:** Always work from the unified patch to avoid overlay errors.

1. Make changes directly in `nheko/` source files
2. Regenerate the unified patch:
   ```bash
   git -C nheko diff HEAD -- \
     CMakeLists.txt \
     resources/qml/Avatar.qml \
     resources/qml/RoomList.qml \
     resources/qml/pages/UserSettingsPage.qml \
     src/AvatarProvider.cpp \
     src/AvatarProvider.h \
     src/Cache.cpp \
     src/Cache_p.h \
     src/ChatPage.h \
     src/MxcImageProvider.cpp \
     src/UserSettingsPage.cpp \
     src/UserSettingsPage.h \
     src/main.cpp \
     src/timeline/CommunitiesModel.cpp \
     src/timeline/RoomlistModel.cpp \
     src/timeline/RoomlistModel.h \
     > patches/0000-unified-nhekobeep.patch
   ```
3. If you added new files:
   - Add to `NEW_FILES` array in `patch-manager.sh`
   - Place files in `patches/new-files/`
   - Add to `CMakeLists.txt` changes in the unified patch

## Superseded Patches

Previous individual patches are archived in `patches/archive/` for reference:
- `0001` through `0011`: Individual patches (replaced by unified patch)
- `neochat-beeper-room-avatar.patch`: Reference only (NeoChat-based, not used)
