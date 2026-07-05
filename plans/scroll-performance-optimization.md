# Scroll Performance Optimization Plan

> **STATUS: 🚧 IN PROGRESS** — Implementing quick wins first

## Root Cause Analysis

### #1: `reuseItems: true` commented out in RoomList.qml:445
Without delegate reuse, QML destroys and recreates every delegate on scroll, causing avatar re-loads and flicker.

### #2: PNG disk cache in MxcImageProvider.cpp:282
All cached thumbnails saved as PNG (lossless). WebP would be 2-5× smaller for photo-like avatars.

### #3: QPixmapCache default limit too small (~10 MB)
No `QPixmapCache::setCacheLimit()` call found anywhere. 200 avatars @ 128×128 RGBA ≈ 13 MB.

### #4: No pre-fetching during scroll
Avatars load reactively — no look-ahead for items about to become visible.

## Implementation Order

### Phase 1: Quick Wins (Highest Impact)
1. Enable `reuseItems: true` in RoomList.qml:445
2. Switch disk cache format from PNG to WebP in MxcImageProvider.cpp:282
3. Increase QPixmapCache limit to 50 MB in main.cpp

### Phase 2: Scroll Experience
4. Add pre-fetching (look-ahead) for avatars in scroll direction via RoomList
5. Cross-fade transition in Avatar.qml (blurhash/identicon → real image)
6. Cache sourceSize in Avatar.qml to avoid recalculations

### Phase 3: Startup Pre-warming
7. Integrate CacheRefreshController to pre-load top rooms' avatars on login
8. LRU in-memory cache for most frequently accessed avatars

## RAM Cost Estimate
- 200 rooms × 64×64 × DPR 2.0 (128×128) × 4 bytes RGBA ≈ 13 MB VRAM
- With 50 MB QPixmapCache: room for ~750 avatars
- Trade-off: negligible on any modern machine

## Files Modified
| File | Change |
|------|--------|
| `nheko/resources/qml/RoomList.qml` | Enable reuseItems, add pre-fetch logic |
| `nheko/src/MxcImageProvider.cpp` | PNG → WebP for disk cache |
| `nheko/src/main.cpp` | Increase QPixmapCache limit |
| `nheko/src/AvatarProvider.cpp` | Size-aware cache eviction |
| `nheko/resources/qml/Avatar.qml` | Cross-fade, blurhash placeholder |
| `nheko/src/timeline/RoomlistModel.h` | Pre-fetch API |
| `nheko/src/timeline/RoomlistModel.cpp` | Pre-fetch implementation |
