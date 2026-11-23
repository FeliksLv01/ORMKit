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
        syntax = next(
            pin for pin in json.loads((ROOT / "Package.resolved").read_text())["pins"]
            if pin["identity"] == "swift-syntax"
        )
        products = ["SwiftSyntax", "SwiftSyntaxMacros", "SwiftCompilerPlugin", "SwiftSyntaxBuilder", "SwiftParser"]
        dependencies = ", ".join(
            '.product(name: ' + json.dumps(name) + ', package: "swift-syntax")' for name in products
        )
        (host / "Package.swift").write_text(
            '// swift-tools-version: 6.0\n'
            'import PackageDescription\n'
            'import CompilerPluginSupport\n'
            'let package = Package(name: "MacroTests", dependencies: [.package(url: '
            + json.dumps(syntax["location"])
            + ', revision: '
            + json.dumps(syntax["state"]["revision"])
            + ')], targets: [.macro(name: '
            + json.dumps(module)
            + ', dependencies: ['
            + dependencies
            + '], path: "Macros"), .testTarget(name: '
            + json.dumps(tests)
            + ', dependencies: ['
            + json.dumps(module)
            + ', .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax")], path: "Tests")])\n'
        )
        run(
            ["swift", "test", "--package-path", str(host), "--scratch-path", str(LOGS / "MacroTests")],
            LOGS / "macro-tests.log",
            ROOT,
        )


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
    result = LOGS / ("Tests-" + str(time.time_ns()) + ".xcresult")
    run(
        [
            "xcodebuild", "test", "-scheme", library,
            "-destination", "platform=iOS Simulator,id=" + device["udid"],
            "-derivedDataPath", str(LOGS / "DerivedData"),
            "-only-testing:" + library + "Tests",
            "-skipMacroValidation",
            "-parallel-testing-enabled", "NO",
            "-resultBundlePath", str(result),
            "CODE_SIGNING_ALLOWED=NO",
        ],
        LOGS / "ios-tests.log",
        ROOT,
    )


def negative():
    with tempfile.TemporaryDirectory(prefix="ormkit-write-only.") as directory:
        work = Path(directory)
        (work / "Sources").mkdir()
        shutil.copy(ROOT / "Tests/CompileFailures/ReadChanges.swift", work / "Sources/main.swift")
        (work / "Package.swift").write_text(
            '// swift-tools-version: 6.0\n'
            'import PackageDescription\n'
            'let package = Package(name: "WriteOnly", platforms: [.macOS(.v12)], dependencies: [.package(path: '
            + json.dumps(str(ROOT))
            + ')], targets: [.executableTarget(name: "WriteOnly", dependencies: [.product(name: "ORMKit", package: '
            + json.dumps(ROOT.name)
            + ')], path: "Sources")])\n'
        )
        log = LOGS / "write-only.log"
        try:
            run(
                ["swift", "build", "--package-path", str(work), "--scratch-path", str(LOGS / "WriteOnly")],
                log,
                ROOT,
            )
        except subprocess.CalledProcessError:
            if "Changes are write-only. Fetch a record to read existing values." not in log.read_text():
                raise RuntimeError("Expected write-only diagnostic missing: " + str(log))
        else:
            raise RuntimeError("Write-only patch unexpectedly compiled")


def main():
    parser = argparse.ArgumentParser(description="Run SwiftPM host macro, iOS, or compile-failure tests.")
    parser.add_argument("suite", choices=["macros", "ios", "negative"])
    args = parser.parse_args()
    {"macros": macros, "ios": ios, "negative": negative}[args.suite]()


if __name__ == "__main__":
    main()
