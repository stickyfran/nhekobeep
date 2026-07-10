with open("nheko/resources/qml/CommunitiesList.qml", "r") as f:
    c = f.read()

# 1. Fix ReferenceError for isEmojiIcon
c = c.replace("visible: isEmojiIcon", "visible: r.isEmojiIcon")
c = c.replace("visible: !isEmojiIcon", "visible: !r.isEmojiIcon")

# 2. Fix collapse.svg and plus.svg
c = c.replace("image: \":/icons/icons/ui/collapse.svg\"", "image: \":/icons/icons/ui/angle-arrow-left.svg\"")
c = c.replace("image: \":/icons/icons/ui/plus.svg\"", "image: \":/icons/icons/ui/add-square-button.svg\"")

with open("nheko/resources/qml/CommunitiesList.qml", "w") as f:
    f.write(c)
