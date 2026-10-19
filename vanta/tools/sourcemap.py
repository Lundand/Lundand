"""Writes a Rojo-style sourcemap.json for vanta/src (used by luau-lsp to resolve requires when type checking).

python3 tools/sourcemap.py > sourcemap.json
"""
import json, os, sys

SUFFIX = [(".server.luau", "Script"), (".client.luau", "LocalScript"), (".luau", "ModuleScript")]
SERVICE_CLASS = {"StarterPlayer": "StarterPlayer"}

def classify(name):
    for suffix, cls in SUFFIX:
        if name.endswith(suffix):
            return name[: -len(suffix)], cls
    return None, None

def node(path, name, default_class):
    entries = sorted(os.listdir(path))
    children, own = [], None
    for entry in entries:
        full = os.path.join(path, entry)
        if os.path.isdir(full):
            cls = "StarterPlayerScripts" if entry == "StarterPlayerScripts" else ("StarterCharacterScripts" if entry == "StarterCharacterScripts" else "Folder")
            children.append(node(full, entry, cls))
        else:
            base, cls = classify(entry)
            if base == "init":
                own = (cls, full)
            elif base:
                children.append({"name": base, "className": cls, "filePaths": [os.path.relpath(full)]})
    result = {"name": name, "className": default_class, "children": children}
    if own:
        result["className"] = own[0]
        result["filePaths"] = [os.path.relpath(own[1])]
    return result

root = {"name": "Vanta", "className": "DataModel", "children": []}
for service in sorted(os.listdir("src")):
    root["children"].append(node(os.path.join("src", service), service, service))
json.dump(root, sys.stdout, indent=1)
