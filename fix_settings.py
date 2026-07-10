import re

config_path = '/home/kes/.config/nheko/nheko.conf'
with open(config_path, 'r') as f:
    content = f.read()

# Look for user/beeper_custom_labels if it exists, or anything similar.
# Wait, QSettings lists are saved like:
# 1\displayName=:/icons/icons/ui/world.svg
# 1\iconKey=All rooms
# We can just look for those and swap them if displayName starts with :/icons
def replacer(match):
    full_block = match.group(0)
    display_name = match.group(1)
    icon_key = match.group(2)
    
    # If display_name looks like an icon path and icon_key DOES NOT look like an icon path, swap them
    if display_name.startswith(":/icons/") and not icon_key.startswith(":/icons/"):
        return full_block.replace(f"displayName={display_name}", f"displayName={icon_key}").replace(f"iconKey={icon_key}", f"iconKey={display_name}")
    return full_block

# Try to find custom labels list format
pattern = re.compile(r'(\d+)\\displayName=(.*?)\n\1\\iconKey=(.*?)\n', re.MULTILINE)
new_content = pattern.sub(replacer, content)

# Reverse pattern just in case they are stored in opposite order
pattern2 = re.compile(r'(\d+)\\iconKey=(.*?)\n\1\\displayName=(.*?)\n', re.MULTILINE)
def replacer2(match):
    full_block = match.group(0)
    icon_key = match.group(1)
    display_name = match.group(2)
    
    if display_name.startswith(":/icons/") and not icon_key.startswith(":/icons/"):
        return full_block.replace(f"displayName={display_name}", f"displayName={icon_key}").replace(f"iconKey={icon_key}", f"iconKey={display_name}")
    return full_block

new_content = pattern2.sub(replacer2, new_content)

if new_content != content:
    with open(config_path, 'w') as f:
        f.write(new_content)
    print("Fixed corrupted QSettings custom labels.")
else:
    print("No corrupted labels found or fixed.")
