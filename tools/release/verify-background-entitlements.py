#!/usr/bin/env python3
"""Inspect the signed host and Gecko helper in the final TrollStore package."""
import argparse
from pathlib import Path
import plistlib
import subprocess
import tempfile
import zipfile

KEY = "com.apple.runningboard.assertions.webkit"
HOST_EXECUTION_KEYS = (
    "com.apple.multitasking.unlimitedassertions",
    "com.apple.multitasking.systemappassertions",
)
EXECUTABLES = {
    "host": "Payload/Reynard.app/Reynard",
    "Gecko helper": "Payload/Reynard.app/PlugIns/Reynard Helper.appex/Reynard Helper",
}


def validate_entitlements(entitlements):
    for role in EXECUTABLES:
        keys = (KEY, *HOST_EXECUTION_KEYS) if role == "host" else (KEY,)
        for key in keys:
            if entitlements.get(role, {}).get(key) is not True:
                raise RuntimeError(f"Signed {role} is missing required background entitlement: {key}")


def verify_package(package):
    entitlements = {}
    with zipfile.ZipFile(package) as archive, tempfile.TemporaryDirectory(prefix="reynard-signed-grants-") as tmp:
        for index, (role, member) in enumerate(EXECUTABLES.items()):
            if archive.namelist().count(member) != 1:
                raise RuntimeError(f"Expected exactly one signed {role} executable in package")
            binary = Path(tmp) / f"executable-{index}"
            binary.write_bytes(archive.read(member))
            result = subprocess.run(["ldid", "-e", str(binary)], check=True, capture_output=True)
            entitlements[role] = plistlib.loads(result.stdout)
    validate_entitlements(entitlements)
    print("PASS: final signed TrollStore host has task-execution permissions AND host/helper background permissions are present")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("package", type=Path)
    verify_package(parser.parse_args().package)
