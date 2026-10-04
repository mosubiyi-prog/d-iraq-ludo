from pathlib import Path

main = Path('lib/main.dart').read_text(encoding='utf-8')
service = Path('lib/deda_social_service.dart').read_text(encoding='utf-8')
rules = Path('firestore.rules').read_text(encoding='utf-8')
compact_main = ''.join(main.split())

required_main = [
    "import 'deda_social_service.dart';",
    '// DEDA_SOCIAL_SYSTEM_100269',
    '// DEDA_SOCIAL_RUNTIME_REFINEMENT_100269',
    'class DedaFriendsPage extends StatefulWidget',
    'class DedaAddFriendPage extends StatefulWidget',
    'class DedaFriendRequestsPage extends StatefulWidget',
    'class DedaFriendPublicProfilePage extends StatelessWidget',
    'class DedaStylePage extends StatefulWidget',
    'class DedaSocialProgressWallet',
    'class DedaStyleInventory',
    'DedaSocialService.findByPublicId',
    'DedaSocialService.sendFriendRequest',
    'DedaSocialService.respondToRequest',
    'DedaSocialService.removeRelation',
    'DedaSocialFriendCount.notifier',
    "dedaText('تم إرسال طلب الصداقة بنجاح.'",
    "dedaText('طلبات واردة', 'Incoming requests')",
    "dedaText('طلبات مرسلة', 'Sent requests')",
    "dedaText('الملف العام', 'Public profile')",
    "dedaText('إطارات DEDA', 'DEDA frames')",
    'static const int coinsPerTaskClaim = 10;',
    'static const int xpPerTaskClaim = 20;',
    'static const int xpPerLevel = 100;',
    "<String>{'frame_0', 'frame_1', 'frame_2', 'badge_member'}",
    "await DedaDiamondsWallet.spend(index == 3 ? 30 : 60)",
    'await DedaSocialProgressWallet.spendCoins(120)',
    "_badgeTile('badge_spark'",
    "_badgeTile('badge_elite'",
    'await DedaSocialProgressWallet.awardTaskClaim(taskId);',
    'await dedaEnsurePersonalSocialSession();',
    'hasApprovedPlace: false,',
    'height: 54,',
    'height: 48,',
]
missing = [needle for needle in required_main if needle not in main]
if missing:
    raise SystemExit('missing 100269 main markers: ' + ' | '.join(missing))

# 100267 placeholders must have become real pages.
for forbidden in [
    "arabicTitle: 'الطلبات'",
    "arabicTitle: 'الزينة'",
    "const int profileLevel = 1;",
    "prefixIcon: const Icon(Icons.alternate_email_rounded)",
    "واجهة البحث جاهزة. ربط التحقق بالحسابات وإرسال الطلب سيكون في المرحلة التالية.",
]:
    if forbidden in main:
        raise SystemExit('obsolete/placeholder social UI remains: ' + forbidden)

# The My Profile friends stat cannot remain hardcoded.
profile_start = main.index('class _DedaProfilePhase2PageState')
profile_end = main.index('class DedaPublicProfilePreviewPage', profile_start)
profile = main[profile_start:profile_end]
if "value: '0'," in profile:
    raise SystemExit('profile friends count is still hardcoded to zero')
if 'DedaSocialProgressWallet.levelNotifier.value' not in profile:
    raise SystemExit('profile level is not connected to live social progress')

# Premium frames must persist, while the original 3 free-frame rule stays intact.
if main.count('profileFrameStyle = frameStyle.clamp(0, 5).toInt();') != 1:
    raise SystemExit('premium frame setter persistence not expanded to 0..5')
if '.clamp(0, 2)' in '\n'.join(
    line for line in main.splitlines() if 'profileFrame' in line or '_profileFrameKey' in line
):
    raise SystemExit('old profile frame 0..2 persistence clamp remains')
if 'bool dedaProfileFrameIsFree(int style) => style >= 0 && style < 3;' not in main:
    raise SystemExit('three-original-free-frames rule was changed')

# Compact-field design rule for social pages.
social_start = main.index('// DEDA_SOCIAL_SYSTEM_100269')
social = main[social_start:]
if 'prefixIcon:constIcon(Icons.alternate_email_rounded)' in ''.join(social.split()):
    raise SystemExit('duplicate @ icon still exists in Add Friend input')
if 'EdgeInsets.fromLTRB(20,18,20,28)' in ''.join(social.split()):
    raise SystemExit('oversized social outer padding remains')
for value in ['height:54', 'height:48']:
    if value not in ''.join(social.split()):
        raise SystemExit('compact social field/button marker missing: ' + value)

required_service = [
    '// DEDA_SOCIAL_SERVICE_TYPES_100269',
    '// DEDA_SOCIAL_STABLE_IDENTITY_100269',
    'class DedaSocialProfile',
    'class DedaFriendshipRecord',
    'class DedaSocialSession',
    'class DedaSocialService',
    "RegExp(r'^@DEDA-[A-Z0-9]{5,12}$')",
    "collection('deda_share_ids').doc(publicId)",
    "collection('deda_social_profiles').doc(publicId)",
    "collection('deda_friendships')",
    ".where('members', arrayContains: uid)",
    'uid: publicId,',
    "'members': <String>[sender.publicId, target.publicId]",
    "'requesterUid': sender.publicId",
    "'recipientUid': target.publicId",
    "data?['sharePersonalId']",
]
missing_service = [needle for needle in required_service if needle not in service]
if missing_service:
    raise SystemExit('missing 100269 social service markers: ' + ' | '.join(missing_service))
if 'final pairKey = _pairKey(sender.uid, target.ownerUid);' in service:
    raise SystemExit('friendship still uses renewable Firebase UID pair identity')
if 'members.contains(user.uid)' in service:
    raise SystemExit('friendship relation ownership still uses renewable Firebase UID')

# The social profile document is cosmetic/public-safe only.
profile_write_start = service.index("final profileRef = _db.collection('deda_social_profiles')")
profile_write_end = service.index('return DedaSocialSession(', profile_write_start)
profile_write = service[profile_write_start:profile_write_end]
for private_field in ["'phone':", "'accountKey':", "'placeName':", "'sharePlaceId':"]:
    if private_field in profile_write:
        raise SystemExit('private/place field leaked into social profile write: ' + private_field)

required_rules = [
    '// DEDA_SOCIAL_RULES_100269',
    '// DEDA_SOCIAL_STABLE_RULES_100269',
    'match /deda_social_profiles/{publicId}',
    'match /deda_friendships/{pairKey}',
    'currentUserHasShareId(publicId)',
    'currentUserHasShareId(resource.data.requesterPublicId)',
    'currentUserHasShareId(resource.data.recipientPublicId)',
    'request.resource.data.requesterUid == request.resource.data.requesterPublicId',
    'request.resource.data.recipientUid == request.resource.data.recipientPublicId',
]
missing_rules = [needle for needle in required_rules if needle not in rules]
if missing_rules:
    raise SystemExit('missing Firestore social rule markers: ' + ' | '.join(missing_rules))

# No social write should be broad-open.
social_rules_start = rules.index('// DEDA_SOCIAL_RULES_100269')
social_rules = rules[social_rules_start:]
if 'allow write: if true' in social_rules or 'allow read, write: if true' in social_rules:
    raise SystemExit('unsafe broad social Firestore rule detected')

# Legacy functionality must remain present after the consolidated patch.
for invariant in [
    '// DEDA_PROFILE_POINTS_TOGGLE_100264',
    '// DEDA_PROFILE_STAT_CARDS_POLISH_100265',
    'DedaDiamondsWallet.balanceNotifier',
    'static Future<bool> spend(int amount)',
    'DedaTaskEngine.totalPointsNotifier',
    'class DedaAccountHubPage extends StatefulWidget',
]:
    if invariant not in main:
        raise SystemExit('legacy invariant missing after 100269: ' + invariant)

print('validated DEDA 100269 consolidated personal social system, compact UI, stable identity, level and style economy')
