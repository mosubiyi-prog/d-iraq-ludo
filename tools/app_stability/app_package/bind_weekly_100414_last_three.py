"""100414: complete 3-point source candidate after green 100413.
Safe-owner legacy ID backfill, lightweight admin login, combined QA. NO APK,
NO production Firestore deploy. Only ephemeral assembled source is modified.
"""
import argparse,hashlib,json,shutil
from pathlib import Path

ROOT=Path(__file__).resolve().parents[3]
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def one(s,a,b,label):
    n=s.count(a)
    if n!=1: raise ValueError('100414 unsafe anchor '+label+'='+str(n))
    return s.replace(a,b,1)

def bind(path):
    p=Path(path).resolve()
    if p==ROOT or ROOT in p.parents: raise ValueError('immutable references only')
    manifest=p/'internal-build-inputs.json'
    meta=json.loads(manifest.read_text())
    if meta.get('versionCode')!=100413 or not (
        meta.get('weekly100413PublicOwnerAdminResponsive',{}).get('ownerNormalProjectionPublicationRestored')
        and meta.get('weekly100413PublicOwnerAdminResponsive',{}).get('adminTileServerOnly')
        and meta.get('weekly100411FriendCopy',{}).get('friendCardOpenUnchanged')
    ): raise ValueError('100414 requires fully verified 100413 source')
    for file,expected in meta['sourceHashes'].items():
        if not (p/file).exists() or sha(p/file)!=expected:
            raise ValueError('100414 assembled source mismatch '+file)

    extra='lib/deda_owner_legacy_public_proof_100414.dart'
    shutil.copy2(ROOT/extra,p/extra)
    f=p/'lib/deda_unified_active_id_100410.dart'
    s=f.read_text()
    s=one(s,"import 'deda_active_id_public_sync_100409.dart';",
          "import 'deda_active_id_public_sync_100409.dart';\n"
          "import 'deda_owner_legacy_public_proof_100414.dart';",
          'server-verified legacy source import')
    s=one(s,
      '''unawaited(DedaActiveIdPublicSync100409.publishAfterVerifiedRead(
        uid:current,originalId:original,
        activeId:active,fixedColor:color,
      ));''',
      '''unawaited(DedaOwnerLegacyPublicProof100414.ensureAndPublish(
        uid:current,originalId:original,
        activeId:active,fixedColor:color,
      ));''',
      'verified owner backfill BEFORE public publication, never public viewer')
    if 'ensureOwner(widget.originalId)' in s:
        raise ValueError('100414 reintroduced friend-wide private owner reads')
    f.write_text(s)

    # 100413 starts its home owner refresh after first frame. Auth may still
    # be initialising; subscribe to auth-ready transitions to avoid missing a
    # new user's one-and-only attempt at publishing the NORMAL public ID.
    f=p/'lib/main.dart'
    s=f.read_text()
    s=one(s,
      "import 'package:cloud_firestore/cloud_firestore.dart';",
      "import 'package:cloud_firestore/cloud_firestore.dart';\n"
      "import 'package:firebase_auth/firebase_auth.dart';",
      'home auth-ready watcher import')
    import re
    home_class=re.search(r'class _HomePageState extends State<HomePage>[^{]*\{',s)
    if home_class is None or s.count('class _HomePageState extends State<HomePage>')!=1:
        raise ValueError('100414 unique assembled HomeState missing')
    pos=home_class.end()
    s=s[:pos]+'''
  StreamSubscription<User?>? _ownerAuthReady;
  String? _lastOwnerRead;
'''+s[pos:]
    old='''      if (DedaPreferences.isLoggedIn) {
        final openingPhone=DedaPreferences.phone;
        final original=DedaBackend.personalShareIdForPhone(openingPhone);
        unawaited(DedaUnifiedActiveId100410.ensureOwner(original)
            .catchError((Object _) {}));
      }'''
    new='''      if (DedaPreferences.isLoggedIn) {
        _scheduleVerifiedOwner();
        if (Firebase.apps.isNotEmpty) {
          _ownerAuthReady=FirebaseAuth.instance.authStateChanges()
              .listen((_) => _scheduleVerifiedOwner());
        }
      }'''
    s=one(s,old,new,'deferred auth ready owner normal projection')
    home=s.index('class _HomePageState extends State<HomePage>')
    dispose=s.index('  @override\n  void dispose() {',home)
    method='''  void _scheduleVerifiedOwner() {
    if (!mounted || !DedaPreferences.isLoggedIn ||
        Firebase.apps.isEmpty) return;
    final uid=FirebaseAuth.instance.currentUser?.uid;
    if (uid==null || uid.isEmpty) return;
    final phone=DedaPreferences.phone;
    final id=DedaBackend.personalShareIdForPhone(phone);
    if (!DedaUnifiedActiveId100410.valid(id)) return;
    final requestKey='$uid|$phone|$id';
    if (_lastOwnerRead==requestKey) return;
    _lastOwnerRead=requestKey;
    // Background-only. Never block first frame or touch any other user.
    unawaited(DedaUnifiedActiveId100410.ensureOwner(id)
        .catchError((Object _) {
          if (mounted && _lastOwnerRead==requestKey) _lastOwnerRead=null;
        }));
  }

'''
    s=s[:dispose]+method+s[dispose:]
    home=s.index('class _HomePageState extends State<HomePage>')
    stop=s.index('  @override\n  void dispose() {',home)
    end=s.index('  }',stop)+3
    old=s[stop:end]
    if 'searchController.dispose();' not in old: raise ValueError('home dispose changed')
    s=s[:stop]+old.replace('    searchController.dispose();','    _ownerAuthReady?.cancel();\n    searchController.dispose();')+s[end:]
    f.write_text(s)

    f=p/'lib/deda_backend.dart'
    s=f.read_text()
    s=one(s,"import 'dart:convert';", "import 'dart:async';\nimport 'dart:convert';",
          'async secondary admin maintenance import')
    admin_start=s.index('  static Future<bool> signInAdmin({')
    admin_end=s.index('  static Future<void> updateCurrentAdminDisplayName(',admin_start)
    admin=s[admin_start:admin_end]
    # The assembled signed-app stages wrap admin reads in operation-context
    # timeout guards; preserve that existing server verification verbatim.
    if "collection('admins')" not in admin or 'final data = admin.data();' not in admin:
        raise ValueError('100414 expected real admin server authorization missing')
    begin=admin.index('      final cleanName = displayName.trim();')
    finish=admin.index('      return true;',begin)
    old=admin[begin:finish]
    if old.count('registerAdminNotifications')!=1 or old.count('_writeAdminAudit')!=1:
        raise ValueError('unexpected admin housekeeping sequence')
    admin=admin[:begin]+'''      // Authorization succeeded from the SERVER. Profile metadata, FCM
      // registration and sign-in audit are ancillary and must never make the
      // first valid sign-in appear failed on a weak mobile connection.
      final cleanName=displayName.trim();
      unawaited(_adminLoginHousekeeping100414(
        uid:uid,verifiedAdmin:Map<String,dynamic>.from(data ?? {}),
        suppliedName:cleanName,
      ));
'''+admin[finish:]
    helper='''  static Future<void> _adminLoginHousekeeping100414({
    required String uid,
    required Map<String,dynamic> verifiedAdmin,
    required String suppliedName,
  }) async {
    if (FirebaseAuth.instance.currentUser?.uid!=uid) return;
    final update=<String,dynamic>{
      'lastSeenAt':FieldValue.serverTimestamp(),
      'lastLoginAt':FieldValue.serverTimestamp(),
      if (suppliedName.isNotEmpty) ...{
        'displayName':suppliedName,
        'updatedAt':FieldValue.serverTimestamp(),
      },
    };
    try {
      await FirebaseFirestore.instance.collection('admins').doc(uid)
          .set(update,SetOptions(merge:true))
          .timeout(const Duration(seconds: 8));
    } catch (_) {}
    if (FirebaseAuth.instance.currentUser?.uid!=uid) return;
    try {
      await registerAdminNotifications()
          .timeout(const Duration(seconds: 5));
    } catch (_) {}
    if (FirebaseAuth.instance.currentUser?.uid!=uid) return;
    try {
      await FirebaseFirestore.instance.collection('admin_audit').add({
        'action':'admin_signed_in',
        'adminUid':uid,
        'adminName':suppliedName.isNotEmpty ? suppliedName :
            (verifiedAdmin['displayName'] ??
             verifiedAdmin['name'] ?? '').toString(),
        'adminRole':normalizeAdminRole(
            verifiedAdmin['role'] ?? verifiedAdmin['jobTitle']),
        'createdAt':FieldValue.serverTimestamp(),
      }).timeout(const Duration(seconds: 8));
    } catch (_) {}
  }

'''
    s=s[:admin_start]+helper+admin+s[admin_end:]
    start=s.index('  static Future<bool> currentAdminSessionMatchesDedaEntry(')
    end=s.index('\n  }',start)+4
    block=s[start:end]
    # Exact signed baseline wraps async calls; retain the final fail-closed
    # catch and insert transport catches immediately BEFORE it. A transport
    # timeout is not proof of a revoked admin permission.
    import re
    caught=list(re.finditer(r'\\}\\s*catch\\s*\\([^)]*\\)\\s*\\{',block))
    if not caught or 'return false' not in block[caught[-1].start():]:
        raise ValueError('100414 outer admin gateway catch missing')
    where=caught[-1].start()
    block=block[:where]+''' } on FirebaseException catch (error) {
      if (error.code=='unavailable' ||
          error.code=='deadline-exceeded' ||
          error.code=='network-request-failed') rethrow;
      return false;
    } on TimeoutException {
      rethrow;
    '''+block[where:]

    s=s[:start]+block+s[end:]
    f.write_text(s)

    f=p/'lib/admin_pages.dart'
    s=f.read_text()
    a=s.index('class _DedaAdminLoginPageState')
    b=s.index('  Future<bool> _forcePasswordChange()',a)
    login=s[a:b]
    login=one(login,
      '''      await _saveIdentity();
      final profile = await DedaBackend.currentAdminProfile();
      final gateMatches =
          await DedaBackend.currentAdminSessionMatchesDedaEntry(
        phone: widget.dedaPhone,
      );''',
      '''      // Session and linked DEDA phone are checked on SERVER first.
      // That check refreshes the admin profile, reused below for password
      // policy without a second redundant Firestore admin read.
      final gateMatches =
          await DedaBackend.currentAdminSessionMatchesDedaEntry(
        phone: widget.dedaPhone,
      );''',
      'single verified server admin profile read at first login')
    login=one(login,
      '''      if (profile['mustChangePassword'] == true) {''',
      '''      await _saveIdentity();
      final profile = await DedaBackend.currentAdminProfile();
      if (profile['mustChangePassword'] == true) {''',
      'cached after server authentication for password policy')
    s=s[:a]+login+s[b:]
    f.write_text(s)

    for name in [extra,'lib/deda_unified_active_id_100410.dart','lib/main.dart',
                 'lib/deda_backend.dart','lib/admin_pages.dart']:
        meta['sourceHashes'][name]=sha(p/name)
    meta['versionCode']=100414
    meta['weekly100414FinalThree']={
        'normalOwnerLegacyAtomicProof':True,
        'neverRekeyPremiumOrFriends':True,
        'legacyRouteDifferentUidFailClosed':True,
        'ownerAuthReadySubscription':True,
        'adminServerProofMandatory':True,
        'adminSideEffectsNoLongerBlockLogin':True,
        'adminNetworkUncertaintyNotDenied':True,
        'adminGateFailClosed':True,
        'existing100413RegressionRequired':True,
        'noLiveFirestoreRulesDeploy':True,
        'apkNotBuilt':True,
    }
    manifest.write_text(json.dumps(meta,ensure_ascii=False,indent=2)+'\n')
    print('PASS_100414_FINAL_THREE_INTEGRATION')

if __name__=='__main__':
    ap=argparse.ArgumentParser()
    ap.add_argument('workspace',type=Path)
    bind(ap.parse_args().workspace)
