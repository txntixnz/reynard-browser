#!/usr/bin/env python3
"""Reuse the exact 0.16.0 released engine for browser-only stability builds."""
import argparse
import hashlib
from pathlib import Path
import plistlib
import shutil
import subprocess
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[2]
VERSION = "0.16.0"
BUILD = "63fb54d"
ENGINE_TAG = "FIREFOX_157_0_RELEASE"
SHA256 = "2950d9279dcdf51644419cf0aa5a6e76017fdf7322c485e958c01769c8e4e044"
URL = "https://github.com/minh-ton/reynard-browser/releases/download/0.16.0/Reynard-TrollStore.tipa"
PREFIX = "Payload/Reynard.app/"
RUNTIME = PREFIX + "Frameworks/GeckoView.framework/Frameworks/"
LIBRARIES = {"XUL", "libfreebl3.dylib", "liblgpllibs.dylib", "libmozinference.dylib",
             "libsoftokn3.dylib", "libmozavutil.dylib", "libmozglue.dylib",
             "libgkcodecs.dylib", "libmozavcodec.dylib", "libnss3.dylib"}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--package", type=Path)
    args = parser.parse_args()
    # Refuse to pair this release with changed engine code/ABI.
    subprocess.run(["git", "diff", "--exit-code", BUILD, "HEAD", "--", "engine", "patches"], cwd=ROOT, check=True)
    if (ROOT / "engine/release.txt").read_text().strip() != ENGINE_TAG:
        raise RuntimeError("Engine release tag does not match the pinned package")
    package = args.package or ROOT / "prebuilt/Reynard-0.16.0-TrollStore.tipa"
    if not args.package:
        package.parent.mkdir(parents=True, exist_ok=True)
        print("Downloading the pinned upstream 0.16.0 TrollStore engine", flush=True)
        urllib.request.urlretrieve(URL, package)
    with package.open("rb") as stream:
        digest = hashlib.file_digest(stream, "sha256").hexdigest()
    if digest != SHA256:
        raise RuntimeError("Released package checksum mismatch; refusing engine reuse")

    dist = ROOT / "engine/firefox/obj-aarch64-apple-ios/dist"
    binary_dir = dist / "bin"
    binary_dir.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(package) as archive:
        info = plistlib.loads(archive.read(PREFIX + "Info.plist"))
        if info["CFBundleShortVersionString"] != VERSION or info["CFBundleVersion"] != BUILD:
            raise RuntimeError("Released package version/build mismatch")
        copied_libraries = set()
        for item in archive.infolist():
            if item.filename.startswith(RUNTIME):
                relative = item.filename[len(RUNTIME):]
            elif item.filename.startswith(PREFIX + "Frameworks/"):
                relative = item.filename[len(PREFIX + "Frameworks/"):]
                if relative not in LIBRARIES:
                    continue
                copied_libraries.add(relative)
            else:
                continue
            if not relative:
                continue
            path = Path(relative)
            if path.is_absolute() or ".." in path.parts:
                raise RuntimeError("Unsafe engine archive path")
            destination = binary_dir / path
            if item.is_dir():
                destination.mkdir(parents=True, exist_ok=True)
            else:
                destination.parent.mkdir(parents=True, exist_ok=True)
                destination.write_bytes(archive.read(item))
                mode = (item.external_attr >> 16) & 0o777
                if mode:
                    destination.chmod(mode)
        if copied_libraries != LIBRARIES:
            raise RuntimeError("Released package is missing engine libraries")

    if not all((binary_dir / item).exists() for item in ("chrome.manifest", "chrome", "components", "defaults", "res")):
        raise RuntimeError("Released engine runtime resources are missing")
    include = dist / "include"
    shutil.copytree(ROOT / "tools/prebuilt-gecko-headers", include, dirs_exist_ok=True)
    (include / "mozilla-config.h").write_text('#define MOZILLA_VERSION "157.0"\n')
    # The existing app packaging script expects this source theme directory.
    theme = ROOT / "engine/firefox/toolkit/mozapps/extensions/default-theme"
    shutil.copytree(binary_dir / "default-theme", theme, dirs_exist_ok=True)
    manifest = binary_dir / "chrome.manifest"
    lines = manifest.read_text().splitlines()
    manifest.write_text("\n".join(line for line in lines if line != "resource default-theme file:default-theme/") + "\n")
    print("Verified engine package checksum, ABI source, libraries and runtime resources", flush=True)
    print("Gecko is ready; only browser targets and idevice support will be compiled", flush=True)


if __name__ == "__main__":
    main()
