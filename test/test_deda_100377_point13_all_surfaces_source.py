import unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
MAIN=ROOT/'lib/main.dart'
STAGE71=ROOT/'lib/deda_stage71_free_owned_use_profile.dart'
MANAGER=ROOT/'lib/deda_stage71_free_manager_200_service.dart'
SPARK=ROOT/'lib/deda_qa32_spark_public_identifier_directory.dart'
OWNER=ROOT/'lib/deda_qa32_active_account_scope.dart'

class Point13TrueAccountProjectionSourceTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.s=MAIN.read_text()
        cls.stage71=STAGE71.read_text()
        cls.manager=MANAGER.read_text()
        cls.spark=SPARK.read_text()
        cls.owner=OWNER.read_text()

    def test_owner_friends_receiver_and_share_have_verified_visual_adapters(self):
        s=self.s
        self.assertEqual(s.count('DedaStage48ActiveInkProfileSlot('), 1)
        self.assertEqual(s.count('DedaQa32ActiveAccountScope('), 2)
        self.assertEqual(s.count('DedaStage50VerifiedFriendInkBadge('), 4)
        self.assertEqual(s.count('DedaStage49VerifiedShareIdBadge('), 1)
        self.assertIn('DEDA_QA32_RECEIVED_PERSONAL_LOCATION_VERIFIED_SENDER_ALIAS_NO_DEPLOY',s)
        self.assertIn('DEDA_QA32_FRIEND_PUBLIC_FULL_VERIFIED_ID_FOIL_NO_DEPLOY',s)
        self.assertIn('DedaStage51FriendSearch.findByUserInput(id)',s)
        self.assertIn('DedaSocialService.sendFriendRequest(',s)
        self.assertIn('DEDA_QA32_SHARE_SENDER_VERIFIED_ACTIVE_ID_VISUAL_ONLY',s)

    def test_manager_200_source_is_account_bound_and_catalog_stays_private(self):
        m=self.manager
        self.assertIn("static const collection = 'deda_stage71_admin_catalog';",m)
        self.assertIn("static const registry = 'deda_stage71_granted_registry';",m)
        self.assertIn('DEDA_STAGE71_ADMIN200_RULES_AND_PRIVATE_CATALOG_DEPLOYED',m)
        self.assertIn("normalizeAdminRole(profile['role']) != 'general_manager'",m)
        self.assertIn('normalizeAdminStatus(profile)',m)
        self.assertIn('defaultValue: false',m)
        self.assertIn('originalId',self.stage71)
        self.assertIn("'recipientOriginalId'",self.stage71)
        self.assertIn('account-rotated',self.stage71)
        self.assertIn('accountKey',self.stage71)
        self.assertIn('acceptedOwnedForMyStore(original)',self.stage71)
        self.assertIn('receivedNames(originalId)',self.stage71)
        self.assertIn('DEDA_100377_UNIFIED_ACCEPTED_OWNERSHIP_PROFILE_AND_MY_STORE',self.stage71)

    def test_late_firebase_start_and_resume_rearm_only_verified_owner_alias(self):
        owner=self.owner
        self.assertIn('DEDA_100377_POINT13_LATE_FIREBASE_INIT_ACCOUNT_SCOPE_REARM',owner)
        self.assertIn('with WidgetsBindingObserver',owner)
        self.assertIn('WidgetsBinding.instance.addObserver(this);',owner)
        self.assertIn('WidgetsBinding.instance.removeObserver(this);',owner)
        self.assertIn('void _attachAuthWhenReady()',owner)
        self.assertIn('FirebaseAuth.instance.authStateChanges().listen',owner)
        self.assertIn('DedaStage71ActiveIdRefresh.notifier.addListener(_load);',owner)
        self.assertIn('state == AppLifecycleState.resumed',owner)
        self.assertIn('_attachAuthWhenReady();',owner)
        self.assertIn('_load(); // server-verified refresh, never a local alias guess',owner)
        self.assertIn('DedaStage71OwnedIdentifierService.active(original)',owner)
        self.assertIn('!DedaStage71OwnedIdentifierService.enabled',owner)
        self.assertIn('verifiedFor(currentUid, widget.originalId)',owner)

    def test_source_of_truth_is_original_and_active_alias_is_server_proof(self):
        spark=self.spark
        owner=self.owner
        self.assertIn('DEDA_QA32_SPARK_PUBLIC_IDS_LIVE',spark)
        self.assertIn('defaultValue: false',spark)
        self.assertIn('Source.server',spark)
        self.assertIn("active['activeId'] != requestedAlias",spark)
        self.assertIn('verifiedFor(currentUid, widget.originalId)',owner)
        self.assertIn('DedaStage71OwnedIdentifierService.active(original)',owner)
        self.assertIn('DedaStage71ActiveIdRefresh.notifier',owner)
        self.assertIn('_currentUid() != uid',owner)
        self.assertIn('releaseEnabled', (ROOT/'lib/deda_100377_point13_unified_identity_projection_staged.dart').read_text())

if __name__=='__main__':
    unittest.main()
