import re

# Read my files patch
with open('my_17_files.patch', 'r') as f:
    my_patch = f.read()

# Find all filenames modified in my_patch
# diff --git a/src/timeline/CommunitiesModel.cpp b/src/timeline/CommunitiesModel.cpp
my_files = set()
for match in re.finditer(r'^diff --git a/(.+?) b/\1$', my_patch, re.MULTILINE):
    my_files.add(match.group(1))

print("Files to replace:", my_files)

# Read original patch
with open('patches/0000-unified-nhekobeep.patch', 'r') as f:
    orig_patch = f.read()

# Split original patch into file diffs
# A file diff starts with 'diff --git '
# We split by 'diff --git ', then prepend it back
parts = orig_patch.split('\ndiff --git ')
# Handle the very first diff (which doesn't have a leading newline)
if parts[0].startswith('diff --git '):
    parts[0] = parts[0][len('diff --git '):]
else:
    # There might be some preamble before the first diff
    pass

filtered_parts = []
if not orig_patch.startswith('diff --git '):
    filtered_parts.append(parts[0])
    parts = parts[1:]

for p in parts:
    full_p = 'diff --git ' + p
    # Extract filename
    match = re.search(r'^diff --git a/(.+?) b/\1$', full_p, re.MULTILINE)
    if match:
        filename = match.group(1)
        if filename in my_files:
            print(f"Skipping {filename} from original patch")
            continue
    filtered_parts.append(full_p)

# Combine filtered parts and my_patch
final_patch = '\n'.join(filtered_parts)
if not final_patch.endswith('\n'):
    final_patch += '\n'
final_patch += my_patch

with open('patches/0000-unified-nhekobeep.patch', 'w') as f:
    f.write(final_patch)

print("Patch fixed successfully.")
