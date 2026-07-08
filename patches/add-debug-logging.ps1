# Read the patch file
$patch = [System.IO.File]::ReadAllText('patches/0000-unified-nhekobeep.patch')
"Original patch size: " + $patch.Length

# === 1. updateNetworkCache: add logging after getMembers ===
$old1 = "+        auto members = cache::client()->getMembers(roomid.toStdString());`r`n+`r`n+        for (const auto &m : members) {"
$new1 = "+        auto members = cache::client()->getMembers(roomid.toStdString());`r`n+`r`n+        nhlog::ui()->debug(`"[BEEPER-DEBUG] updateNetworkCache roomid={} members.size={}`",`r`n+                           roomid.toStdString(), members.size());`r`n+`r`n+        for (const auto &m : members) {"
$patch = $patch -replace [regex]::Escape($old1), $new1
"Step 1 done: updateNetworkCache member logging"

# === 2. updateNetworkCache: logging before isBeeperBridge check ===
$old2 = "+        }`r`n+    }`r`n+`r`n+    if (isBeeperBridge) {`r`n+        if (activeMembers > 2) {"
$new2 = "+        }`r`n+    }`r`n+`r`n+    nhlog::ui()->debug(`"[BEEPER-DEBUG] updateNetworkCache roomid={} isBeeperBridge={} activeMembers={} counterpart={}`",`r`n+                       roomid.toStdString(), isBeeperBridge, activeMembers, counterpart.toStdString());`r`n+`r`n+    if (isBeeperBridge) {`r`n+        if (activeMembers > 2) {`r`n+            nhlog::ui()->debug(`"[BEEPER-DEBUG] updateNetworkCache roomid={} CLASSIFIED=Group activeMembers={}`",`r`n+                               roomid.toStdString(), activeMembers);"
$patch = $patch -replace [regex]::Escape($old2), $new2
"Step 2 done: updateNetworkCache classification logging"

# === 3. updateNetworkCache: DM branch logging ===
$old3 = "+        } else {`r`n+            // 1:1 DM  (local user + bot + 1 real contact = total <= 3)"
$new3 = "+        } else {`r`n+            nhlog::ui()->debug(`"[BEEPER-DEBUG] updateNetworkCache roomid={} CLASSIFIED=DM activeMembers={}`",`r`n+                               roomid.toStdString(), activeMembers);`r`n+            // 1:1 DM  (local user + bot + 1 real contact = total <= 3)"
$patch = $patch -replace [regex]::Escape($old3), $new3
"Step 3 done: updateNetworkCache DM logging"

# === 4. updateNetworkCache: FALLBACK_DM and NO_BRIDGE logging ===
$old4 = "+        networkCache.insert(roomid, {info.name, info.color, userId, 1});`r`n+        return;`r`n+    }`r`n+`r`n+    // No bridge detected`r`n+    networkCache.insert(roomid, {QString(), QColor(), QString(), 0});"
$new4 = "+        nhlog::ui()->debug(`"[BEEPER-DEBUG] updateNetworkCache roomid={} FALLBACK_DM nativeMatrix=true`",`r`n+                           roomid.toStdString());`r`n+        networkCache.insert(roomid, {info.name, info.color, userId, 1});`r`n+        return;`r`n+    }`r`n+`r`n+    // No bridge detected`r`n+    nhlog::ui()->debug(`"[BEEPER-DEBUG] updateNetworkCache roomid={} NO_BRIDGE`",`r`n+                       roomid.toStdString());`r`n+    networkCache.insert(roomid, {QString(), QColor(), QString(), 0});"
$patch = $patch -replace [regex]::Escape($old4), $new4
"Step 4 done: updateNetworkCache fallback logging"

# === 5. filterAcceptsRow VirtualUnread logging ===
$old5 = "+        return hasUnread || notifCount > 0 || msgCount > 0;`r`n+    } else if (filterType == FilterBy::VirtualGroups) {"
$new5 = "+        nhlog::ui()->debug(`"[BEEPER-DEBUG] filterAcceptsRow VirtualUnread sourceRow={} hasUnread={} notifCount={} msgCount={} ACCEPT={}`",`r`n+                           sourceRow, hasUnread, notifCount, msgCount,`r`n+                           (hasUnread || notifCount > 0 || msgCount > 0));`r`n+`r`n+        return hasUnread || notifCount > 0 || msgCount > 0;`r`n+    } else if (filterType == FilterBy::VirtualGroups) {"
$patch = $patch -replace [regex]::Escape($old5), $new5
"Step 5 done: filterAcceptsRow VirtualUnread logging"

# === 6. filterAcceptsRow VirtualGroups logging ===
$old6 = "+        return !sourceModel()->data(idx, RoomlistModel::IsDirect).toBool();`r`n      } else {`r`n          return true;`r`n      }"
$new6 = "+        const bool isDirect =`r`n+          sourceModel()->data(idx, RoomlistModel::IsDirect).toBool();`r`n+`r`n+        nhlog::ui()->debug(`"[BEEPER-DEBUG] filterAcceptsRow VirtualGroups sourceRow={} IsDirect={} ACCEPT={}`",`r`n+                           sourceRow, isDirect, !isDirect);`r`n+`r`n+        return !isDirect;`r`n      } else {`r`n          return true;`r`n      }"
$patch = $patch -replace [regex]::Escape($old6), $new6
"Step 6 done: filterAcceptsRow VirtualGroups logging"

# === 7. CommunitiesList.qml: Edit Label MenuItem logging ===
$old7 = "+                visible: CustomLabelListModel.displayNameForTag(pureTag) !== `"`" || pureTag.startsWith(`"u.`")"
$new7 = "+                visible: {`r`n+                    var displayName = CustomLabelListModel.displayNameForTag(pureTag);`r`n+                    var rc = (typeof CustomLabelListModel.rowCount === 'function') ? CustomLabelListModel.rowCount() : -1;`r`n+                    console.log(`"[BEEPER-DEBUG] EditLabel visibilityCheck tagId=`" + communityContextMenu.tagId + `" pureTag=`" + pureTag + `" displayNameForTag='`" + displayName + `"' startsWithU=`" + pureTag.startsWith(`"u.`") + `" rowCount=`" + rc);`r`n+                    return displayName !== `"`" || pureTag.startsWith(`"u.`");`r`n+                }"
$patch = $patch -replace [regex]::Escape($old7), $new7
"Step 7 done: CommunitiesList Edit Label visibility logging"

# === 8. CommunitiesList.qml: Edit Label onTriggered logging ===
$old8 = "+                onTriggered: {`r`n+                    var dialog = editCustomLabelComponent.createObject(communitySidebar, {"
$new8 = "+                onTriggered: {`r`n+                    console.log(`"[BEEPER-DEBUG] EditLabel triggered tagId=`" + communityContextMenu.tagId + `" pureTag=`" + pureTag);`r`n+                    var dialog = editCustomLabelComponent.createObject(communitySidebar, {"
$patch = $patch -replace [regex]::Escape($old8), $new8
"Step 8 done: CommunitiesList Edit Label onTriggered logging"

# === 9. CommunitiesList.qml: show function logging ===
# Add new hunk before the existing CommunitiesList.qml hunk
# The existing hunk starts with "diff --git a/resources/qml/CommunitiesList.qml b/resources/qml/CommunitiesList.qml"
# We insert a new hunk BEFORE it that modifies the show function
$menuHunk = "diff --git a/resources/qml/CommunitiesList.qml b/resources/qml/CommunitiesList.qml`r`nindex a134474..5c24197 100644`r`n--- a/resources/qml/CommunitiesList.qml`r`n+++ b/resources/qml/CommunitiesList.qml`r`n@@ -202,6 +202,7 @@`r`n             property string tagId`r`n `r`n             function show(parent, id_, hidden_, muted_) {`r`n+                console.log(`"[BEEPER-DEBUG] Context menu opened tagId=`" + id_ + `" hidden=`" + hidden_ + `" muted=`" + muted_);`r`n                 tagId = id_;`r`n                 hidden = hidden_;`r`n                 muted = muted_;"
$patch = $patch -replace [regex]::Escape("diff --git a/resources/qml/CommunitiesList.qml b/resources/qml/CommunitiesList.qml`r`nindex a134474..5c24197 100644`r`n--- a/resources/qml/CommunitiesList.qml`r`n+++ b/resources/qml/CommunitiesList.qml"), $menuHunk
"Step 9 done: CommunitiesList show function logging"

"Final patch size: " + $patch.Length

[System.IO.File]::WriteAllText('patches/0000-unified-nhekobeep.patch', $patch, [System.Text.UTF8Encoding]::new($false))

"Done! Verifying..."
Select-String -Path patches/0000-unified-nhekobeep.patch -Pattern 'BEEPER-DEBUG' -SimpleMatch | ForEach-Object { $_.LineNumber.ToString() + ': ' + $_.Line.Trim() }
