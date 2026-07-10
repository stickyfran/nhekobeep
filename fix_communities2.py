import re

with open("nheko/src/timeline/CommunitiesModel.cpp", "r") as f:
    c = f.read()

# 1. Remove the direct chats block from data()
start = c.find("} else if (index.row() == 1) {")
if start != -1:
    end = c.find("} else if (index.row() - 1 < spaceOrder_.size()) {", start)
    if end != -1:
        c = c[:start] + c[end:]

# 2. Fix rowCount()
c = c.replace("return tags_.size() + spaceOrder_.size() + 2;", "return tags_.size() + spaceOrder_.size() + 1;")

# 3. Fix flags()
flags_start = c.find("Qt::ItemFlags\nCommunitiesModel::flags(const QModelIndex &index) const\n{")
if flags_start != -1:
    flags_block_end = c.find("}", flags_start)
    flags_block = c[flags_start:flags_block_end]
    new_flags_block = flags_block.replace("if (index.row() < 2)", "if (index.row() < 1)")
    c = c[:flags_start] + new_flags_block + c[flags_block_end:]

# 4. Fix tags_ population
tags_pop_start = c.find("    for (const auto &t : ts)\n        tags_.push_back(QString::fromStdString(t));\n\n    // Add virtual tags for dynamic sidebar sections\n    tags_.push_back(QStringLiteral(\"virtual:unread\"));\n    tags_.push_back(QStringLiteral(\"virtual:groups\"));")
if tags_pop_start != -1:
    new_tags_pop = """    // Add virtual tags for dynamic sidebar sections FIRST
    tags_.push_back(QStringLiteral("virtual:unread"));
    tags_.push_back(QStringLiteral("virtual:groups"));

    if (ts.count("m.favourite")) {
        tags_.push_back(QStringLiteral("m.favourite"));
    }

    for (const auto &t : ts) {
        if (t != "m.favourite") {
            tags_.push_back(QString::fromStdString(t));
        }
    }"""
    c = c.replace("    for (const auto &t : ts)\n        tags_.push_back(QString::fromStdString(t));\n\n    // Add virtual tags for dynamic sidebar sections\n    tags_.push_back(QStringLiteral(\"virtual:unread\"));\n    tags_.push_back(QStringLiteral(\"virtual:groups\"));", new_tags_pop)

with open("nheko/src/timeline/CommunitiesModel.cpp", "w") as f:
    f.write(c)
