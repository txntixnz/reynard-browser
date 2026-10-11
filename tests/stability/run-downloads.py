#!/usr/bin/env python3
"""Run real destination operations and production background control flow on macOS."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix="reynard-downloads-") as tmp:
    main = Path(tmp) / "main.swift"
    binary = Path(tmp) / "regression"
    source = (ROOT / "browser/Reynard/Client/Stores/DownloadBackgroundActivity.swift").read_text()
    source = source.replace("import GeckoView\nimport UIKit", "import Foundation")
    template = (ROOT / "tests/stability/DownloadBackgroundRegression.swift.template").read_text()
    main.write_text(template.replace("// BACKGROUND_SOURCE", source))
    subprocess.run(["swiftc", "-swift-version", "5", str(main), "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
    main.write_text((ROOT / "tests/stability/DownloadDestinationRegression.swift.template").read_text())
    subprocess.run(["swiftc", "-swift-version", "5", str(ROOT / "browser/Reynard/Client/Stores/DownloadDestination.swift"), str(main), "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
