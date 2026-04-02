import os
import re

path = "scripts/build-controller-app.sh"
with open(path, "r") as f:
    content = f.read()

content = content.replace("BUILD_PRODUCTS_DIR=\"$PROJECT_ROOT/.build/$CONFIGURATION\"", "BUILD_PRODUCTS_DIR=$(swift build -c \"$CONFIGURATION\" --show-bin-path)")

with open(path, "w") as f:
    f.write(content)
