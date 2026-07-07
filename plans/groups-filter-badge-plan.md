# Groups Filter Badge — Implementation Plan

## Objective

Add a smart "Groups" filter badge to Nheko's left sidebar (driven by CommunitiesModel), similar to how standard tags like "Low Priority" or "Favourites" are displayed. Clicking "Groups" filters the room list to show only rooms that are **not** direct chats (1:1s), including correctly excluding Beeper bridged DMs (3-member rooms with a bridge bot).

## Design Decisions

### Approach: Synthetic tag injection

Instead of adding a hardcoded row to CommunitiesModel (which would require updating many offset/index calculations), we inject `"virtual:groups"` into the `tags_` list in `initializeSidebar()`. This is less invasive because:

- `rowCount()` already accounts for `tags_.size()` — no change needed
- The tag is handled specially in `data()` with dedicated icon, name and tooltip
- The `FilteredCommunitiesModel::lessThan()` sort order gets a new `Groups` category (between Favourites and Server Notices)

### Filtering logic

When the user clicks "Groups", `setCurrentTagId("tag:virtual:groups")` is called, which flows to `FilteredRoomlistModel::updateFilterTag("tag:virtual:groups")`, setting `filterType = FilterBy::Tag` and `filterStr = "virtual:groups"`.

In `filterAcceptsRow()`, we intercept this special tag: instead of checking if the room has a tag called "virtual:groups" (no room does), we accept rooms where `IsDirect == false`.

### Beeper bridge DM detection

The unified patch (0000-unified-nhekobeep.patch) already introduces:
- `BeeperNetworkInfo` struct with `counterpartMxid`
- `networkCache` (`QHash<QString, BeeperNetworkInfo>`) on `RoomlistModel`
- `updateNetworkCache()` / `rebuildNetworkCache()` which detects 3-member rooms with a `beeper.*` bridge bot

We extend the `IsDirect` role in `RoomlistModel::data()`: after checking `directChatToUser`, we also consult `networkCache`. If a room's network cache entry has a non-empty `counterpartMxid`, it's treated as a direct chat. This covers Beeper fake DMs that haven't yet been added to `m.direct` account data.

## Files Modified

| File | Changes |
|------|---------|
| `src/timeline/CommunitiesModel.h` | `tags()` and `tagsWithDefault()` filter out `"virtual:groups"` from public tag lists |
| `src/timeline/CommunitiesModel.cpp` | Inject into `tags_` in `initializeSidebar()`; handle in `data()` with icon/name/tooltip; add `Groups` category to sort order |
| `src/timeline/RoomlistModel.cpp` | Extend `IsDirect` to consult `networkCache`; intercept `"virtual:groups"` in `filterAcceptsRow()` to show only non-DM rooms |

## Patch File

`patches/0011-groups-filter-badge.patch` — unified diff against pristine nheko master.

## Dependencies

- The CommunitiesModel changes are self-contained and apply to pristine nheko.
- The RoomlistModel `networkCache`-based IsDirect fallback requires the unified patch (0000) which introduces `updateNetworkCache()` / `rebuildNetworkCache()`. Without it, standard `m.direct` DMs are still correctly excluded, but Beeper 3-member bridge DMs that aren't yet in `m.direct` may leak into the Groups view.
