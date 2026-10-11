#!/usr/bin/env python3
"""Reject corrupt/misidentified engine archives and strip redirect credentials."""
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("engine_package", ROOT / "tools/release/prepare-prebuilt-gecko.py")
engine = importlib.util.module_from_spec(spec)
spec.loader.exec_module(engine)

class EnginePackageTests(unittest.TestCase):
    def test_archive_integrity_and_payload(self):
        with tempfile.TemporaryDirectory() as tmp:
            archive = Path(tmp) / "engine.zip"
            with zipfile.ZipFile(archive, "w") as out:
                out.writestr("Reynard-TrollStore.tipa", b"verified engine")
            with patch.object(engine, "KEYBOARD_ARCHIVE_SHA256", hashlib.sha256(archive.read_bytes()).hexdigest()):
                self.assertEqual(engine.keyboard_engine_package(archive).read_bytes(), b"verified engine")
                archive.write_bytes(archive.read_bytes() + b"modified")
                with self.assertRaisesRegex(RuntimeError, "checksum mismatch"):
                    engine.keyboard_engine_package(archive)
            with zipfile.ZipFile(archive, "w") as out:
                out.writestr("../unwanted", b"other file")
            with patch.object(engine, "KEYBOARD_ARCHIVE_SHA256", hashlib.sha256(archive.read_bytes()).hexdigest()):
                with self.assertRaisesRegex(RuntimeError, "Unexpected files"):
                    engine.keyboard_engine_package(archive)

    def test_wrong_build_metadata_stops_before_download(self):
        metadata = {"workflow_run": {"id": engine.KEYBOARD_RUN, "head_sha": "different build"},
                    "expired": False, "name": "Reynard-TrollStore.tipa",
                    "digest": "sha256:" + engine.KEYBOARD_ARCHIVE_SHA256}
        class Opener:
            calls = 0
            def open(self, request, timeout):
                self.calls += 1
                return io.BytesIO(json.dumps(metadata).encode())
        opener = Opener()
        with tempfile.TemporaryDirectory() as tmp, patch.object(engine, "ROOT", Path(tmp)), patch.dict(engine.os.environ, {"GITHUB_TOKEN": "test-value"}), patch.object(engine.urllib.request, "build_opener", return_value=opener):
            with self.assertRaisesRegex(RuntimeError, "provenance mismatch"):
                engine.keyboard_engine_package()
        self.assertEqual(opener.calls, 1)

    def test_download_redirect_strips_token(self):
        request = urllib.request.Request("https://api.github.com/example", headers={"Authorization": "Bearer test-value"})
        redirected = engine.SafeRedirect().redirect_request(request, None, 302, "Found", {}, "https://example.blob.core.windows.net/artifact")
        self.assertIsNone(redirected.get_header("Authorization"))

if __name__ == "__main__":
    unittest.main()
