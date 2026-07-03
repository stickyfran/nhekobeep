# Nheko Patch System

## Project Context

This is a clone of [Nheko-Reborn/nheko](https://github.com/Nheko-Reborn/nheko), a Qt6/QML Matrix client. The source is in the [`nheko/`](nheko/) subdirectory.

We maintain custom patches in [`patches/`](patches/) for:
- **Beeper bridge integration**: Better handling of Beeper's bridged chats (Instagram, WhatsApp, etc. via Beeper)
- **Cache refresh controller**: Force-refresh of profile names and avatars when a Nheko instance was initialized with an old build

## Patch Manager

Use [`patches/patch-manager.sh`](patches/patch-manager.sh) to manage patches:

```bash
# Interactive menu
./patches/patch-manager.sh

# Apply everything needed for the cache refresh feature
./patches/patch-manager.sh apply all

# Check status
./patches/patch-manager.sh list
```

## Patches Index

| # | File | Description | Status |
|---|------|-------------|--------|
| 0001 | [`0001-beeper-bridge-fake-dm-cleanup.patch`](patches/0001-beeper-bridge-fake-dm-cleanup.patch) | Beeper bridge DM detection — fixes room names and avatars for bridged chats (Instagram, WhatsApp, etc.) | Pre-existing |
| 0002 | [`0002-cache-refresh-accessors.patch`](patches/0002-cache-refresh-accessors.patch) | Adds public accessor methods to `Cache` class (`env()`, `roomsDb()`, `openMembersDb()`, `openStatesDb()`, `localUserId()`) and `friend class CacheRefreshController` | New |
| 0003 | [`0003-cache-refresh-cmakelists.patch`](patches/0003-cache-refresh-cmakelists.patch) | Registers new source files in `CMakeLists.txt` (`SRC_FILES` and `QML_SOURCES`) | New |
| 0004 | [`0004-cache-refresh-usersettings.patch`](patches/0004-cache-refresh-usersettings.patch) | Adds "Force Cache Sync" button to settings page and modal progress overlay | New |
| — | [`neochat-beeper-room-avatar.patch`](patches/neochat-beeper-room-avatar.patch) | NeoChat-specific Beeper room avatar handling (not used with Nheko) | Ignored |

## New Files (delivered via `patches/new-files/`)

These files must be **copied** into the source tree (the patch manager script does this automatically):

| Source (`patches/new-files/...`) | Destination (`nheko/...`) | Purpose |
|---|---|---|
| [`src/CacheRefreshController.h`](patches/new-files/src/CacheRefreshController.h) | [`src/CacheRefreshController.h`](nheko/src/CacheRefreshController.h) | QML singleton exposing `startCacheRefresh()` + signals |
| [`src/CacheRefreshController.cpp`](patches/new-files/src/CacheRefreshController.cpp) | [`src/CacheRefreshController.cpp`](nheko/src/CacheRefreshController.cpp) | Background worker: profile fetching, LMDB writes, avatar download, batching |
| [`resources/qml/ui/CacheRefreshOverlay.qml`](patches/new-files/resources/qml/ui/CacheRefreshOverlay.qml) | [`resources/qml/ui/CacheRefreshOverlay.qml`](nheko/resources/qml/ui/CacheRefreshOverlay.qml) | Modal overlay with spinner, progress bar, blocking MouseArea |

## How to Add a New Patch

1. Make your changes in the `nheko/` directory
2. Generate the patch: `cd nheko && git diff -- src/YourFile.cpp > ../patches/0005-description.patch`
3. Register it in [`patches/patch-manager.sh`](patches/patch-manager.sh) by adding an entry to the `PATCHES` array
4. If you created new files, place them in `patches/new-files/` with the correct relative path and add an entry to the `NEW_FILES` array

## Build Script

The original build script (referenced as `sh` that does pull, patch, and build) likely does:
```bash
cd nheko
git pull
# Apply patches
git apply ../patches/0001-beeper-bridge-fake-dm-cleanup.patch
# Copy new files
cp -r ../patches/new-files/* ./
# Build
cmake -S. -Bbuild -DCMAKE_BUILD_TYPE=Release
cmake --build build
```

## Architecture: CacheRefreshController

### C++ Backend

- **Class**: [`CacheRefreshController`](nheko/src/CacheRefreshController.h) — QML singleton (`QML_ELEMENT` + `QML_SINGLETON`)
- **Threading**: Worker object moved to a dedicated `QThread`; uses `QAtomicInt` for cancellation
- **Batching**: Processes 50 rooms per batch with 200ms delay between batches
- **Rate limiting**: Exponential backoff on HTTP 429 (200ms → 400ms → 800ms)
- **LMDB strategy**: Accumulates member profile updates in memory, flushes in a single LMDB write transaction per batch
- **Beeper priority**: Beeper bridge rooms (3-member rooms with `@*bot*:beeper.*` pattern) are sorted first

### QML Frontend

- **Button**: Prominent "Force Cache Sync" button at the top of [`UserSettingsPage.qml`](nheko/resources/qml/pages/UserSettingsPage.qml)
- **Overlay**: [`CacheRefreshOverlay.qml`](nheko/resources/qml/ui/CacheRefreshOverlay.qml) — full-screen semi-transparent overlay with:
  - `BusyIndicator` (spinner)
  - `ProgressBar` (bound to `progressUpdated` signal)
  - Status text ("Updating cache and downloading avatars...")
  - Blocking `MouseArea` to prevent interaction during refresh

### Key Signals

| Signal | Arguments | When |
|--------|-----------|------|
| `refreshStarted()` | — | Worker thread started |
| `progressUpdated(int current, int total)` | current, total | After each room processed |
| `refreshFinished(bool success, QString message)` | success, message | All rooms done or error |
