import re

with open("/home/kes/.gemini/antigravity/brain/a1e66c54-449c-424e-8104-0dc976c1e7d2/task.md", "r") as f:
    c = f.read()

c = c.replace("- `[ ]` **Implement fast-scroll orientation logic**", "- `[x]` **Implement fast-scroll orientation logic**")
c = c.replace("- `[ ]` **Tune QML `ListView` for smooth scrolling**", "- `[x]` **Tune QML `ListView` for smooth scrolling**")
c = c.replace("- `[ ]` **Filter empty/ghost chats**", "- `[x]` **Filter empty/ghost chats**")
c = c.replace("- `[ ]` **Expose Deep Fetch / Reinit**", "- `[x]` **Expose Deep Fetch / Reinit**")

with open("/home/kes/.gemini/antigravity/brain/a1e66c54-449c-424e-8104-0dc976c1e7d2/task.md", "w") as f:
    f.write(c)
