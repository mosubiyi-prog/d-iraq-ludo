import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('friends', ROOT/'tools/app_stability/app_package/bind_stage2_friends_2026_11_24.py')
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
profile_spec = importlib.util.spec_from_file_location('profile', ROOT/'tools/app_stability/app_package/bind_stage2_profile_owner_2026_11_23.py')
profile = importlib.util.module_from_spec(profile_spec)
profile_spec.loader.exec_module(profile)

class FriendsSourceTests(unittest.TestCase):
    def test_protected_archive_has_distinct_canonical_and_auth_keys(self):
        src = profile.archived_profile_member('lib/deda_social_service.dart')
        changed = mod.patch_service(src)
        self.assertIn('uid: publicId,', changed)
        self.assertIn('profile.ownerUid == liveUid', changed)
        self.assertIn("direction('requesterPublicId')", changed)
        self.assertIn("direction('recipientPublicId')", changed)
        self.assertIn('if (outgoing == null || incoming == null) return;', changed)
        a = src.index('  static Future<String> sendFriendRequest(')
        b = changed.index('  static Future<String> sendFriendRequest(')
        self.assertEqual(src[a:], changed[b:])
        with self.assertRaises(ValueError):
            mod.patch_service(changed)

    def test_retry_and_count_use_owner_not_canonical(self):
        body = '''// DEDA_100441_FRIENDS_RETRY_FIX
    if (_loadingFriends) return;
    if (!mounted || _loadingFriends || !dedaSessionRescueStage3Enabled) return;
      await _prepareOriginal();
      if (!mounted || generation != _friendsGeneration) return;
      if (liveUid != verified.uid) {}
      final latest = DedaSocialService.watchRelations(verified.uid);
      if (FirebaseAuth.instance.currentUser?.uid != session.uid) return;
'''
        changed = mod.patch_friends_page(body)
        self.assertIn('!verified.belongsToFirebaseOwner(liveUid)', changed)
        self.assertIn('!session.belongsToFirebaseOwner(FirebaseAuth.instance.currentUser?.uid)', changed)
        self.assertIn('DedaSocialService.watchRelations(verified.uid)', changed)
        self.assertIn('DedaAuthRuntime.checkSnapshot(principal);', changed)
        with self.assertRaises(ValueError):
            mod.patch_friends_page(changed)

    def test_real_search_anchors_and_self_alias(self):
        src = profile.archived_profile_member('lib/main.dart')
        a = src.index('class _DedaAddFriendPageState')
        z = src.index('class DedaFriendRequestsPage', a)
        changed = mod.patch_add_page(src[a:z])
        self.assertIn('searchSession.isSelfProfile(found)', changed)
        self.assertIn('_resultQuery != DedaSocialService.normalizePublicId(_idController.text)', changed)
        self.assertIn('DedaSocialService.sendFriendRequest(sender: sender, target: target)', changed)

    def test_lab_binding_keeps_repository_immutable_and_requires_approved_previous_binding(self):
        with self.assertRaises(ValueError):
            mod.bind_lab(ROOT)
        self.assertIn('readFriends()', mod.LAB_HELPERS)
        self.assertIn('opening.requireCurrent()', mod.LAB_HELPERS)
        self.assertNotIn('signInAnonymously', mod.LAB_HELPERS)
        self.assertNotIn('httpsCallable', mod.LAB_HELPERS)

    def test_lab_search_preserves_existing_outer_session_operation(self):
        call='DedaStage51FriendSearch.findByUserInput(id)'
        replacement='(DedaSocialService.stage04LabMode ? DedaSocialService.readLabPublicProfile(id) : '+call+')'
        for body in (
            'final found = await '+call+';',
            'final found = await DedaSectionOperationContext.wait(\n        '+call+');',
            'final found = await\n        '+call+';',
        ):
            self.assertEqual(mod.patch_lab_search(body),body.replace(call,replacement))
        for invalid in ('missing search',call+';'+call):
            with self.assertRaises(ValueError):
                mod.patch_lab_search(invalid)

    def test_lab_preview_uses_current_accepted_relation_and_existing_service(self):
        src = profile.archived_profile_member('lib/deda_social_service.dart')
        changed = mod.patch_lab_service(mod.patch_service(src))
        self.assertIn('if(stage04LabMode)return readLabFriendPreview(relation,myUid);',changed)
        self.assertIn('view.requireAcceptedPeer(relation.id,relation.otherPublicId(key))',changed)
        self.assertIn('latest.verifyPreview(selected,profile.ownerUid,profile.publicId)',changed)
        self.assertIn('readLabPublicProfile(selected.peerPublicId)',changed)
        self.assertEqual(changed.count('static Future<DedaSocialProfile?> readLabFriendPreview('),1)
        self.assertIn("performFriendCandidate('send',target.ownerUid,target.publicId)",changed)
        self.assertIn("_performLabFriendAction(accept?'accept':'reject',relationId,renderedEvent:stage04Event)",changed)
        self.assertIn("_performLabFriendAction('remove',relationId,renderedEvent:stage04Event)",changed)
        with self.assertRaises(ValueError):
            mod.patch_lab_service(changed)

    def test_lab_preview_reuses_original_page_and_verified_stream(self):
        route='  Future<void> _openProfile(DedaFriendshipRecord relation) async {'
        bound=mod.patch_lab_preview_route(route)
        self.assertIn('watchLabFriendPreview(session,relation)',bound)
        self.assertIn('DedaFriendPublicProfilePage(profile: profile)',bound)
        self.assertIn('!session.stage04Current || snapshot.hasError',bound)
        original='    return DedaQa32LiveFriendAppearance('
        surface=mod.patch_lab_preview_surface(original)
        self.assertIn('return _buildVisible(context, profile);',surface)
        self.assertTrue(surface.endswith(original))
        self.assertIn('final result=await profileForFriend(relation,session.uid);',mod.LAB_HELPERS)
        self.assertIn('yield null;',mod.LAB_HELPERS)

    def test_lab_notification_binding_reuses_original_lifecycle(self):
        source = '''class DedaIncomingRequestNotifications {
  static Future<void> start() async {
  }
  static Future<void> markCurrentIncomingSeen() async {
  }
}
Future<DedaSocialSession> dedaPrepareSocialSectionEntry(
'''
        bound=mod.patch_lab_notifications(source)
        self.assertIn("scope:'stage04_uid_'+owner!",bound)
        self.assertIn('stage04NotificationKey!',bound)
        self.assertIn('_lifecycle.markSeen(displayed:keys,',bound)
        self.assertNotIn('DedaBackend.accountKeyForPhone',bound)

    def test_repository_cannot_be_patched(self):
        with self.assertRaises(ValueError):
            mod.bind(ROOT)

if __name__ == '__main__':
    unittest.main()
