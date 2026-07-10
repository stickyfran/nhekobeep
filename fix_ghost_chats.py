import re

with open("nheko/src/timeline/RoomlistModel.cpp", "r") as f:
    c = f.read()

start = c.find("FilteredRoomlistModel::filterAcceptsRow(int sourceRow, const QModelIndex &) const\n{")
if start != -1:
    body_start = start + len("FilteredRoomlistModel::filterAcceptsRow(int sourceRow, const QModelIndex &) const\n{")
    
    new_code = """
    auto idx = sourceModel()->index(sourceRow, 0);

    // Hide Beeper ghost chats (bridged rooms with no real messages)
    bool isBeeper = !sourceModel()->data(idx, RoomlistModel::BeeperNetworkRole).toString().isEmpty();
    if (isBeeper && !sourceModel()->data(idx, RoomlistModel::IsInvite).toBool()) {
        bool hasMessages = sourceModel()->data(idx, RoomlistModel::Timestamp).toULongLong() > 0;
        if (!hasMessages) {
            return false;
        }
    }
"""
    c = c[:body_start] + new_code + c[body_start:]

with open("nheko/src/timeline/RoomlistModel.cpp", "w") as f:
    f.write(c)
