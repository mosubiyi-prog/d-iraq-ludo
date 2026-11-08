"""Offline security tests — no Firebase network or credentials."""
import unittest
from preflight_qa_config import (
    PROD_FIREBASE_PROJECT,
    PROD_ANDROID,
    QA_ANDROID,
    check_config,
    checked_build_package,
)

GOOD = {
    "LAB_QA_PROJECT_ID": "deda-qa-uid-lab-1234",
    "LAB_QA_FIREBASE_APP_ID": "1:123456789012:android:deadbeef123456",
    "LAB_QA_SENDER_ID": "123456789012",
    "LAB_QA_API_KEY": "FakeQAOnlyApiKeyNoRealKeys123456",
    "LAB_QA_GOOGLE_WEB_CLIENT_ID":
        "123456789012-fakeqawebclient.apps.googleusercontent.com",
}
PRODUCTION = {
    "project_info": {"project_id": PROD_FIREBASE_PROJECT},
    "client": [{
        "client_info": {"mobilesdk_app_id": "1:888:android:abcd"},
        "api_key": [{"current_key": "FakeProductionCollisionOnly123456"}],
        "oauth_client": [
            {"client_id": "12345-fakecollision.apps.googleusercontent.com"}
        ],
    }],
}


class TestQaIsolation(unittest.TestCase):
    def test_valid_synthetic_qa(self):
        self.assertEqual(check_config(GOOD, PRODUCTION),
                         "QA_ISOLATION_CONFIG_VALID")

    def test_exact_production_project_blocked(self):
        self.assertNotEqual(
            check_config({**GOOD,"LAB_QA_PROJECT_ID":PROD_FIREBASE_PROJECT}),
            "QA_ISOLATION_CONFIG_VALID")

    def test_lookalike_project_name_without_qa_prefix_blocked(self):
        self.assertNotEqual(
            check_config({**GOOD,"LAB_QA_PROJECT_ID":"deda-production"}),
            "QA_ISOLATION_CONFIG_VALID")

    def test_android_package_must_be_unique_qa_package(self):
        self.assertEqual(checked_build_package(QA_ANDROID),
                         "QA_ANDROID_PACKAGE_VALID")
        self.assertNotEqual(checked_build_package(PROD_ANDROID),
                            "QA_ANDROID_PACKAGE_VALID")

    def test_wrong_android_sender_id_rejected(self):
        self.assertNotEqual(
            check_config({**GOOD,"LAB_QA_SENDER_ID":"000000"}),
            "QA_ISOLATION_CONFIG_VALID")

    def test_production_firebase_app_id_rejected_even_under_qa_project_name(self):
        self.assertEqual(
            check_config({**GOOD,"LAB_QA_FIREBASE_APP_ID":
                          "1:888:android:abcd",
                          "LAB_QA_SENDER_ID":"888"}, PRODUCTION),
            "LIVE_FIREBASE_CONFIGURATION_REJECTED")

    def test_production_api_key_rejected(self):
        self.assertEqual(
            check_config({**GOOD,"LAB_QA_API_KEY":
                          "FakeProductionCollisionOnly123456"},PRODUCTION),
            "LIVE_FIREBASE_CONFIGURATION_REJECTED")

    def test_production_google_oauth_id_rejected(self):
        self.assertEqual(
            check_config({**GOOD,"LAB_QA_GOOGLE_WEB_CLIENT_ID":
                          "12345-fakecollision.apps.googleusercontent.com"},
                         PRODUCTION),
            "LIVE_FIREBASE_CONFIGURATION_REJECTED")

    def test_missing_or_unexpected_json_keys_rejected(self):
        for cfg in [
            {},
            {**GOOD, "pin":"123456"},
            {k:v for k,v in GOOD.items() if k!="LAB_QA_PROJECT_ID"},
        ]:
            self.assertNotEqual(check_config(cfg,PRODUCTION),
                                "QA_ISOLATION_CONFIG_VALID")

    def test_qa_demo_project_rejected_on_real_devices(self):
        self.assertNotEqual(
            check_config({**GOOD,"LAB_QA_PROJECT_ID":"demo-deda-qa"}),
            "QA_ISOLATION_CONFIG_VALID")

    def test_missing_google_client_id_rejected(self):
        self.assertNotEqual(
            check_config({**GOOD,"LAB_QA_GOOGLE_WEB_CLIENT_ID":""}),
            "QA_ISOLATION_CONFIG_VALID")

    def test_no_raw_phone_pin_or_user_secrets_in_qa_config(self):
        self.assertEqual(set(GOOD),{
            "LAB_QA_PROJECT_ID", "LAB_QA_FIREBASE_APP_ID",
            "LAB_QA_SENDER_ID", "LAB_QA_API_KEY",
            "LAB_QA_GOOGLE_WEB_CLIENT_ID",
        })


if __name__ == "__main__":
    unittest.main()
