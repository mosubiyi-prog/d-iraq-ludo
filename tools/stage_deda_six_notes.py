"""Apply the six-note delta AFTER immutable reconstructed 100379 integration."""
from pathlib import Path
import hashlib,json,re
root=Path('.')
def replace(s,a,b,n=1):
    assert s.count(a)==n, (a[:90],s.count(a),n)
    return s.replace(a,b)
p=Path('lib/main.dart'); s=p.read_text(); before=hashlib.sha256(s.encode()).hexdigest()
s="import 'deda_six_frame_equip.dart';\nimport 'deda_six_frame_purchase_action.dart';\nimport 'deda_six_level_badges.dart';\nimport 'deda_six_active_identity.dart';\n"+s
# Badge geometry remains unchanged at every call site.
s=s.replace('DedaOwner18LevelBadge(', 'DedaSixLevelBadge(').replace('DedaOwner18AchievementsPage(', 'DedaSixAchievementsPage(')
s=replace(s,'  static Future<void> setProfileAppearance({','  static int _appearanceRevision = 0;\n  static Future<void> setProfileAppearance({')
s=replace(s,'    final requestedAvatar = avatarStyle.clamp(0, 8).toInt();','    ++_appearanceRevision;\n    final requestedAvatar = avatarStyle.clamp(0, 8).toInt();')
a=s.index('  static Future<void> setProfileAppearance('); b=s.index('  static Future<void> setVoiceEnabled',a)
part=s[a:b]
# Check the local save result only; the restore retains its existing fallback.
part=part.replace('    await Future.wait([','    final writes = await Future.wait<bool>([',1)
part=replace(part,'      prefs.setInt(_profileBackgroundKey(savePhone), requestedBackground),\n    ]);','      prefs.setInt(_profileBackgroundKey(savePhone), requestedBackground),\n    ]);\n    if (writes.any((ok) => !ok)) throw StateError("appearance-local-save-failed");')
part=replace(part,'    final ownerPhone = phone;','    final revision = _appearanceRevision;\n    final ownerPhone = phone;')
part=replace(part,'bool same() => phone == ownerPhone && _appearanceCurrentUid() == uid;', 'bool same() => revision == _appearanceRevision && phone == ownerPhone && _appearanceCurrentUid() == uid;')
s=s[:a]+part+s[b:]
a=s.index('class DedaProfileFramePreview'); b=s.index('\nclass ',a+7)
e=s[a:b]
e=replace(e,'  final bool selected;', '  final bool selected;\n  final bool owned;')
e=replace(e,'    this.selected = false,', '    this.selected = false,\n    this.owned = false,')
e=e.replace('            const PositionedDirectional(', '            if (!owned) const PositionedDirectional(',1)
s=s[:a]+e+s[b:]
# Scope all editor replacements to this single class.
a=s.index('class _DedaEditProfilePageState');b=s.index('\nclass ',a+7); e=s[a:b]
e=replace(e,'    _backgroundStyle = DedaPreferences.profileBackgroundStyle;','    _backgroundStyle = DedaPreferences.profileBackgroundStyle;\n    WidgetsBinding.instance.addPostFrameCallback((_) => _loadOwnedFrames());')
anchor='  Future<void> _save() async {'
e=replace(e,anchor,'''  Future<void> _loadOwnedFrames() async {
    if (Firebase.apps.isEmpty || DedaPreferences.phone.trim().isEmpty) return;
    final phone = DedaPreferences.phone;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final owned = await DedaOwner18FrameCheckout.verifiedOwnedFrameIds(
        DedaBackend.personalShareIdForPhone(phone).trim());
      if (!mounted || DedaPreferences.phone != phone ||
          FirebaseAuth.instance.currentUser?.uid != uid) return;
      setState(() {
        for (var i = 6; i <= 18; i++) {
          if (owned.contains(DedaLabPremiumFrameStyles.byProfileStyle(i)!.id)) {
            _serverVerifiedPaidStyles.add(i);
          }
        }
      });
    } catch (_) { /* Keep unpaid frames locked until server proof succeeds. */ }
  }

  Future<bool> _equipOwnedFrame(int index) async {
    if (_saving) return false;
    final phone = DedaPreferences.phone;
    setState(() { _saving = true; _error = null; });
    try {
      await DedaSixFrameEquip.use(style: index, avatar: _avatarStyle,
          background: _backgroundStyle);
      if (!mounted || phone != DedaPreferences.phone) return false;
      setState(() {
        _serverVerifiedPaidStyles.add(index);
        _frameStyle = index; _previewFrameStyle = null;
      });
      return true;
    } catch (_) {
      if (mounted && phone == DedaPreferences.phone) {
        setState(() => _error = 'تعذّر تأكيد حفظ الإطار بالحساب. أعد المحاولة.');
      }
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

'''+anchor)
e=replace(e,'final index = offset + 3;', 'final index = DedaSixFrameOrder.styles(_serverVerifiedPaidStyles)[offset];')
e=replace(e,'                                  free &&\n                                  _frameStyle == index);','                                  (free || _serverVerifiedPaidStyles.contains(index)) &&\n                                  _frameStyle == index);')
e=replace(e,'                            onTap: free','                            onTap: _saving ? null : free')
e=replace(e,'                                DedaProfileFramePreview(\n                                  style: index,', '                                DedaProfileFramePreview(\n                                  owned: _serverVerifiedPaidStyles.contains(index),\n                                  style: index,')
e=e.replace('DedaOwner18FramePurchaseAction(', 'DedaSixFramePurchaseAction(')
e=replace(e,'''                                    onVerifiedOwned: () => setState(() {
                                      _serverVerifiedPaidStyles.add(index);
                                      _frameStyle = index;
                                      _previewFrameStyle = null;
                                    }),''','''                                    isActive: _frameStyle == index &&
                                        DedaPreferences.profileFrameStyle == index &&
                                        _previewFrameStyle == null,
                                    onVerifiedOwned: () => _equipOwnedFrame(index),
                                    onOwnershipVerified: (owned) {
                                      if (mounted && owned && !_serverVerifiedPaidStyles.contains(index)) {
                                        setState(() => _serverVerifiedPaidStyles.add(index));
                                      }
                                    },''')
e=replace(e,'''child: SelectableText(
                            DedaBackend.personalShareIdForPhone(''', '''child: DedaSixActiveIdentity(
                            selectable: true,
                            originalId: DedaBackend.personalShareIdForPhone(''')
e=e.replace('المعرّفات المميزة المملوكة: تفعيلها يتطلب ربطًا موثقًا في مرحلة مستقلة.','يظهر هنا معرّف حسابك الفعّال بعد التحقق من ملكيته.').replace('Owned premium ID activation requires verified linking in a separate stage.','Your verified active account ID appears here.')
s=s[:a]+e+s[b:]
a=s.index('class DedaPublicProfilePreviewPage'); b=s.index('\nclass ',a+7); e=s[a:b]
e=replace(e,'child: Text(\n                    id,','child: DedaSixActiveIdentity(\n                    originalId: id,')
s=s[:a]+e+s[b:]
a=s.index('  Widget _shareCard(Map<String, dynamic> item)');b=s.index('  @override',a)
e=s[a:b]
e=replace(e,'DedaStage50VerifiedFriendInkBadge(', 'DedaSixReceivedIdentity(')
s=s[:a]+e+s[b:];p.write_text(s)
# Visible own identity and copy/share use the verified alias across legacy
# account UI and Add Friend as well. No internal IDs or transaction routes change.
s=p.read_text()
for name,following in [('_DedaAccountHubPageState', None),
        ('_DedaProfilePhase2PageState', None),('_DedaAddFriendPageState', None)]:
    a=s.index('class '+name);b=s.index('\nclass ',a+7);e=s[a:b]
    if name=='_DedaAccountHubPageState':
        e=replace(e,'    final id = _personalDedaId;\n    if (id.isEmpty) return;',
          '    final id = await DedaSixIdentityCopy.resolve(_personalDedaId);\n    if (!mounted || id == null || id.isEmpty) return;',n=2)
        e=replace(e,'child: Text(\n                        _personalDedaId,',
          'child: DedaSixActiveIdentity(\n                        originalId: _personalDedaId,')
        e=replace(e,'                        maxLines: 1,\n                        overflow: TextOverflow.ellipsis,\n                        textAlign: TextAlign.center,',
          '                        textAlign: TextAlign.center,')
    elif name=='_DedaProfilePhase2PageState':
        e=replace(e,'    final id = _dedaId;\n    if (id.isEmpty) return;',
          '    final id = await DedaSixIdentityCopy.resolve(_dedaId);\n    if (!mounted || id == null || id.isEmpty) return;')
    else:
        e=replace(e,"    final id = _session?.publicId ??\n        DedaBackend.personalShareIdForPhone(DedaPreferences.phone);\n    if (id.trim().isEmpty) return;",
          "    final original = _session?.publicId ??\n        DedaBackend.personalShareIdForPhone(DedaPreferences.phone);\n    final id = await DedaSixIdentityCopy.resolve(original);\n    if (!mounted || id == null || id.trim().isEmpty) return;")
        e=replace(e,"child: Text(myId.isEmpty ? '@DEDA' : myId,\n                                maxLines: 1,",
          "child: DedaSixActiveIdentity(originalId: myId.isEmpty ? '@DEDA' : myId,")
    s=s[:a]+e+s[b:]
p.write_text(s)

# Read-only admin listing: group accounts, registration order, no documents deleted.
p=Path('lib/admin_team_pages.dart');s=p.read_text();s="import 'deda_six_admin_users.dart';\n"+s
a=s.index('class _DedaAdminUsersPageState');b=s.index('\nclass ',a+7);e=s[a:b]
e=replace(e,'  final Set<String> _openingUsers = <String>{};','  final Set<String> _openingUsers = <String>{};\n  late final _accountRows = DedaSixAdminUsers.watch();')
e=replace(e,'Future<void> _openUser(String uid) async {\n    final cleanUid = uid.trim();','Future<void> _openUser(DedaSixAdminUserRow row) async {\n    final cleanUid = row.accountKey;')
e=replace(e,"ownerUid: cleanUid,\n        sourceCollection: 'users',\n        sourceId: cleanUid,", 'ownerUid: row.ownerUid,\n        sourceCollection: row.sourceCollection,\n        sourceId: row.sourceId,')
e=replace(e,'StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(', 'StreamBuilder<List<DedaSixAdminUserRow>>(')
e=replace(e,'stream: DedaBackend.adminUsers(),','stream: _accountRows,')
e=replace(e,'snapshot.data!.docs.where((doc)', 'snapshot.data!.where((doc)')
a1=e.index('          }).toList()\n            ..sort('); b1=e.index('\n\n          return Column',a1)
e=e[:a1]+'          }).toList();'+e[b1:]
e=replace(e,'onTap: () => _openUser(doc.id),','onTap: () => _openUser(doc),')
s=s[:a]+e+s[b:];p.write_text(s)
p=Path('pubspec.yaml');s=p.read_text();asset='    - assets/deda_owner_level_badges/owner_six_rank_background_alpha_v1.png\n'
if '    - assets/deda_owner_level_badges/\n' not in s:
    s=s.replace('  assets:\n','  assets:\n'+asset)
p.write_text(s)
Path('six-note-stage.json').write_text(json.dumps({'baselineMainSHA256':before,'notes':6,'noWalletPriceOwnershipOrMapDelta':True},indent=2))
print('Applied six-note source integration; no deployment, wallet or account writes')
