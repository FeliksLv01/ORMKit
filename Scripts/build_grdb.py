import hashlib
import json
from pathlib import Path
import shutil
import urllib.request

from tools import capture, environment, run

ROOT = Path(__file__).resolve().parent.parent


def checksum(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def prepare():
    config = json.loads((ROOT / "GRDBDistribution.json").read_text())
    build_environment = environment()
    inputs = json.dumps({key: value for key, value in config.items() if key != "repository"}, sort_keys=True)
    inputs += json.dumps(build_environment, sort_keys=True)
    fingerprint = hashlib.sha256(inputs.encode() + Path(__file__).read_bytes() + (ROOT / "Scripts/tools.py").read_bytes()).hexdigest()
    directory = ROOT / ".distribution/grdb" / fingerprint
    directory.mkdir(parents=True, exist_ok=True)
    archive = directory / "GRDB.xcframework.zip"
    lock_path = ROOT / "GRDBArtifact.lock.json"
    if lock_path.exists():
        lock = json.loads(lock_path.read_text())
        if lock["input_fingerprint"] == fingerprint:
            if not archive.exists() or checksum(archive) != lock["checksum"]:
                temporary = archive.with_suffix(".zip.tmp")
                with urllib.request.urlopen(lock["url"], timeout=120) as response, temporary.open("wb") as output:
                    shutil.copyfileobj(response, output)
                if checksum(temporary) != lock["checksum"]:
                    temporary.unlink()
                    raise RuntimeError("GRDB checksum mismatch")
                temporary.replace(archive)
            if not (directory / "GRDB.xcframework").is_dir():
                capture("ditto", "-x", "-k", str(archive), str(directory))
            return lock, archive
    source = directory / "source"
    if not (source / ".git").exists():
        caches = [ROOT / ".build/checkouts/GRDB.swift", *sorted((ROOT / ".distribution/grdb").glob("*/source"))]
        cached = next((path for path in caches if (path / ".git").exists() and capture("git", "-C", str(path), "rev-parse", "HEAD") == config["revision"]), None)
        if cached:
            capture("git", "clone", "--no-hardlinks", "--no-checkout", str(cached), str(source))
            capture("git", "-C", str(source), "remote", "set-url", "origin", config["source"])
        else:
            capture("git", "clone", "--depth", "1", "--branch", "v" + config["version"], "--no-checkout", config["source"], str(source))
    capture("git", "-C", str(source), "checkout", "--detach", config["revision"])
    if capture("git", "-C", str(source), "rev-parse", "HEAD") != config["revision"]:
        raise RuntimeError("GRDB source revision mismatch")
    frameworks = []
    for platform in config["platforms"]:
        path = directory / (platform["name"] + ".xcarchive")
        command = ["xcodebuild", "archive", "-project", "GRDB.xcodeproj", "-scheme", "GRDB", "-configuration", "Release",
                   "-destination", platform["destination"], "-archivePath", str(path), "SKIP_INSTALL=NO",
                   "BUILD_LIBRARY_FOR_DISTRIBUTION=YES", "CODE_SIGNING_ALLOWED=NO", "ONLY_ACTIVE_ARCH=NO"]
        command += [key + "=" + value for key, value in platform["settings"].items()]
        run(command, directory / (platform["name"] + ".log"), source)
        framework = path / "Products/Library/Frameworks/GRDB.framework"
        if not (framework / "GRDB").is_file() or not list(framework.rglob("PrivacyInfo.xcprivacy")):
            raise RuntimeError("Missing GRDB framework/privacy manifest")
        interfaces = list(framework.rglob("*.swiftinterface"))
        if not interfaces or any("\nimport GRDBSQLite\n" in file.read_text() for file in interfaces):
            raise RuntimeError("Missing stable interface or undistributed GRDBSQLite module")
        linked = capture("otool", "-L", str(framework / "GRDB"))
        if any(line.startswith("\t") and not line.strip().startswith(("@rpath/GRDB.framework/", "/usr/lib/", "/System/Library/", "@rpath/libswift")) for line in linked.splitlines()):
            raise RuntimeError("Non-portable framework dependency")
        frameworks.append(framework)
    output = directory / "GRDB.xcframework"
    if output.exists():
        shutil.rmtree(output)
    command = ["xcodebuild", "-create-xcframework"]
    for framework in frameworks:
        command += ["-framework", str(framework)]
    run(command + ["-output", str(output)], directory / "create-xcframework.log", source)
    license_path = ROOT / "ThirdPartyNotices/GRDB-LICENSE.txt"
    license_path.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy(source / "LICENSE", license_path)
    shutil.copy(license_path, output / "LICENSE.txt")
    temporary = archive.with_suffix(".zip.tmp")
    temporary.unlink(missing_ok=True)
    capture("ditto", "-c", "-k", "--keepParent", str(output), str(temporary))
    temporary.replace(archive)
    tag = "grdb-" + config["version"] + "-" + fingerprint
    lock = {"version": config["version"], "revision": config["revision"], "input_fingerprint": fingerprint,
            "checksum": checksum(archive), "release_tag": tag, "environment": build_environment,
            "url": "https://github.com/" + config["repository"] + "/releases/download/" + tag + "/GRDB.xcframework.zip"}
    lock_path.write_text(json.dumps(lock, indent=2) + "\n")
    return lock, archive


if __name__ == "__main__":
    prepare()
