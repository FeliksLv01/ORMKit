import argparse
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import time

from tools import capture, run

ROOT = Path(__file__).resolve().parent.parent
LOGS = ROOT / ".build/ci"


def library_name():
    return re.search(r'let package = Package\(\s*name: "([^\"]+)"', (ROOT / "Package.swift").read_text()).group(1)


def macros():
    library = library_name()
    module, tests = library + "Macros", library + "MacrosTests"
    with tempfile.TemporaryDirectory(prefix="macro-tests.") as directory:
        host = Path(directory)
        shutil.copytree(ROOT / "Sources" / module, host / "Macros")
        shutil.copytree(ROOT / "Tests" / tests, host / "Tests")
        syntax = next(pin for pin in json.loads((ROOT / "Package.resolved").read_text())["pins"] if pin["identity"] == "swift-syntax")
        products = ["SwiftSyntax", "SwiftSyntaxMacros", "SwiftCompilerPlugin", "SwiftSyntaxBuilder", "SwiftParser"]
        dependencies = ", ".join('.product(name: ' + json.dumps(name) + ', package: "swift-syntax")' for name in products)
        (host / "Package.swift").write_text('// swift-tools-version: 6.1\nimport PackageDescription\nimport CompilerPluginSupport\nlet package = Package(name: "MacroTests", dependencies: [.package(url: ' + json.dumps(syntax["location"]) + ', revision: ' + json.dumps(syntax["state"]["revision"]) + ')], targets: [.macro(name: ' + json.dumps(module) + ', dependencies: [' + dependencies + '], path: "Macros"), .testTarget(name: ' + json.dumps(tests) + ', dependencies: [' + json.dumps(module) + ', .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax")], path: "Tests")])\n')
        run(["swift", "test", "--package-path", str(host), "--scratch-path", str(LOGS / "MacroTests")], LOGS / "macro-tests.log", ROOT)


def ios():
    library = library_name()
    LOGS.mkdir(parents=True, exist_ok=True)
    run(["xcodebuild", "-version"], LOGS / "xcode.log", ROOT)
    (LOGS / "swift.log").write_text(capture("swift", "--version") + "\n")
    devices = json.loads(capture("xcrun", "simctl", "list", "devices", "available", "--json"))["devices"]
    candidates = [device for runtime, items in devices.items() if "iOS" in runtime for device in items]
    if not candidates:
        raise RuntimeError("No available iOS Simulator")
    device = next((item for item in candidates if item["state"] == "Booted"), candidates[0])
    if device["state"] != "Booted":
        subprocess.run(["xcrun", "simctl", "boot", device["udid"]], check=True, timeout=60)
    run(["xcrun", "simctl", "bootstatus", device["udid"], "-b"], LOGS / "simulator.log", ROOT, timeout=240)
    flags = "$(inherited)"
    if library in {"DebugMenuKit", "LaunchTaskKit"}:
        flags += " -enable-experimental-feature SymbolLinkageMarkers"
    result = LOGS / ("Tests-" + str(time.time_ns()) + ".xcresult")
    run(["xcodebuild", "test", "-scheme", library, "-destination", "platform=iOS Simulator,id=" + device["udid"],
         "-derivedDataPath", str(LOGS / "DerivedData"), "-only-testing:" + library + "Tests", "-skipMacroValidation",
         "-parallel-testing-enabled", "NO", "-resultBundlePath", str(result), "CODE_SIGNING_ALLOWED=NO", "OTHER_SWIFT_FLAGS=" + flags],
        LOGS / "ios-tests.log", ROOT)



def negative():
    with tempfile.TemporaryDirectory(prefix="ormkit-write-only.") as directory:
        work = Path(directory)
        (work / "Sources").mkdir()
        shutil.copy(ROOT / "Tests/CompileFailures/ReadChanges.swift", work / "Sources/main.swift")
        (work / "Package.swift").write_text('// swift-tools-version: 6.1\nimport PackageDescription\nlet package = Package(name: "WriteOnly", platforms: [.macOS(.v12)], dependencies: [.package(path: ' + json.dumps(str(ROOT)) + ')], targets: [.executableTarget(name: "WriteOnly", dependencies: [.product(name: "ORMKit", package: ' + json.dumps(ROOT.name) + ')], path: "Sources")])\n')
        log = LOGS / "write-only.log"
        try:
            run(["swift", "build", "--package-path", str(work), "--scratch-path", str(LOGS / "WriteOnly")], log, ROOT)
        except subprocess.CalledProcessError:
            if "Changes are write-only. Fetch a record to read existing values." not in log.read_text():
                raise RuntimeError("Expected write-only diagnostic missing: " + str(log))
        else:
            raise RuntimeError("Write-only patch unexpectedly compiled")


def local_grdb():
    with tempfile.TemporaryDirectory(prefix="ormkit-binary-tests.") as directory:
        work = Path(directory)
        lock = json.loads((ROOT / "GRDBArtifact.lock.json").read_text())
        artifact = ROOT / ".distribution/grdb" / lock["input_fingerprint"] / "GRDB.xcframework"
        for name in ["Sources", "Tests", "Scripts"]:
            shutil.copytree(ROOT / name, work / name)
        for name in ["GRDBArtifact.lock.json", "Package.resolved"]:
            shutil.copy(ROOT / name, work / name)
        shutil.copytree(artifact, work / "GRDB.xcframework")
        manifest = (ROOT / "Package.swift").read_text()
        marker = '.binaryTarget(name: "GRDB", url: grdbURL, checksum: grdbChecksum)'
        if manifest.count(marker) != 1:
            raise RuntimeError("Expected exactly one GRDB binary target")
        (work / "Package.swift").write_text(manifest.replace(marker, '.binaryTarget(name: "GRDB", path: "GRDB.xcframework")'))
        try:
            run(["swift", "test", "--package-path", str(work), "--scratch-path", str(LOGS / "LocalGRDB")], LOGS / "local-grdb-tests.log", ROOT)
            for suite in ["negative", "ios"]:
                subprocess.run(["python3", str(work / "Scripts/test.py"), suite], check=True)
        finally:
            candidate_logs = work / ".build/ci"
            if candidate_logs.exists():
                LOGS.mkdir(parents=True, exist_ok=True)
                for path in candidate_logs.iterdir():
                    if path.suffix == ".log":
                        shutil.copy(path, LOGS / path.name)
                    elif path.suffix == ".xcresult":
                        shutil.copytree(path, LOGS / path.name)


def main():
    parser = argparse.ArgumentParser(description="Run SwiftPM host macro or iOS runtime tests.")
    parser.add_argument("suite", choices=["macros", "ios", "negative", "local-grdb"])
    args = parser.parse_args()
    {"macros": macros, "ios": ios, "negative": negative, "local-grdb": local_grdb}[args.suite]()


if __name__ == "__main__":
    main()
