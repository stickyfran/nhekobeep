import re

content = open('/home/kes/nhekobeep/nheko/resources/qml/MessageView.qml').read()
print("TopItem logic found:")
print(re.search(r'property var topItem: \{.*?(?=text: \{)', content, re.DOTALL).group(0))
