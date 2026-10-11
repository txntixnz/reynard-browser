#!/usr/bin/env python3
"""Run production UIKit editing methods with an input-delegate recorder."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
patch = (ROOT / "patches/widget/uikit/GeckoEditableSupport.mm.patch").read_text()
source = "\n".join(line[1:] for line in patch.splitlines() if line.startswith("+") and not line.startswith("+++"))
methods = []
for name in ["setSelectedTextRange:", "replaceRange:", "setMarkedText:", "unmarkText", "insertText:", "deleteBackward", "cut:", "paste:"]:
    start = source.index("- (void)" + name)
    end = source.index("\n}", start) + 2
    methods.append(source[start:end])
with tempfile.TemporaryDirectory(prefix="reynard-autocorrect-") as tmp:
    native_file = Path(tmp) / "autocorrect.mm"
    template = (ROOT / "tests/stability/AutocorrectRegression.mm.template").read_text()
    native_file.write_text(template.replace("// EDIT_METHODS", "\n\n".join(methods)))
    binary = Path(tmp) / "regression"
    subprocess.run(["clang++", "-std=c++17", "-fobjc-arc", "-framework", "Foundation", str(native_file), "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
