"""DEDA 100418 isolated friend ID legacy compatibility BIND only.
Requires 100414 assembled source (which uses reviewed 100417 owner repair).
Feature is OFF in any signed APK unless owner-approved live rule is deployed.
Never changes production Firebase, stable account IDs, prizes or admin.
"""
import argparse,hashlib,json,shutil
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def one(text,old,new,description):
    count=text.count(old)
    if count!=1:raise ValueError('100418 AMBIGUOUS '+description+' count='+str(count))
    return text.replace(old,new,1)
def bind(destination):
    p=Path(destination).resolve()
    if p==ROOT or ROOT in p.parents:raise ValueError('100418 NEVER EDIT REFERENCE')
    manifest=p/'internal-build-inputs.json'
    meta=json.loads(manifest.read_text())
    if meta.get('versionCode')!=100414 or not all([
       meta.get('weekly100414FinalThree',{}).get('adminServerProofMandatory'),
       meta.get('weekly100413PublicOwnerAdminResponsive',{}).get('walletAndPrizesUnchanged'),
       meta.get('weekly100411FriendCopy',{}).get('onlyVerifiedDisplayedIdCopyable')]):
        raise ValueError('100418 NEEDS VERIFIED 100414 AND PREVIOUS FIXES')
    for name,digest in meta['sourceHashes'].items():
        if sha(p/name)!=digest:raise ValueError('100418 SOURCE HASH DRIFT '+name)
    helper='lib/deda_legacy340_active_selection_100418.dart'
    shutil.copy2(ROOT/helper,p/helper)
    uni=p/'lib/deda_unified_active_id_100410.dart'
    s=uni.read_text()
    s=one(s,
        "import 'deda_verified_active_id_store.dart';",
        "import 'deda_verified_active_id_store.dart';\n"
        "import 'deda_legacy340_active_selection_100418.dart';",
        'shared public active reader import')
    s=one(s,
        '  static final Set<String> _normal={};',
        """  static final Set<String> _normal={};
  static bool _legacyListenerBound=false;
  static void _bindLegacyReaderOnce() {
    if(!DedaLegacy340ActiveSelection100418.enabled ||
        _legacyListenerBound) return;
    _legacyListenerBound=true;
    DedaLegacy340ActiveSelection100418.revision.addListener(
        () => revision.value++);
  }""",
        'no repeated legacy revision listeners')
    s=one(s,
        '''    final current=uid;
    if (current!=null) {
      final own=DedaVerifiedActiveIdStore.read(current,original);''',
        '''    if(DedaLegacy340ActiveSelection100418.enabled) {
      // A real server active selection, not the absence of the optional
      // public projection, decides whether original ID is safe to show.
      final selected=DedaLegacy340ActiveSelection100418.selected(original);
      if(selected==null) return null;
      if(selected==original) {
        return DedaVerifiedActiveId(
          uid:'legacy340-server',originalId:original,
          displayId:original,fixedColor:null);
      }
      final publicProof=_public[original];
      if(publicProof!=null && publicProof.wellFormed &&
          publicProof.displayId==selected) return publicProof;
      final ownUid=uid;
      if(ownUid!=null) {
        final own=DedaVerifiedActiveIdStore.read(ownUid,original);
        if(own!=null && own.wellFormed && own.displayId==selected) return own;
      }
      // Premium ID itself is proven by Stage71 but color is unknown until
      // verified PUBLIC projection exists. Never invent a premium color.
      return null;
    }
    final current=uid;
    if (current!=null) {
      final own=DedaVerifiedActiveIdStore.read(current,original);''',
        'legacy active selection overrides stale public normal index')
    s=one(s,
        '''  static String? display(String original) => proof(original)?.displayId;''',
        '''  static String? display(String original) {
    if(DedaLegacy340ActiveSelection100418.enabled) {
      if(!valid(original)) return null;
      return DedaLegacy340ActiveSelection100418.selected(original);
    }
    return proof(original)?.displayId;
  }''',
        'actual confirmed Stage71 ID used for friends copy and league')
    s=one(s,
        '''    _refCounts[original]=(_refCounts[original]??0)+1;''',
        '''    _bindLegacyReaderOnce();
    final releaseLegacy=DedaLegacy340ActiveSelection100418.watch(original);
    _refCounts[original]=(_refCounts[original]??0)+1;''',
        'start one public active fallback per visible friend')
    s=one(s,
        '''      if(released) return;
      released=true;
      final remaining=(_refCounts[original]??1)-1;''',
        '''      if(released) return;
      released=true;
      releaseLegacy();
      final remaining=(_refCounts[original]??1)-1;''',
        'release peer listener on card disposal')
    s=one(s,
        """value??(DedaUnifiedActiveId100410.ready ?
          'جارِ تأكيد الآيدي...' : 'معرّف غير متاح'),""",
        """value??(DedaLegacy340ActiveSelection100418.failed(widget.originalId)
            ? 'تعذّر تأكيد الآيدي'
            : (DedaUnifiedActiveId100410.ready
                ? 'جارِ تأكيد الآيدي...' : 'معرّف غير متاح')),""",
        'error ID label not infinite spinner')
    uni.write_text(s)
    friend=p/'lib/deda_stage50_verified_friend_ink_badge.dart'
    t=friend.read_text()
    t=one(t,
        "import 'deda_unified_active_id_100410.dart';",
        "import 'deda_unified_active_id_100410.dart';\n"
        "import 'deda_legacy340_active_selection_100418.dart';",
        'friend graceful legacy read error')
    t=one(t,
        """        if(proof==null || active==null) {
          // Never substitute the potentially retired original ID while
          // waiting for server-authorized premium proof.
          return const SizedBox(height:20,child:Text(
              'جارِ تأكيد الآيدي...',textDirection:TextDirection.rtl));
        }
        if(active==originalId) return fallback;
        final verified=DedaStage50PublicIdStyle(
          requestedId:originalId,displayId:proof.displayId,
          permanentColor:proof.fixedColor,
        );""",
        """        if(active==null) {
          // Neither a missing projection nor a failed read licenses a
          // retired normal ID to appear in a premium user's public card.
          return SizedBox(height:20,child:Text(
              DedaLegacy340ActiveSelection100418.failed(originalId)
                  ? 'تعذّر تأكيد الآيدي' : 'جارِ تأكيد الآيدي...',
              textDirection:TextDirection.rtl));
        }
        if(active==originalId) return fallback;
        final verified=DedaStage50PublicIdStyle(
          requestedId:originalId,displayId:active,
          permanentColor:proof?.fixedColor,
        );""",
        'premium without published foil still displays verified new ID text')
    friend.write_text(t)
    for path in (helper,'lib/deda_unified_active_id_100410.dart',
                 'lib/deda_stage50_verified_friend_ink_badge.dart'):
        meta['sourceHashes'][path]=sha(p/path)
    meta['versionCode']=100418
    meta['weekly100418Legacy340OwnerOnlyAuthReadCandidate']={
        'buildFlagDisabledWithoutReviewedLiveRules': True,
        'readsOnlyPublicRouteAndActiveStage71': True,
        'sameAuthenticatedViewerScoped': True,
        'neverShowsOldIdIfSelectedPremium': True,
        'premiumColorNeverInvented': True,
        'copyUsesRealSelectedId': True,
        'noFirebaseUserOrRuleMutation': True,
        'adminPrizesBalancesUnchanged': True,
        'realPhoneTestPending': True
    }
    manifest.write_text(json.dumps(meta,ensure_ascii=False,indent=2)+'\n')
    print('PASS_100418_SAFE_LEGACY340_ID_COMPATIBILITY_FEATURE_FLAG_OFF')
if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('workspace')
    bind(parser.parse_args().workspace)
