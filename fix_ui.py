import re

with open("nheko/resources/qml/pages/UserSettingsPage.qml", "r") as f:
    c = f.read()

# 1. Add import "../emoji" and import "../ui"
if 'import "../emoji"' not in c:
    c = c.replace('import im.nheko', 'import im.nheko\nimport "../emoji"\nimport "../ui"')

# 2. Add StickerPicker to customLabelsDialog
picker = """
            StickerPicker {
                id: emojiPopup
                emoji: true
            }
"""
c = c.replace("            ColumnLayout {\n                spacing: Nheko.paddingMedium", picker + "\n            ColumnLayout {\n                spacing: Nheko.paddingMedium")

# 3. Replace TextField + ComboBox with TextField + ImageButton
start_marker = "TextField {\n                                text: model.iconKey"
end_marker = "Label {\n                                text: model.tag"
start_idx = c.find(start_marker)
end_idx = c.find(end_marker)

replacement = """TextField {
                                text: model.iconKey
                                placeholderText: qsTr("Icon")
                                Layout.preferredWidth: 80
                                onEditingFinished: {
                                    CustomLabelListModel.updateLabel(index, model.tag, model.displayName, text);
                                }
                            }
                            
                            ImageButton {
                                id: emojiBtn
                                Layout.preferredWidth: 22
                                Layout.preferredHeight: 22
                                image: ":/icons/icons/ui/smile.svg"
                                ToolTip.text: qsTr("Pick Emoji")
                                ToolTip.visible: hovered
                                hoverEnabled: true
                                onClicked: emojiPopup.visible ? emojiPopup.close() : emojiPopup.show(emojiBtn, "", function (plaintext, markdown) {
                                    CustomLabelListModel.updateLabel(index, model.tag, model.displayName, plaintext);
                                })
                            }
                            
                            """

c = c[:start_idx] + replacement + c[end_idx:]

with open("nheko/resources/qml/pages/UserSettingsPage.qml", "w") as f:
    f.write(c)
