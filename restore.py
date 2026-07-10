import re

with open('patches/0000-unified-nhekobeep.patch', 'r') as f:
    patch = f.read()

# Find the diff for CommunitiesList.qml
start = patch.find('diff --git a/resources/qml/CommunitiesList.qml b/resources/qml/CommunitiesList.qml')
end = patch.find('diff --git', start + 1)
if end == -1:
    end = len(patch)

diff_content = patch[start:end]

with open('comm.patch', 'w') as f:
    f.write(diff_content)

