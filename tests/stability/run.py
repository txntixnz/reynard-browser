#!/usr/bin/env python3
"""Compile actual session/restoration methods with lightweight engine doubles.

This checks control flow without an iPhone. It does not simulate Gecko, UIKit,
networking or ChatGPT. The workflow also builds the complete app separately.
"""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
TAB_SOURCE = ROOT / "browser/Reynard/Client/TabManagement/TabManagerImpl.swift"
SESSION_SOURCE = ROOT / "browser/Reynard/Client/SessionManagement/SessionManager.swift"


def method(path, signature):
    source = path.read_text()
    start = source.index("    " + signature)
    end = source.index("\n    }", start) + len("\n    }")
    return source[start:end]


session_methods = "\n".join(method(SESSION_SOURCE, sig) for sig in [
    "func activate(", "func deactivate(", "func setApplicationForeground(",
    "func applicationDidBecomeActive(",
])
tab_methods = "\n".join(method(TAB_SOURCE, sig) for sig in [
    "func applicationDidBecomeActive(",
    "private func restoredURL(", "private func displayedURL(",
    "private func hasDisplayURL(", "private func restorableSessionState(",
    "private func prepareRestoration(\n", "private func prepareRestoration(for",
    "private func restoreTabIfNeeded(", "private func recoverSelectedSessionIfNeeded(",
    "func onSessionStateChange(", "func onSlowScript(",
])
state_source = (ROOT / "browser/GeckoView/Session/GeckoSessionState.swift").read_text()
payload_source = (ROOT / "browser/GeckoView/Support/PayloadValue.swift").read_text()
template = (ROOT / "tests/stability/Regression.swift.template").read_text()
source = template.replace("// SESSION_METHODS", session_methods).replace(
    "// TAB_METHODS", tab_methods
).replace("// STATE_SOURCE", state_source).replace("// PAYLOAD_SOURCE", payload_source)

with tempfile.TemporaryDirectory(prefix="reynard-stability-") as tmp:
    swift_file = Path(tmp) / "main.swift"
    swift_file.write_text(source)
    binary = Path(tmp) / "regression"
    subprocess.run(["swiftc", "-swift-version", "5", str(swift_file), "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
