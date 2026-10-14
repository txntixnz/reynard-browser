#!/usr/bin/env python3
"""Execute production lifecycle code against controlled OS/engine responses.

These checks run on the macOS build runner. They cannot establish whether iOS
grants assertions or whether ChatGPT reconnects successfully on the device.
"""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]

with tempfile.TemporaryDirectory(prefix="reynard-resume-") as tmp:
    binary = Path(tmp) / "regression"
    source = (ROOT / "browser/Reynard/Client/SessionManagement/LivePageBackgroundTask.swift").read_text()
    source = source.replace("import GeckoView\nimport UIKit", "import Foundation")
    template = (ROOT / "tests/stability/BackgroundRegression.swift.template").read_text()
    swift_file = Path(tmp) / "main.swift"
    swift_file.write_text(template.replace("// BACKGROUND_SOURCE", source))
    subprocess.run(["swiftc", "-swift-version", "5", str(swift_file), "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True)

    connection = (ROOT / "browser/Reynard/Client/Preferences/ConnectionCompatibilityController.swift").read_text().replace("import GeckoView\n", "")
    swift_file.write_text((ROOT / "tests/stability/ConnectionPolicyRegression.swift.template").read_text().replace("// CONNECTION_SOURCE", connection))
    subprocess.run(["swiftc", "-swift-version", "5", str(swift_file), "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True)

    helper = (ROOT / "browser/Helper/Helper.swift").read_text()
    helper = helper[helper.index("@objc private protocol BootstrapPing"):helper.index("\nopen class BrowserHelper")]
    helper = helper.replace("_exit(EXIT_SUCCESS)", "recordExit(EXIT_SUCCESS)")
    swift_file.write_text((ROOT / "tests/stability/HelperRegression.swift.template").read_text().replace("// HELPER_SOURCE", helper))
    subprocess.run(["swiftc", "-parse-as-library", "-swift-version", "5", str(swift_file), "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True)

    bridge = (ROOT / "browser/GeckoView/Runtime/GeckoRuntimeBridge.mm").read_text()
    bridge = bridge[bridge.index("@protocol RYNProcessAssertion"):].replace("@MOZILLA_VERSION", '@"test"')
    # macOS also ships the real private framework. Use a uniquely named test
    # class so dlopen cannot replace/collide with the controlled API double.
    for class_name in ["BKSProcessAssertion", "RBSAssertion", "RBSTarget", "RBSDomainAttribute", "NSExtension"]:
        bridge = bridge.replace(f'NSClassFromString(@"{class_name}")', f'TestAssertionClass(@"{class_name}")')
    native_file = Path(tmp) / "assertions.mm"
    native_file.write_text((ROOT / "tests/stability/BackgroundAssertionRegression.mm.template").read_text().replace("// BRIDGE_SOURCE", bridge))
    subprocess.run(["clang++", "-std=c++17", "-fobjc-arc", "-fblocks", "-framework", "Foundation", "-I", str(ROOT / "browser/GeckoView/Runtime"), str(native_file), "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
