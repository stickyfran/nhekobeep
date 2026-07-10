import re

def hide_state(file_path):
    with open(file_path, "r") as f:
        c = f.read()

    # Find the top-level Column/Item definition that holds the message.
    # We can just inject `visible: !wrapper.isStateEvent || Settings.showStateEvents` 
    # but since Settings might not have it, let's just do `visible: !wrapper.isStateEvent`
    # Wait, if we set visible to false on the wrapper, we also need to set height to 0.
    
    # In TimelineBubbleMessageStyle.qml, the root is Item { id: wrapper ... }
    # In TimelineDefaultMessageStyle.qml, the root is Item { id: wrapper ... }
    
    start = c.find("Item {\n    id: wrapper")
    if start != -1:
        # insert properties right after wrapper
        insert_pos = c.find("\n", start + 10)
        
        # Check if already added
        if "visible: !wrapper.isStateEvent" not in c:
            new_props = """
    visible: !wrapper.isStateEvent
    height: visible ? implicitHeight : 0
    width: visible ? implicitWidth : 0
"""
            c = c[:insert_pos] + new_props + c[insert_pos:]
            
            with open(file_path, "w") as f:
                f.write(c)

hide_state("nheko/resources/qml/TimelineBubbleMessageStyle.qml")
hide_state("nheko/resources/qml/TimelineDefaultMessageStyle.qml")
