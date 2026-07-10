import re

with open("nheko/src/UserSettingsPage.cpp", "r") as f:
    c = f.read()

start_marker = "void\nCustomLabelListModel::refreshFromSettings()"
end_marker = "endResetModel();\n}"

start_idx = c.find(start_marker)
end_idx = c.find(end_marker, start_idx) + len(end_marker)

new_func = """void
CustomLabelListModel::refreshFromSettings()
{
    beginResetModel();
    labels_.clear();
    
    QSet<QString> knownTags;
    auto custom = UserSettings::instance()->customLabels();
    for (const auto &v : std::as_const(custom)) {
        auto lbl = v.value<CustomLabel>();
        labels_.append(lbl);
        knownTags.insert(lbl.tag);
    }
    
    // Auto-discover tags from rooms
    auto roomInfos = cache::client()->roomInfo(false);
    for (auto it = roomInfos.begin(); it != roomInfos.end(); ++it) {
        for (const auto &tag : it.value().tags) {
            QString qtag = QString::fromStdString(tag);
            if (!knownTags.contains(qtag) && !qtag.isEmpty()) {
                CustomLabel lbl;
                lbl.tag = qtag;
                lbl.displayName = qtag;
                lbl.iconKey = "";
                labels_.append(lbl);
                knownTags.insert(qtag);
            }
        }
    }
    
    endResetModel();
}"""

c = c[:start_idx] + new_func + c[end_idx:]

with open("nheko/src/UserSettingsPage.cpp", "w") as f:
    f.write(c)
