#!/usr/bin/env python3
"""Reject the host-only permission combination found in the device log."""
import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("signed_grants", ROOT / "tools/release/verify-background-entitlements.py")
grants = importlib.util.module_from_spec(spec)
spec.loader.exec_module(grants)


class BackgroundEntitlementTests(unittest.TestCase):
    def test_host_only_permission_is_rejected(self):
        with self.assertRaisesRegex(RuntimeError, "Gecko helper"):
            grants.validate_entitlements({"host": {grants.KEY: True}, "Gecko helper": {}})

    def test_child_permission_does_not_replace_host_permission(self):
        with self.assertRaisesRegex(RuntimeError, "host"):
            grants.validate_entitlements({"host": {}, "Gecko helper": {grants.KEY: True}})

    def test_both_permissions_are_required(self):
        grants.validate_entitlements({role: {grants.KEY: True} for role in grants.EXECUTABLES})


if __name__ == "__main__":
    unittest.main()
