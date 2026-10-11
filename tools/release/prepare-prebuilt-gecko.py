#!/usr/bin/env python3
"""Reuse a verified released or keyboard-fixed engine for browser-only builds."""
import argparse
import hashlib
import json
import os
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
KEYBOARD_COMMIT = "626195e58056f946f73d6fdc88cd8809fdc954c2"
KEYBOARD_ARTIFACT = 11683403964
KEYBOARD_RUN = 38072739578
KEYBOARD_ARCHIVE_SHA256 = "7a9515df2431b668d9cbb22e37c8ca5360a00504081129795b7d544a8cd76ad7"
PREFIX = "Payload/Reynard.app/"
RUNTIME = PREFIX + "Frameworks/GeckoView.framework/Frameworks/"
LIBRARIES = {"XUL", "libfreebl3.dylib", "liblgpllibs.dylib", "libmozinference.dylib",
             "libsoftokn3.dylib", "libmozavutil.dylib", "libmozglue.dylib",
             "libgkcodecs.dylib", "libmozavcodec.dylib", "libnss3.dylib"}


class SafeRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        redirected = super().redirect_request(req, fp, code, msg, headers, newurl)
        if redirected:
            redirected.remove_header("Authorization")
        return redirected


def keyboard_engine_package(local_archive=None):
    archive_path = local_archive or ROOT / "prebuilt/keyboard-engine.zip"
    archive_path.parent.mkdir(parents=True, exist_ok=True)
    if not local_archive:
        token = os.environ.get("GITHUB_TOKEN")
        if not token:
            raise RuntimeError("GITHUB_TOKEN is required to fetch the pinned workflow artifact")
        endpoint = f"https://api.github.com/repos/txntixnz/reynard-browser/actions/artifacts/{KEYBOARD_ARTIFACT}"
        headers = {"Authorization": f"Bearer {token}", "Accept": "application/vnd.github+json"}
        opener = urllib.request.build_opener(SafeRedirect())
        with opener.open(urllib.request.Request(endpoint, headers=headers), timeout=60) as response:
            metadata = json.load(response)
        run = metadata["workflow_run"]
        if (metadata["expired"] or metadata["name"] != "Reynard-TrollStore.tipa"
                or metadata.get("digest") != "sha256:" + KEYBOARD_ARCHIVE_SHA256
                or run["id"] != KEYBOARD_RUN or run["head_sha"] != KEYBOARD_COMMIT):
            raise RuntimeError("Pinned keyboard engine artifact provenance mismatch")
        with opener.open(urllib.request.Request(endpoint + "/zip", headers=headers), timeout=60) as response:
            with archive_path.open("wb") as output:
                shutil.copyfileobj(response, output)
    with archive_path.open("rb") as stream:
        if hashlib.file_digest(stream, "sha256").hexdigest() != KEYBOARD_ARCHIVE_SHA256:
            raise RuntimeError("Keyboard engine artifact archive checksum mismatch")
    package = archive_path.parent / "Reynard-keyboard-engine.tipa"
    with zipfile.ZipFile(archive_path) as archive:
        if archive.namelist() != ["Reynard-TrollStore.tipa"]:
            raise RuntimeError("Unexpected files in the pinned keyboard artifact")
        with archive.open("Reynard-TrollStore.tipa") as source, package.open("wb") as destination:
            shutil.copyfileobj(source, destination)
    return package


def verify_engine_sources(engine_commit, compile_check_only=False):
    paths = ["engine", "patches"]
    if compile_check_only:
        # The check can use older implementation code, never older bridge ABI.
        # This exact .mm-only change is permitted solely for an app compile.
        paths.append(":(exclude)patches/widget/uikit/GeckoEditableSupport.mm.patch")
    for revisions in ([engine_commit, "HEAD"], ["HEAD"]):
        result = subprocess.run(["git", "diff", "--quiet", *revisions, "--", *paths], cwd=ROOT)
        if result.returncode:
            raise RuntimeError("Engine source/ABI differs from the pinned package")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--package", type=Path)
    parser.add_argument("--keyboard-engine", action="store_true")
    parser.add_argument("--compile-check-only", action="store_true",
                        help="Allow editor implementation changes for app compilation; packaging is disabled")
    args = parser.parse_args()
    # Refuse to pair this release with changed engine code/ABI.
    engine_commit = KEYBOARD_COMMIT if args.keyboard_engine else BUILD
    if args.compile_check_only and not args.keyboard_engine:
        parser.error("--compile-check-only requires --keyboard-engine")
    verify_engine_sources(engine_commit, args.compile_check_only)
    marker = ROOT / "prebuilt/COMPILE_CHECK_ONLY"
    if args.compile_check_only:
        marker.parent.mkdir(parents=True, exist_ok=True)
        marker.write_text("This engine is for app compilation only; do not package.\n")
    elif marker.exists():
        marker.unlink()
    if (ROOT / "engine/release.txt").read_text().strip() != ENGINE_TAG:
        raise RuntimeError("Engine release tag does not match the pinned package")
    package = keyboard_engine_package(args.package) if args.keyboard_engine else args.package or ROOT / "prebuilt/Reynard-0.16.0-TrollStore.tipa"
    if not args.package and not args.keyboard_engine:
        package.parent.mkdir(parents=True, exist_ok=True)
        print("Downloading the pinned upstream 0.16.0 TrollStore engine", flush=True)
        urllib.request.urlretrieve(URL, package)
    with package.open("rb") as stream:
        digest = hashlib.file_digest(stream, "sha256").hexdigest()
    if not args.keyboard_engine and digest != SHA256:
        raise RuntimeError("Released package checksum mismatch; refusing engine reuse")

    dist = ROOT / "engine/firefox/obj-aarch64-apple-ios/dist"
    binary_dir = dist / "bin"
    binary_dir.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(package) as archive:
        info = plistlib.loads(archive.read(PREFIX + "Info.plist"))
        expected_build = KEYBOARD_COMMIT[:7] if args.keyboard_engine else BUILD
        if info["CFBundleShortVersionString"] != VERSION or info["CFBundleVersion"] != expected_build:
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
