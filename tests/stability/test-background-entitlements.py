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
    def complete_host(self):
        return {key: True for key in (grants.KEY, *grants.HOST_EXECUTION_KEYS)}

    def test_host_only_permission_is_rejected(self):
        with self.assertRaisesRegex(RuntimeError, "Gecko helper"):
            grants.validate_entitlements({"host": self.complete_host(), "Gecko helper": {}})

    def test_child_permission_does_not_replace_host_permission(self):
        with self.assertRaisesRegex(RuntimeError, "host"):
            grants.validate_entitlements({"host": {}, "Gecko helper": {grants.KEY: True}})

    def test_both_permissions_are_required(self):
        grants.validate_entitlements({"host": self.complete_host(), "Gecko helper": {grants.KEY: True}})

    def test_host_task_execution_permissions_are_required(self):
        for key in grants.HOST_EXECUTION_KEYS:
            with self.subTest(key=key):
                host = self.complete_host()
                del host[key]
                with self.assertRaisesRegex(RuntimeError, key):
                    grants.validate_entitlements({"host": host, "Gecko helper": {grants.KEY: True}})

    def test_false_host_execution_permission_is_rejected(self):
        host = self.complete_host()
        host[grants.HOST_EXECUTION_KEYS[0]] = False
        with self.assertRaisesRegex(RuntimeError, grants.HOST_EXECUTION_KEYS[0]):
            grants.validate_entitlements({"host": host, "Gecko helper": {grants.KEY: True}})


if __name__ == "__main__":
    unittest.main()
