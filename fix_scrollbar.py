import re

with open("nheko/resources/qml/MessageView.qml", "r") as f:
    c = f.read()

start = c.find("        contentItem: Rectangle {")
if start != -1:
    end = c.find("        }", start)
    if end != -1:
        new_block = """        contentItem: Rectangle {
            implicitWidth: 14
            radius: 7
            color: scrollbar.pressed ? Nheko.theme.separator : Qt.rgba(Nheko.theme.separator.r, Nheko.theme.separator.g, Nheko.theme.separator.b, 0.6)
            
            ToolTip {
                visible: scrollbar.pressed
                text: stickyHeader.text
                x: -width - 8
                y: (parent.height - height) / 2
                contentItem: Label {
                    text: parent.text
                    color: palette.text
                    font.bold: true
                }
                background: Rectangle {
                    color: Qt.rgba(palette.window.r, palette.window.g, palette.window.b, 0.9)
                    border.color: palette.mid
                    border.width: 1
                    radius: 4
                }
            }
"""
        c = c[:start] + new_block + c[end:]

with open("nheko/resources/qml/MessageView.qml", "w") as f:
    f.write(c)
