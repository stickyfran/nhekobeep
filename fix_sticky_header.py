import re

with open("nheko/resources/qml/MessageView.qml", "r") as f:
    c = f.read()

c = c.replace("return roommodel.formatDateSeparator(item.day);", "return roommodel.formatDateSeparator(item.timestamp);")

with open("nheko/resources/qml/MessageView.qml", "w") as f:
    f.write(c)
