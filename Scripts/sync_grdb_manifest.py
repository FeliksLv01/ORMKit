import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parent.parent


def sync():
    lock = json.loads((ROOT / "GRDBArtifact.lock.json").read_text())
    path = ROOT / "Package.swift"
    manifest = path.read_text()
    for name, key in [("grdbURL", "url"), ("grdbChecksum", "checksum")]:
        manifest, count = re.subn(r"^let " + name + r" = .*", lambda _: "let " + name + " = " + json.dumps(lock[key]), manifest, flags=re.MULTILINE)
        if count != 1:
            raise RuntimeError("Expected exactly one artifact constant: " + name)
    path.write_text(manifest)


if __name__ == "__main__":
    sync()
