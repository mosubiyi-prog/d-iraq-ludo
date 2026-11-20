"""Pure, credential-free negative tests for the one-account B Auth read-only audit."""
from types import SimpleNamespace
import importlib.util
from pathlib import Path
import unittest

HERE = Path(__file__).resolve().parents[1]
FILE = HERE / "tools" / "deda_b_owner_01_current_auth_readonly.py"
spec = importlib.util.spec_from_file_location("deda_b_readonly", FILE)
target = importlib.util.module_from_spec(spec)
spec.loader.exec_module(target)
A, B, C = "QA_SOURCE_UID_A1", "QA_SOURCE_UID_B2", "QA_SOURCE_UID_C3"
ACCOUNT = "9647712345678"
ORIGINAL = "@DEDA-ABC123"


def records():
    return {
        "route": {"publicId": ORIGINAL, "ownerUid": A, "active": True, "kind": "personal"},
        "user_a": {"accountKey": ACCOUNT, "sharePersonalId": ORIGINAL},
        "directory": {"accountKey": ACCOUNT, "active": True, "createdUid": B},
        "credentials": {"accountKey": ACCOUNT, "active": True, "createdUid": B},
        "social": {"publicId": ORIGINAL, "ownerUid": C},
        "user_b": {"accountKey": ACCOUNT},
        "user_c": {"accountKey": ACCOUNT},
    }


def auth(uid=B, providers=(), email=None):
    return SimpleNamespace(
        uid=uid, disabled=False, provider_data=[
            SimpleNamespace(provider_id=p) for p in providers],
        email=email, email_verified=False, phone_number=None)


class TestOneAccountReadOnly(unittest.TestCase):
    def test_history_lineage_does_not_grant_ownership(self):
        for user in [None, auth(), auth(providers=("google.com",)),
                     auth(email="test@example.test"), auth(providers=("phone",))]:
            result = target.status_of(records(), user)
            self.assertTrue(result["source_split_A_B_C_consistent"])
            self.assertFalse(result["independent_human_owner_verified"])
            self.assertFalse(result["current_phone_UID_verified"])
            self.assertFalse(result["safe_to_grant_or_merge"])
            self.assertFalse(result["B_password_provider_confirmed"])
        self.assertTrue(target.status_of(records(), auth(providers=("google.com",)))["B_google_linked"])
        self.assertFalse(target.status_of(records(), auth(email="test@example.test"))["B_google_linked"])

    def test_stale_or_forged_paths_fail_closed(self):
        for kind in ("directory", "credentials", "route", "social", "user_b", "user_c"):
            rec = records()
            if kind in ("directory", "credentials"):
                rec[kind]["createdUid"] = A
            elif kind == "route":
                rec[kind]["ownerUid"] = C
            elif kind == "social":
                rec[kind]["ownerUid"] = A
            else:
                rec[kind]["accountKey"] = "9647999999999"
            result = target.status_of(rec, auth())
            self.assertFalse(result["source_split_A_B_C_consistent"], kind)
            self.assertFalse(result["B_auth_record_present"])
            self.assertFalse(result["safe_to_grant_or_merge"])

    def test_auth_record_mismatch_is_not_same_owner(self):
        result = target.status_of(records(), auth(uid=A, providers=("google.com",)))
        self.assertFalse(result["B_auth_record_present"])
        self.assertFalse(result["B_google_linked"])
        self.assertFalse(result["safe_to_grant_or_merge"])

    def test_scope_stays_original_id_not_input_phone(self):
        self.assertEqual(target.original_scope(), "@DEDA-AQPYXJ")


if __name__ == "__main__":
    unittest.main()
