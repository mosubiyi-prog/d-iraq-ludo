"""100413 safe additive: restore owner-published normal-ID proof and
reduce repeated admin gateway reads. Never grant access from a UI cache.
Runs only after isolated 100411 verified friend-copy integration in a temporary
app. Does not mutate active IDs, wallets, Firestore rules or baseline.
"""
from pathlib import Path
import argparse,hashlib,json

def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def one(s,old,new,name):
    n=s.count(old)
    if n!=1: raise ValueError('100413 refuse ambiguous '+name+': '+str(n))
    return s.replace(old,new,1)

def bind(workspace):
    p=Path(workspace).resolve()
    root=Path(__file__).resolve().parents[3]
    if p==root or root in p.parents: raise ValueError('never modify checked-in reference')
    manifest=p/'internal-build-inputs.json'
    meta=json.loads(manifest.read_text())
    if (meta.get('versionCode')!=100411 or
        not meta.get('weekly100411FriendCopy',{}).get('onlyVerifiedDisplayedIdCopyable') or
        not meta.get('weekly100410UnifiedActiveId',{}).get('originalKeysNeverReplaced')):
        raise ValueError('100413 requires tested 100411 over 100410 baseline')
    for path,digest in meta['sourceHashes'].items():
        if not (p/path).exists() or sha(p/path)!=digest:
            raise ValueError('100413 digest mismatch '+path)
    
    f=p/'lib/deda_unified_active_id_100410.dart'
    s=f.read_text()
    s=one(s,
        "import 'deda_qa32_spark_public_identifier_directory.dart';",
        "import 'deda_qa32_spark_public_identifier_directory.dart';\n"
        "import 'deda_active_id_public_sync_100409.dart';",
        'recover owner public publication import')
    s=one(s,
        """    DedaVerifiedActiveIdStore.confirmed(
        uid:current,originalId:original,displayId:active,fixedColor:color);
  }""",
        """    DedaVerifiedActiveIdStore.confirmed(
        uid:current,originalId:original,displayId:active,fixedColor:color);
    // 100410 replaced 100409's owner verification adapter and accidentally
    // removed its publication hook. Server-verified owner NORMAL IDs and
    // premium IDs must publish the current public projection again.
    // This is asynchronous; it cannot hold up the profile or home screen.
    if (uid==current) {
      unawaited(DedaActiveIdPublicSync100409.publishAfterVerifiedRead(
        uid:current,originalId:original,
        activeId:active,fixedColor:color,
      ));
    }
  }""",
        'owner normal ID public proof after verified Stage71')
    check="""    if(DedaUnifiedActiveId100410.uid!=null) {
      unawaited(DedaUnifiedActiveId100410
          .ensureOwner(widget.originalId).catchError((Object _) {}));
    }"""
    if s.count(check)!=2: raise ValueError('100413 expect exactly TWO public owner-check loops')
    s=s.replace(check,
        """    // Public competitor/friend label: the VIEWER is never the OWNER of
    // every listed user. A network owner-read here caused N*4 failed reads
    // for friends/league. Owner verification runs once on OWN home page.
    """)
    f.write_text(s)

    mainfile=p/'lib/main.dart'
    main=mainfile.read_text()
    home='''    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeShareIdentity();
    });'''
    after='''    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeShareIdentity();
      // Do not block the first home frame, sharing, login or daily tasks.
      // The authenticating owner publishes the normal/premium proof once,
      // instead of trying to read private ownership for EACH friend/score row.
      if (DedaPreferences.isLoggedIn) {
        final openingPhone=DedaPreferences.phone;
        final original=DedaBackend.personalShareIdForPhone(openingPhone);
        unawaited(DedaUnifiedActiveId100410.ensureOwner(original)
            .catchError((Object _) {}));
      }
    });'''
    main=one(main,home,after,'home owner proof nonblocking prewarm')

    settings=main.index('class _DedaSettingsPageState')
    settingsEnd=main.index('  Widget _sectionTitle(',settings)
    block=main[settings:settingsEnd]
    block=one(block,
      '''  bool _adminEntryVisible = false;''',
      '''  bool _adminEntryVisible = false;
  bool _adminEntryTapBusy = false;
  String _adminEntryVerifiedPhone = '';
  int _adminGateRevision = 0;''',
      'scoped verified administrative tile state')
    block=one(block,
      '''  Future<void> _refreshAdminEntryVisibility() async {
    final phone''',
      '''  Future<void> _refreshAdminEntryVisibility() async {
    final revision=++_adminGateRevision;
    final phone''',
      'ignore late gateway result after session rotate')
    block=one(block,
      '''setState(() => _adminEntryVisible = allowed);''',
      '''final livePhone=DedaPreferences.accountPhone.trim().isNotEmpty
        ? DedaPreferences.accountPhone : DedaPreferences.phone;
    if (revision!=_adminGateRevision || livePhone!=phone ||
        !DedaPreferences.isLoggedIn) return;
    setState(() {
      _adminEntryVisible=allowed;
      _adminEntryVerifiedPhone=allowed ? phone : '';
    });''',
      'keep card for same confirmed session only')
    main=main[:settings]+block+main[settingsEnd:]

    begin=main.index('                                final gateAllowed = await DedaBackend',settings)
    end=main.index('                              icon: const Icon(',begin)
    old=main[begin:end]
    if old.count('currentDedaAccountCanSeeAdminEntry')!=1 or old.count('currentUserIsAdmin')!=1 or old.count('currentAdminSessionMatchesDedaEntry')!=1 or old.count('Navigator.push')!=1:
        raise ValueError('100413 admin button structure changed; refuse patch')
    replacement='''                                // The tile is ALREADY server-verified for
                                // this exact DEDA phone. Never re-read the
                                // same gateway on tap. The destination admin
                                // session still has independent server guards.
                                if (!_adminEntryVisible ||
                                    _adminEntryVerifiedPhone!=phone ||
                                    !DedaPreferences.isLoggedIn ||
                                    _adminEntryTapBusy) return;
                                setState(() => _adminEntryTapBusy=true);
                                try {
                                  // ONE session+phone match instead of
                                  // gateway + admin role + session rechecks.
                                  // false opens the actual admin LOGIN,
                                  // not the protected dashboard.
                                  final verifiedAdmin = await DedaBackend
                                      .currentAdminSessionMatchesDedaEntry(
                                        phone: phone,
                                      ).timeout(const Duration(seconds: 10));
                                  final livePhone = DedaPreferences.accountPhone
                                          .trim().isNotEmpty
                                      ? DedaPreferences.accountPhone
                                      : DedaPreferences.phone;
                                  if (!mounted || !DedaPreferences.isLoggedIn ||
                                      livePhone!=phone) return;
                                  Navigator.push(context, MaterialPageRoute(
                                    builder: (_) => verifiedAdmin
                                        ? DedaAdminDashboardPage(
                                            isArabic:DedaLanguageState.isArabic)
                                        : DedaAdminLoginPage(
                                            isArabic:DedaLanguageState.isArabic,
                                            dedaPhone:phone),
                                  ));
                                } catch (_) {
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content:Text(dedaText(
                                        'تعذر تأكيد الجلسة الإدارية. أعد المحاولة.',
                                        'Unable to verify admin session. Retry.'))),
                                    );
                                  }
                                } finally {
                                  if (mounted) {
                                    setState(() => _adminEntryTapBusy=false);
                                  }
                                }
                              },
'''
    main=main[:begin]+replacement+main[end:]
    main=one(main,
        '''OutlinedButton.icon(
                              onPressed: () async {''',
        '''OutlinedButton.icon(
                              onPressed: _adminEntryTapBusy ? null : () async {''',
        'disable duplicate admin entry taps')
    mainfile.write_text(main)

    for name in ['lib/deda_unified_active_id_100410.dart','lib/main.dart']:
        meta['sourceHashes'][name]=sha(p/name)
    meta['versionCode']=100413
    meta['weekly100413PublicOwnerAdminResponsive']={
      'ownerNormalProjectionPublicationRestored':True,
      'publicFriendOwnerReadsRemoved':True,
      'ownerReadOnceNonblockingHome':True,
      'noOriginalIdFallbackWhenPremiumUnknown':True,
      'adminTileServerOnly':True,
      'adminTileSessionPhoneScoped':True,
      'adminEntryTapDoesNotRecheckGateway':True,
      'adminDashboardStillServerValidated':True,
      'walletAndPrizesUnchanged':True,
      'noRulesOrPlayDeploy':True,
      'phoneAndTabletQaPending':True
    }
    manifest.write_text(json.dumps(meta,ensure_ascii=False,indent=2)+'\n')
    print('PASS_100413_OWNER_PROJECTION_AND_ADMIN_TAP_INTEGRATED')
if __name__=='__main__':
    ap=argparse.ArgumentParser()
    ap.add_argument('workspace',type=Path)
    bind(ap.parse_args().workspace)
