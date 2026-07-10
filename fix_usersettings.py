import re

with open("nheko/resources/qml/pages/UserSettingsPage.qml", "r") as f:
    c = f.read()

# Find the iconCombo block
start = c.find("id: iconCombo")
if start != -1:
    end = c.find("delegate: ItemDelegate {", start)
    if end != -1:
        block = c[start:end]
        if "editable: true" not in block:
            new_block = block + "                                editable: true\n                                onAccepted: {\n                                    if (editText.length > 0) {\n                                        CustomLabelListModel.updateLabel(\n                                            index, model.tag, model.displayName,\n                                            editText);\n                                    }\n                                }\n"
            c = c.replace(block, new_block)

with open("nheko/resources/qml/pages/UserSettingsPage.qml", "w") as f:
    f.write(c)
