#!/usr/bin/env python3
"""Compile actual session/restoration methods with lightweight engine doubles.

This checks control flow without an iPhone. It does not simulate Gecko, UIKit,
networking or ChatGPT. The workflow also builds the complete app separately.
"""
from pathlib import Path
import subprocess
import tempfile
import argparse

parser = argparse.ArgumentParser()
parser.add_argument("--released-engine", action="store_true", help="Use the untouched checksum-verified release engine, without legacy 0.16 editor fixtures")
args = parser.parse_args()
ROOT = Path(__file__).resolve().parents[2]
subprocess.run(["python3", str(ROOT / "tests/stability/test-engine-package.py")], check=True)
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
    "func beginBackgroundPageActivity(", "private func endBackgroundPageActivity(",
])
tab_methods = "\n".join(method(TAB_SOURCE, sig) for sig in [
    "func applicationWillResignActive(",
    "func applicationDidBecomeActive(",
    "private func restoredURL(", "private func displayedURL(",
    "private func hasDisplayURL(", "private func restorableSessionState(",
    "private func prepareRestoration(\n", "private func prepareRestoration(for",
    "private func restoreTabIfNeeded(", "private func recoverSelectedSessionIfNeeded(",
    "private func handleSessionTermination(",
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
    if (ROOT / "browser/GeckoView/Support/WebRequestErrorBridge.mm").exists():
        subprocess.run([
            "clang++", "-std=c++17", "-fobjc-arc", "-framework", "Foundation",
            "-I", str(ROOT / "tools/prebuilt-gecko-headers-019"),
            "-I", str(ROOT / "browser/GeckoView/Support"),
            str(ROOT / "browser/GeckoView/Support/WebRequestErrorBridge.mm"),
            str(ROOT / "tests/stability/WebRequestErrorRegression.mm"),
            "-o", str(binary),
        ], check=True)
        subprocess.run([str(binary)], check=True)
    subprocess.run(["swiftc", "-swift-version", "5", str(swift_file), "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True)

    picker_menu = ROOT / "browser/Reynard/Client/Interface/ContentView/WebContent/FilePicker/FilePickerMenu.swift"
    picker_source = (ROOT / "tests/stability/PickerRegression.swift.template").read_text().replace(
        "// RESTORE_FOCUS_METHOD", method(ROOT / "browser/Reynard/Client/Interface/BrowserViewController.swift", "private func restoreContentKeyboardFocus(")
    ).replace("// DISMISS_KEYBOARD_METHOD", method(ROOT / "browser/Reynard/Client/Interface/BrowserViewController.swift", "private func dismissContentKeyboard(")).replace("// FOLLOWUP_METHOD", method(picker_menu, "func launchFollowupPicker(")).replace(
        "// SHEET_DISMISSED_METHOD", method(picker_menu, "func handleActionSheetDismissed(")
    )
    swift_file.write_text(picker_source)
    subprocess.run(["swiftc", "-parse-as-library", "-swift-version", "5", str(swift_file), "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True)

    if not args.released_engine:
        patch = (ROOT / "patches/widget/uikit/GeckoEditableSupport.mm.patch").read_text()
        native_source = "\n".join(line[1:] for line in patch.splitlines() if line.startswith("+") and not line.startswith("+++"))
        start = native_source.index("- (BOOL)interactionShouldBegin:")
        end = native_source.index("\n}", start) + 2
        native_template = (ROOT / "tests/stability/TextInteractionRegression.mm.template").read_text()
        native_file = Path(tmp) / "text-interaction.mm"
        native_file.write_text(native_template.replace("// INTERACTION_METHOD", native_source[start:end]))
        subprocess.run(["clang++", "-std=c++17", "-fobjc-arc", "-framework", "Foundation", "-framework", "CoreGraphics", str(native_file), "-o", str(binary)], check=True)
        subprocess.run([str(binary)], check=True)

    popup_template = (ROOT / "tests/stability/NewTabRegression.swift.template").read_text()
    popup_source = popup_template.replace(
        "// CREATE_SESSION_METHOD", method(SESSION_SOURCE, "func createSession(")
    ).replace("// NEW_SESSION_METHOD", method(TAB_SOURCE, "func onNewSession("))
    swift_file.write_text(popup_source)
    subprocess.run(["swiftc", "-swift-version", "5", str(swift_file), "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True)

subprocess.run(["python3", str(ROOT / "tests/stability/run-resume.py")], check=True)
