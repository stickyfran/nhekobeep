import re

with open("nheko/resources/qml/MessageView.qml", "r") as f:
    c = f.read()

# Insert sticky header after chat ListView
start = c.find("id: chatRoot")
if start != -1:
    chat_end = c.find("RoundButton {\n        id: jumpToBottomBtn", start)
    if chat_end != -1:
        sticky_header = """
    // Sticky Header for date
    Rectangle {
        id: stickyHeader
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.topMargin: 8
        z: 10
        color: Qt.rgba(palette.window.r, palette.window.g, palette.window.b, 0.85)
        border.color: palette.mid
        border.width: 1
        radius: height / 2
        height: 28
        width: stickyText.implicitWidth + 24
        visible: text !== ""
        opacity: (chat.moving || chat.flicking || chat.dragging) && !chat.atYBeginning ? 1.0 : 0.0

        property string text: {
            var yPos = chat.contentY + chat.height - 40;
            var item = chat.itemAt(chat.width / 2, yPos);
            if (item && item.day !== undefined) {
                return roommodel.formatDateSeparator(item.day);
            }
            return "";
        }

        Label {
            id: stickyText
            anchors.centerIn: parent
            text: stickyHeader.text
            color: palette.text
            font.bold: true
            font.pointSize: 9
        }
        
        Behavior on opacity { NumberAnimation { duration: 250 } }
    }
"""
        c = c[:chat_end] + sticky_header + c[chat_end:]

with open("nheko/resources/qml/MessageView.qml", "w") as f:
    f.write(c)
