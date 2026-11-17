#!/usr/bin/env python3
"""Isolated DEDA point 1 source contracts; NO Firebase/Android/network access."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
PIN = (ROOT / "lib/deda_pin_auth.dart").read_text()
BACK = (ROOT / "lib/deda_backend.dart").read_text()
POLICY = (ROOT / "lib/deda_100431_linked_owner_session_policy.dart").read_text()
RULES = (ROOT / "firestore.rules").read_text()


def section(source, start, end):
    if source.count(start) != 1:
        raise AssertionError("missing or duplicated source anchor: " + start)
    return source.split(start, 1)[1].split(end, 1)[0]


class ExistingOwnerNoNewUid(unittest.TestCase):
    def test_no_implicit_anonymous_uid_in_pilot(self):
        body = section(PIN, "static Future<User> _ensureAnonymousSession(",
                       "// Never discard a verified")
        self.assertIn("mayPrepareAnonymousForAction(", body)
        self.assertIn("linkedOwnerPilotEnabled: dedaLinkedOwnerCompatEnabled", body)
        self.assertIn("hasCurrentPrincipal: current != null", body)
        self.assertIn("deda-existing-owner-login-required-no-new-uid", body)
        self.assertLess(body.index("mayPrepareAnonymousForAction("),
                        body.index("auth.signInAnonymously()"))

    def test_explicit_lanes_not_confused_with_owner_login(self):
        signup = section(PIN, "static Future<Map<String, dynamic>> createAccount(",
                         "static Future<Map<String, dynamic>> signIn(")
        recovery = section(PIN, "static Future<String> requestRecovery(",
                           "static Stream<DocumentSnapshot")
        login = section(PIN, "static Future<Map<String, dynamic>> signIn(",
                        "static Future<void> markCurrentDeviceTrusted()")
        self.assertIn("action: _DedaAnonymousEntry.newAccount", signup)
        self.assertIn("action: _DedaAnonymousEntry.recoveryRequest", recovery)
        self.assertNotIn("signInAnonymously(", login)
        self.assertIn("await _verifiedExistingPinUid(accountKey)", login)
        self.assertLess(login.index("_verifiedExistingPinUid(accountKey)"),
                        login.index("await _provePin("))
        self.assertIn("dedaLinkedOwnerCompatEnabled", login)

    def test_known_old_phone_cannot_create_duplicate_account(self):
        signup = section(PIN, "static Future<Map<String, dynamic>> createAccount(",
                         "static Future<Map<String, dynamic>> signIn(")
        self.assertIn("mayBeginExplicitEnrollment(", signup)
        self.assertIn("prefs.getBool(_knownAccountKey(phone)) == true", signup)
        self.assertIn("deda-existing-account-must-use-login", signup)
        self.assertLess(signup.index("deda-existing-account-must-use-login"),
                        signup.index("_ensureAnonymousSession("))
        self.assertIn("collection('deda_sessions').doc(existing.uid).get(options)", signup)
        self.assertIn("collection('users').doc(existing.uid).get(options)", signup)
        self.assertIn("deda-existing-firebase-uid-must-not-enroll-again", signup)
        self.assertIn("checkEnrollmentUid()", signup)
        self.assertIn("FirebaseAuth.instance.currentUser?.uid != user.uid", signup)

    def test_profile_sync_uses_same_account_not_generic_public_user(self):
        sync = section(BACK, "static Future<void> syncCurrentUserProfile(",
                       "static Future<bool> _hasActivePlaceRequest(")
        self.assertIn("await _ensureOwnerSessionForAccountKey(accountKey)", sync)
        self.assertIn(": await _ensurePublicUser()", sync)  # legacy preserved
        self.assertIn("ref.get(const GetOptions(source: Source.server))", sync)
        self.assertIn("existing.data()?['accountKey'] != accountKey", sync)
        self.assertIn("!existing.exists", sync)
        self.assertIn("existing.metadata.isFromCache", sync)
        self.assertIn("existing.metadata.hasPendingWrites", sync)
        self.assertIn("FirebaseAuth.instance.currentUser?.uid != user.uid", sync)
        self.assertLess(sync.index("deda-profile-owner-session-not-verified"),
                        sync.index("await ref.set("))
        self.assertNotIn("signInAnonymously(", sync)

    def test_legacy_signin_and_firestore_rules_remain_intact(self):
        self.assertIn("!linkedOwnerPilotEnabled || hasCurrentPrincipal", POLICY)
        self.assertIn("!linkedOwnerPilotEnabled || !previouslyKnownAccount", POLICY)
        public = section(BACK, "static Future<User> _ensurePublicUser()",
                         "static Future<User> _ensureOwnerSessionForAccountKey(")
        self.assertIn("mayImplicitlyPrepareOwnerSession(", public)
        self.assertIn("final credential = await auth.signInAnonymously()", public)
        self.assertIn("deda-explicit-auth-entry-required-no-new-uid", public)
        self.assertIn("match /deda_sessions/{uid}", RULES)
        self.assertIn("'uid', 'accountKey', 'installId', 'signedInAt', 'lastSeenAt'", RULES)


if __name__ == "__main__":
    unittest.main(verbosity=2)
