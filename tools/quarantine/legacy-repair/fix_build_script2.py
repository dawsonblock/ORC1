import re

path = "scripts/build-controller-app.sh"
with open(path, "r") as f:
    content = f.read()

content = content.replace('swift build -c "$CONFIGURATION" --product OracleController --product OracleControllerHost', 'swift build -c "$CONFIGURATION" --product OracleController\nswift build -c "$CONFIGURATION" --product OracleControllerHost')

with open(path, "w") as f:
    f.write(content)
