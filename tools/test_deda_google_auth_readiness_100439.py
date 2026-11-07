#!/usr/bin/env python3
"""Offline tests: real Firebase settings must never be inferred from QA success."""
import importlib.util
import json
import unittest
from pathlib import Path

p = Path(__file__).with_name("deda_google_auth_readiness_100439.py")
spec = importlib.util.spec_from_file_location("deda_google_auth_ready", p)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

SHA1 = "a" * 40


def config(android=True, web=True):
    oauth = []
    if android:
        oauth.append({
            "client_type": 1,
            "client_id": "android.apps.googleusercontent.com",
            "android_info": {
                "package_name": mod.APP_PACKAGE, "certificate_hash": SHA1,
            },
        })
    if web:
        oauth.append({
            "client_type": 3, "client_id": "web.apps.googleusercontent.com",
        })
    return {
        "project_info": {"project_id": mod.PROJECT_ID},
        "client": [{
            "client_info": {
                "android_client_info": {"package_name": mod.APP_PACKAGE},
            },
            "oauth_client": oauth,
        }],
    }


class GoogleReadinessTests(unittest.TestCase):
    def test_no_oauth_clients_is_not_ready(self):
        self.assertEqual(mod.review(config(android=False, web=False)), [
            "ANDROID_OAUTH_SHA1_CLIENT_MISSING",
            "WEB_OAUTH_ID_TOKEN_CLIENT_MISSING",
        ])

    def test_both_correct_clients_ready_for_local_config_only(self):
        self.assertEqual(mod.review(config(), expected_sha1=SHA1), [])

    def test_default_config_must_match_original_100439_release_signer(self):
        self.assertIn("RELEASE_SIGNER_SHA1_NOT_REGISTERED", mod.review(config()))

    def test_release_signer_sha1_must_match(self):
        self.assertIn("RELEASE_SIGNER_SHA1_NOT_REGISTERED",
                      mod.review(config(), expected_sha1="b" * 40))

    def test_wrong_project_cannot_be_used(self):
        bad = config()
        bad["project_info"]["project_id"] = "unapproved-project"
        self.assertIn("FIREBASE_PROJECT_ID_MISMATCH", mod.review(bad))

    def test_wrong_android_app_cannot_be_used(self):
        bad = config()
        bad["client"][0]["client_info"]["android_client_info"]["package_name"] = (
            "com.example.unknown"
        )
        self.assertIn("ANDROID_APP_PACKAGE_CLIENT_NOT_UNIQUE", mod.review(bad))

    def test_missing_android_or_web_oauth_is_blocked(self):
        self.assertIn("ANDROID_OAUTH_SHA1_CLIENT_MISSING",
                      mod.review(config(android=False)))
        self.assertIn("WEB_OAUTH_ID_TOKEN_CLIENT_MISSING",
                      mod.review(config(web=False)))


if __name__ == "__main__":
    unittest.main()
