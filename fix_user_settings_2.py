import re

with open("nheko/resources/qml/pages/UserSettingsPage.qml", "r") as f:
    c = f.read()

# Replace the iconCombo block entirely
start = c.find("ComboBox {\n                                id: iconCombo")
if start != -1:
    end = c.find("Label {\n                                text: model.tag", start)
    if end != -1:
        new_block = """TextField {
                                text: model.iconKey
                                placeholderText: qsTr("Icon (Emoji or :/)")
                                Layout.preferredWidth: 140
                                onEditingFinished: {
                                    CustomLabelListModel.updateLabel(index, model.tag, model.displayName, text);
                                }
                            }
                            
                            ComboBox {
                                id: iconCombo
                                model: CustomLabelListModel.availableIcons()
                                Layout.preferredWidth: 60
                                
                                property bool ignoreIndexChange: false
                                onCurrentIndexChanged: {
                                    if (ignoreIndexChange) return;
                                    if (currentIndex >= 0) {
                                        var icons = CustomLabelListModel.availableIcons();
                                        CustomLabelListModel.updateLabel(
                                            index, model.tag, model.displayName,
                                            icons[currentIndex]);
                                    }
                                }
                                Component.onCompleted: {
                                    ignoreIndexChange = true;
                                    var icons = CustomLabelListModel.availableIcons();
                                    currentIndex = Math.max(0, icons.indexOf(model.iconKey));
                                    ignoreIndexChange = false;
                                }
                                
                                delegate: ItemDelegate {
                                    width: iconCombo.width
                                    height: 32
                                    contentItem: Image {
                                        source: modelData.startsWith(":/") ? ("image://colorimage/" + modelData.replace(":/", "qrc:/") + "?" + palette.text) : ""
                                        fillMode: Image.PreserveAspectFit
                                        horizontalAlignment: Image.AlignHCenter
                                        verticalAlignment: Image.AlignVCenter
                                        visible: modelData.startsWith(":/")
                                    }
                                }
                                contentItem: Item {
                                    width: iconCombo.width
                                    height: iconCombo.height
                                    Image {
                                        anchors.centerIn: parent
                                        width: 24
                                        height: 24
                                        source: iconCombo.currentText.startsWith(":/") ? ("image://colorimage/" + iconCombo.currentText.replace(":/", "qrc:/") + "?" + palette.text) : ""
                                        fillMode: Image.PreserveAspectFit
                                        visible: iconCombo.currentText.startsWith(":/")
                                    }
                                }
                            }
                            
                            """
        c = c[:start] + new_block + c[end:]

with open("nheko/resources/qml/pages/UserSettingsPage.qml", "w") as f:
    f.write(c)
