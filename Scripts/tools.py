import os
from pathlib import Path
import shlex
import subprocess


def capture(*command, cwd=None):
    return subprocess.check_output(command, cwd=cwd, text=True).strip()


def run(command, log, cwd, timeout=1800):
    log = Path(log)
    log.parent.mkdir(parents=True, exist_ok=True)
    pipeline = shlex.join(map(str, command)) + " 2>&1 | tee " + shlex.quote(str(log))
    if command[0] == "xcodebuild":
        pipeline += " | xcbeautify"
    # pipefail propagates compiler, log writer and formatter failures.
    process = subprocess.Popen(["/bin/bash", "-o", "pipefail", "-c", pipeline], cwd=cwd, start_new_session=True)
    try:
        code = process.wait(timeout=timeout)
    except (subprocess.TimeoutExpired, KeyboardInterrupt):
        import signal
        os.killpg(process.pid, signal.SIGTERM)
        try:
            process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait()
        raise
    if code:
        raise subprocess.CalledProcessError(code, command)


def environment():
    developer = Path(capture("xcode-select", "-p"))
    return {"swift": capture("xcrun", "swift", "--version"),
            "xcode": capture("/usr/libexec/PlistBuddy", "-c", "Print :DTXcodeBuild", str(developer.parent / "Info.plist")),
            "sdks": {sdk: capture("xcrun", "--sdk", sdk, "--show-sdk-version") for sdk in
                     ["iphoneos", "iphonesimulator", "macosx", "appletvos", "appletvsimulator", "watchos", "watchsimulator"]}}
