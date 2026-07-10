with open("nheko/src/timeline/CommunitiesModel.h", "r") as f:
    c = f.read()

c = c.replace("return 2 + tags_.size() + spaceOrder_.size();", "return 1 + tags_.size() + spaceOrder_.size();")

with open("nheko/src/timeline/CommunitiesModel.h", "w") as f:
    f.write(c)

with open("nheko/src/timeline/CommunitiesModel.cpp", "r") as f:
    c = f.read()

c = c.replace("this->index(cindex + 2)", "this->index(cindex + 1)")
c = c.replace("tags_.indexOf(tagId) + 2", "tags_.indexOf(tagId) + 1")
c = c.replace("index(idx + 2)", "index(idx + 1)")
c = c.replace("index(idx + 2 + spaceOrder_.size())", "index(idx + 1 + spaceOrder_.size())")
c = c.replace("sourceRow < 2", "sourceRow < 1")
c = c.replace("sourceRow - 2", "sourceRow - 1")

with open("nheko/src/timeline/CommunitiesModel.cpp", "w") as f:
    f.write(c)
