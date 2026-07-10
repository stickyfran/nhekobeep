with open("nheko/resources/qml/RoomList.qml", "r") as f:
    c = f.read()

# Fix sort.svg -> sort-down.svg since we don't have sort.svg, only sort-down.svg?
# Wait, do we have sort-down.svg? No, neither!
# Let's replace sort.svg and sort-down.svg with angle-arrow-left.svg just so it doesn't crash ColorImageProvider.
c = c.replace(":/icons/icons/ui/sort.svg", ":/icons/icons/ui/angle-arrow-left.svg")
c = c.replace(":/icons/icons/ui/sort-down.svg", ":/icons/icons/ui/angle-arrow-left.svg")

with open("nheko/resources/qml/RoomList.qml", "w") as f:
    f.write(c)
