import 'dart:convert';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'deda_auth_session_runtime.dart';
import 'deda_private_data_sync.dart';
import 'deda_profile_visible_diamonds.dart';
import 'deda_stage02_lab_single_uid_2026_11_25.dart';
import 'deda_weekly_league_clock.dart';
import 'deda_weekly_community_outbox.dart';

/// Read-only envelope. Only the guarded server transaction establishes source
/// provenance; decoding a map never grants rewards, money, ownership or roles.
class DedaStage03ProtectedSnapshot {
  DedaStage03ProtectedSnapshot._(this.uid, this.progress, this.inventory, this.account);
  final String uid;
  final Map<String, Object?> progress, inventory, account;

  static bool _exact(Map<String, Object?> m, Set<String> keys) =>
      m.length == keys.length && keys.every(m.containsKey);
  static bool _counter(Object? v, {int min = 0}) =>
      v is int && v >= min && v <= 9007199254740990;
  static Object? _freeze(Object? v) {
    if (v is Map) {
      return Map<String, Object?>.unmodifiable({
        for (final e in v.entries) e.key as String: _freeze(e.value),
      });
    }
    if (v is List) return List<Object?>.unmodifiable(v.map(_freeze));
    if (v == null || v is String || v is bool || v is num) return v;
    throw const FormatException('unsupported-protected-field');
  }
  static DedaStage03ProtectedSnapshot decode({
    required String expectedUid,
    required Map<String, Object?>? progress,
    required Map<String, Object?>? inventory,
    required Map<String, Object?>? account,
  }) {
    if (expectedUid != DedaStage02LabSingleUid.approvedUid ||
        progress == null || inventory == null || account == null) {
      throw const FormatException('protected-source-incomplete');
    }
    final balances = progress['balances'];
    const units = {'points', 'coins', 'xp', 'earnedDiamonds'};
    if (!_exact(progress, {'format','accountKey','version','balances','initializedBy'}) ||
        progress['format'] != 1 || progress['accountKey'] != expectedUid ||
        !_counter(progress['version'], min: 1) || balances is! Map ||
        balances.length != units.length || !units.every((k) => _counter(balances[k])) ||
        progress['initializedBy'] is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(progress['initializedBy'] as String)) {
      throw const FormatException('invalid-protected-progress');
    }
    bool validProjection(Map<String, Object?> row, Set<String> fields) =>
        _exact(row, {'format','uid','revision','complete',...fields}) &&
        row['format'] == 1 && row['uid'] == expectedUid &&
        _counter(row['revision'], min: 1) && row['complete'] == true;
    if (!validProjection(inventory, {'frames','idGifts','diamondGifts'}) ||
        !['frames','idGifts','diamondGifts'].every((k) => inventory[k] is List)) {
      throw const FormatException('invalid-protected-inventory');
    }
    final profile = account['profile'];
    if (!validProjection(account, {'profile','friends','tasks','league'}) ||
        profile is! Map || profile.length != 4 ||
        !['displayName','originalId','activeId','fixedColor'].every(profile.containsKey) ||
        profile['displayName'] is! String || (profile['displayName'] as String).trim().isEmpty ||
        profile['originalId'] is! String ||
        !RegExp(r'^@DEDA-[A-Z0-9]{6}$').hasMatch(profile['originalId'] as String) ||
        profile['activeId'] is! String ||
        !RegExp(r'^@DEDA-[A-Z0-9]{4,12}$').hasMatch(profile['activeId'] as String) ||
        !['friends','tasks','league'].every((k) => account[k] is List)) {
      throw const FormatException('invalid-protected-account');
    }
    return DedaStage03ProtectedSnapshot._(expectedUid,
        _freeze(progress) as Map<String, Object?>,
        _freeze(inventory) as Map<String, Object?>,
        _freeze(account) as Map<String, Object?>);
  }
}

/// Section 04/01: read-only profile data contract over the existing protected
/// snapshot. It does not mint, equip, edit, infer a full wallet or create a UID.
/// No local-phone fallback. The original profile renderer is still held until
/// its actual compiled callsites consume this contract.
class DedaStage04ProfileView {
  DedaStage04ProfileView._(this._source, this.acceptedFriends);
  final DedaStage03ProtectedSnapshot _source;
  final int acceptedFriends;
  String get uid => _source.uid;
  Map get _profile => _source.account['profile'] as Map;
  Map get _balances => _source.progress['balances'] as Map;
  String get displayName => _profile['displayName'] as String;
  String get originalId => _profile['originalId'] as String;
  String get activeId => _profile['activeId'] as String;
  String? get fixedColor => _profile['fixedColor'] as String?;
  int get taskPoints => _balances['points'] as int;
  int get coins => _balances['coins'] as int;
  int get xp => _balances['xp'] as int;
  // Only the protected earned balance, NOT the complete displayed wallet.
  int get earnedDiamonds => _balances['earnedDiamonds'] as int;
  List get frameRecords => _source.inventory['frames'] as List;
  List get identifierGiftRecords => _source.inventory['idGifts'] as List;
  List get diamondGiftRecords => _source.inventory['diamondGifts'] as List;
  /// Inventory projection is read-only. Require both records for a frame;
  /// a selection, bare ID, or unaccepted grant is not evidence of ownership.
  Set<String> get verifiedPaidFrameIds {
    final ids = <String>{};
    for (final row in frameRecords) {
      if (row is! Map || row.length != 3) {
        throw const FormatException('profile-frame-proof');
      }
      final id = row['frameId'], receipt = row['receipt'], ownership = row['ownership'];
      if (id is! String || !RegExp(r'^FRAME_(03|0[5-9]|1[0-6])$').hasMatch(id) ||
          receipt is! Map || receipt.length != 5 ||
          ownership is! Map || ownership.length != 4 ||
          receipt['uid'] != uid || ownership['uid'] != uid ||
          receipt['frameId'] != id || ownership['frameId'] != id ||
          receipt['kind'] != 'lab_frame' || receipt['cost'] != 1000 ||
          receipt['createdMs'] is! int || (receipt['createdMs'] as int) <= 0 ||
          receipt['createdMs'] != ownership['createdMs'] ||
          ownership['receiptId'] != '${uid}_$id' || !ids.add(id)) {
        throw const FormatException('profile-frame-proof');
      }
    }
    return Set.unmodifiable(ids);
  }

  Set<String> get acceptedGiftIds {
    final seen = <String>{}, accepted = <String>{};
    for (final row in identifierGiftRecords) {
      if (row is! Map || row.length != 3 || !row.containsKey('acceptance')) {
        throw const FormatException('profile-id-gift-proof');
      }
      final id = row['identifier'], grant = row['grant'], acceptance = row['acceptance'];
      if (id is! String || !RegExp(r'^@DEDA-[A-Z0-9]{4,12}$').hasMatch(id) ||
          grant is! Map || grant.length != 6 || grant['uid'] != uid ||
          grant['identifier'] != id || grant['kind'] != 'gifted' ||
          !const {'001','002'}.contains(grant['group']) ||
          !const {'gold','diamond','royal','pink'}.contains(grant['baseColor']) ||
          grant['grantedMs'] is! int || (grant['grantedMs'] as int) <= 0 ||
          !seen.add(id)) {
        throw const FormatException('profile-id-gift-proof');
      }
      if (acceptance != null) {
        if (acceptance is! Map || acceptance.length != 4 ||
            acceptance['uid'] != uid || acceptance['identifier'] != id ||
            acceptance['group'] != grant['group'] ||
            acceptance['receivedMs'] is! int ||
            (acceptance['receivedMs'] as int) < (grant['grantedMs'] as int)) {
          throw const FormatException('profile-id-acceptance-proof');
        }
        accepted.add(id);
      }
    }
    return Set.unmodifiable(accepted);
  }
  int get accountRevision => _source.account['revision'] as int;
  int get inventoryRevision => _source.inventory['revision'] as int;
  int get progressRevision => _source.progress['version'] as int;

  static DedaStage04ProfileView fromProtected(DedaStage03ProtectedSnapshot s) {
    final p = s.account['profile'] as Map;
    final color = p['fixedColor'];
    if (p['activeId'] == p['originalId']
        ? color != null
        : !const {'gold', 'diamond', 'royal', 'pink'}.contains(color)) {
      throw const FormatException('profile-id-color-inconsistent');
    }
    // Only a full accepted relationship involving this UID counts. Do not
    // substitute an empty list when a record is incomplete or duplicated.
    final peers = <String>{};
    var accepted = 0;
    for (final row in s.account['friends'] as List) {
      if (row is! Map) throw const FormatException('profile-invalid-friend');
      final a = row['requesterUid'], b = row['recipientUid'];
      final members = row['members'], status = row['status'];
      if (a is! String || b is! String || a.isEmpty || b.isEmpty ||
          a == b || (a != s.uid && b != s.uid) ||
          members is! List || members.length != 2 ||
          !members.contains(a) || !members.contains(b) ||
          !const {'pending','accepted','rejected'}.contains(status)) {
        throw const FormatException('profile-invalid-friend');
      }
      final pair = [a,b]..sort();
      if (row['pairKey'] != pair.join('__') ||
          !peers.add(a == s.uid ? b : a)) {
        throw const FormatException('profile-duplicate-or-invalid-friend');
      }
      if (status == 'accepted') accepted++;
    }
    final view = DedaStage04ProfileView._(s, accepted);
    if (view.activeId != view.originalId) {
      if (!view.acceptedGiftIds.contains(view.activeId)) {
        throw const FormatException('profile-active-id-unproven');
      }
      final row = view.identifierGiftRecords.singleWhere(
          (item) => (item as Map)['identifier'] == view.activeId) as Map;
      if ((row['grant'] as Map)['baseColor'] != view.fixedColor) {
        throw const FormatException('profile-active-id-color-unproven');
      }
    }
    return view;
  }
}


/// Name-only compare-and-set plan for the already tested candidate rules.
/// It cannot mint rights, replace a UID, or write by itself.
class DedaStage04NameChange {
  DedaStage04NameChange._(this.uid, this.revision, this.name, this.account);
  final String uid, name;
  final int revision;
  final Map<String, Object?> account;

  static DedaStage04NameChange prepare(DedaStage04ProfileView opening,
      DedaStage04ProfileView fresh, String name) {
    if (opening.uid != fresh.uid ||
        opening.accountRevision != fresh.accountRevision ||
        opening.displayName != fresh.displayName) {
      throw const DedaPrivateDataConflict();
    }
    if (name.runes.length < 2 || name.runes.length > 96 ||
        name != name.trim() || name.contains(RegExp(r'[<>\x00-\x1f]')) ||
        name == fresh.displayName ||
        fresh.accountRevision >= 9007199254740990) {
      throw const FormatException('profile-name-invalid-or-unchanged');
    }
    final next = <String,Object?>{
      ...fresh._source.account,
      'revision': fresh.accountRevision + 1,
      'profile': Map<String,Object?>.unmodifiable({
        ...Map<String,Object?>.from(fresh._profile),
        'displayName': name,
      }),
    };
    return DedaStage04NameChange._(fresh.uid, fresh.accountRevision+1, name,
        Map<String,Object?>.unmodifiable(next));
  }

  bool confirmedBy(DedaStage04ProfileView readback) =>
      readback.uid == uid && readback.accountRevision == revision &&
      readback.displayName == name;
}


/// Save coordination only: delegates to the existing guarded writers.
/// Separate results prevent an unconfirmed operation from being shown as
/// successful, and no rollback or automatic retry can overwrite another device.
enum DedaStage04SavePart { unchanged, confirmed, unconfirmed, notAttempted }
class DedaStage04ProfileSaveOutcome {
  const DedaStage04ProfileSaveOutcome(this.name, this.appearance);
  final DedaStage04SavePart name, appearance;
  bool get complete =>
      (name == DedaStage04SavePart.unchanged || name == DedaStage04SavePart.confirmed) &&
      (appearance == DedaStage04SavePart.unchanged || appearance == DedaStage04SavePart.confirmed);

  static Future<DedaStage04ProfileSaveOutcome> run({
    required bool nameChanged, required bool appearanceChanged,
    required Future<void> Function() saveName,
    required Future<bool> Function() saveAppearance,
  }) async {
    var name = DedaStage04SavePart.unchanged;
    var appearance = appearanceChanged
        ? DedaStage04SavePart.notAttempted : DedaStage04SavePart.unchanged;
    if (nameChanged) {
      try {
        await saveName();
        name = DedaStage04SavePart.confirmed;
      } catch (_) {
        return DedaStage04ProfileSaveOutcome(DedaStage04SavePart.unconfirmed, appearance);
      }
    }
    if (appearanceChanged) {
      try {
        appearance = await saveAppearance()
            ? DedaStage04SavePart.confirmed : DedaStage04SavePart.unconfirmed;
      } catch (_) {
        appearance = DedaStage04SavePart.unconfirmed;
      }
    }
    return DedaStage04ProfileSaveOutcome(name, appearance);
  }
}


/// Review-only contract for the missing, independently verified personal
/// wallet residuals. Not a balance writer, not a claim, and not a new ledger.
/// The existing progress balance is already net of verified spends.
class DedaStage04PersonalWallet {
  DedaStage04PersonalWallet._(this.earnedResidual,this.giftResidual,
      this.managerPersonal,this.hasManagerPersonal);
  final int earnedResidual, giftResidual, managerPersonal;
  final bool hasManagerPersonal;
  static const _max = 9007199254740990;
  int get visibleDiamonds => dedaProfileVisibleDiamonds(
      ordinaryEarnedAndGifted: earnedResidual + giftResidual,
      hasGeneralManagerPersonalWallet: hasManagerPersonal,
      generalManagerPersonal: managerPersonal);

  static DedaStage04PersonalWallet decodeForOpening(
      Map<String,Object?> row, DedaStage04ProfileView opening,
      DedaStage04ProfileView fresh) {
    if (opening.uid != fresh.uid || opening.originalId != fresh.originalId ||
        opening.progressRevision != fresh.progressRevision ||
        opening.inventoryRevision != fresh.inventoryRevision ||
        opening.accountRevision != fresh.accountRevision ||
        opening.earnedDiamonds != fresh.earnedDiamonds) {
      throw const DedaPrivateDataConflict();
    }
    return decode(row, fresh);
  }

  // Both source snapshots must be server-confirmed under the candidate
  // owner rules. A missing personal document is allowed only for a proven
  // ordinary account; a missing gift source never means zero.
  static DedaStage04PersonalWallet fromSources(
      DedaStage04ProfileView opening,DedaStage04ProfileView fresh,
      Map<String,dynamic>? gift,Map<String,dynamic>? personal) {
    if(gift==null || gift['publicId']!=fresh.originalId ||
        (gift.containsKey('ownerUid') && gift['ownerUid']!=fresh.uid) ||
        (personal!=null && personal['accountKey']!=fresh.uid)) {
      throw const FormatException('profile-wallet-source-unproven');
    }
    return decodeForOpening({'format':1,'uid':fresh.uid,'complete':true,
      'sourceKind':'synthetic-lab-wallet-v1','progressVersion':fresh.progressRevision,
      'inventoryRevision':fresh.inventoryRevision,'accountRevision':fresh.accountRevision,
      'originalId':fresh.originalId,'giftResidual':gift['balance'],
      'managerPersonal':personal==null?0:personal['balance'],
      'hasManagerPersonal':personal!=null},opening,fresh);
  }
  static DedaStage04PersonalWallet decode(Map<String,Object?> row,
      DedaStage04ProfileView profile) {
    const keys = {'format','uid','complete','sourceKind','progressVersion',
      'inventoryRevision','accountRevision','originalId','giftResidual','managerPersonal','hasManagerPersonal'};
    final gift = row['giftResidual'], manager = row['managerPersonal'],
        hasManager = row['hasManagerPersonal'];
    bool valid(Object? n) => n is int && n >= 0 && n <= _max;
    if (row.length != keys.length || !keys.every(row.containsKey) ||
        row['uid'] != profile.uid || row['format'] != 1 ||
        row['complete'] != true || row['sourceKind'] != 'synthetic-lab-wallet-v1' ||
        row['progressVersion'] != profile.progressRevision ||
        row['inventoryRevision'] != profile.inventoryRevision ||
        row['accountRevision'] != profile.accountRevision || row['originalId'] != profile.originalId ||
        !valid(gift) || !valid(manager) || hasManager is! bool ||
        (hasManager == false && manager != 0)) {
      throw const FormatException('profile-wallet-source-unproven');
    }
    final earned = profile.earnedDiamonds, g = gift as int, m = manager as int;
    if (g > _max-earned || m > _max-earned-g) {
      throw const FormatException('profile-wallet-overflow');
    }
    return DedaStage04PersonalWallet._(earned,g,m,hasManager);
  }
}

/// Direct store transaction rows for the SAME fixed synthetic UID and ID.
/// This is a proposed client transaction, not a new authority. Firestore
/// must independently validate all before/after values and the receipt ring.
class DedaStage04StoreDirectRows {
  // Derived from reconcile-core.eventKey for the pinned synthetic account.
  // Do not use these keys for any other account or production.
  static const eventKeys = <String,String>{
    'FRAME_03': '478bb61195f624d9a746f55f03ca6c7fea6eb344c67e4b37c65bc334d74553ae',
    'FRAME_05': '5bc1baa1e7e441c4f44ec76a264a7d218daae3cd99958e4c65f8318741c6f02e',
    'FRAME_06': 'd87072a4dc96d405e738233e1de537f4d51d26c71e7729f7d90ac911dab4bf00',
    'FRAME_07': '85be4f7bd2604a8e5438e1d0a2035e802606aab327cddfe8f7b5cd9abb97dfb1',
    'FRAME_08': '944eaa095143e78b8310811e71e9d299adb6b4b6223151d9c2e970b4061b4ef8',
    'FRAME_09': '8b256d01235f62a4a97e3904ebb050b4f8aa89909d628bd8452ab4bf94889c45',
    'FRAME_10': 'ffe84b71a449b5aaef715bcfc7cd18aeb1f837e86efc5b86017e9179da869d6f',
    'FRAME_11': 'a367ea5105b3451bf11b1557dd02b41fb22f800541b94b2be41c065813ec5742',
    'FRAME_12': 'e6ab6c62ed047273d3384717287450d6008010570536249480ea33a3bd47b32d',
    'FRAME_13': 'e446f01aaa4b3ef96396267a4be93feaed87faf006576fa054649632a384971e',
    'FRAME_14': '81c0446ffe14f621314dd23ee8430e08dcda4f37591ff370bd90a742b9d457f6',
    'FRAME_15': 'eb91f4940d8e414e66191b5da07b7d725871878193eb2bb3c93ad0bc61b372cf',
    'FRAME_16': 'aebde7783dde9b827e69dfcb7c00c828f08f365fbced2990d391f59a8b905b06',
  };

  static Map<String,Map<String,dynamic>> prepare({
    required DedaStage04ProfileView profile, required String frameId,
    required Map<String,dynamic> walletRow, required Map<String,dynamic> gift,
    required Map<String,dynamic>? personal, required Map<String,dynamic> native,
    required int createdMs,
  }) {
    final uid=profile.uid, original=profile.originalId, key=eventKeys[frameId];
    if(uid!=DedaStage02LabSingleUid.approvedUid || original!='@DEDA-QA1234' ||
        key==null || createdMs<=0 || profile.verifiedPaidFrameIds.contains(frameId) ||
        profile.inventoryRevision>=9007199254740990) {
      throw StateError('store-direct-synthetic-scope-held');
    }
    final wallet=DedaStage04PersonalWallet.decode(walletRow,profile);
    if(gift['publicId']!=original || gift['balance']!=wallet.giftResidual ||
       (gift.containsKey('ownerUid')&&gift['ownerUid']!=uid) ||
       wallet.hasManagerPersonal!=(personal!=null) ||
       (personal!=null&&(personal['accountKey']!=uid||personal['balance']!=wallet.managerPersonal))) {
      throw const DedaPrivateDataConflict();
    }
    final owned=native['ownedFrames'],pending=native['pendingFrames'];
    final verified=profile.verifiedPaidFrameIds;
    if(native['originalId']!=original || owned is! List || pending is! List ||
        pending.isNotEmpty || owned.length!=verified.length ||
        owned.toSet().length!=owned.length || !owned.every(verified.contains)) {
      throw StateError('store-native-proof-held');
    }
    if(wallet.hasManagerPersonal?wallet.managerPersonal<1000:
        wallet.earnedResidual+wallet.giftResidual<1000) {
      throw StateError('store-insufficient-diamonds');
    }
    final earned=wallet.hasManagerPersonal?0:min(1000,wallet.earnedResidual);
    final gifted=wallet.hasManagerPersonal?0:1000-earned;
    final manager=wallet.hasManagerPersonal?1000:0;
    if(earned>0&&profile.progressRevision>=9007199254740990) {
      throw const DedaPrivateDataConflict();
    }
    final root='deda_lab_uid_authority/$uid',
        revision=profile.inventoryRevision+1, progressVersion=profile.progressRevision+(earned>0?1:0);
    final now=Timestamp.fromMillisecondsSinceEpoch(createdMs);
    final frame=<String,dynamic>{'frameId':frameId,
      'receipt':{'uid':uid,'frameId':frameId,'kind':'lab_frame','cost':1000,'createdMs':createdMs},
      'ownership':{'uid':uid,'frameId':frameId,'receiptId':'${uid}_$frameId','createdMs':createdMs}};
    final frames=<Map>[...profile.frameRecords.cast<Map>(),frame]
      ..sort((a,b)=>(a['frameId'] as String).compareTo(b['frameId'] as String));
    final inventory=<String,dynamic>{...profile._source.inventory,'revision':revision,'frames':frames};
    final rows=<String,Map<String,dynamic>>{};
    if(earned>0){
      final balances=<String,dynamic>{...profile._balances,'earnedDiamonds':wallet.earnedResidual-earned};
      final receipt=<String,dynamic>{'format':1,'accountKey':uid,'source':'cosmetic-debit-v1',
        'sourceId':'stage04-store-frame|$original|$frameId','kind':'spend',
        'delta':{'points':0,'coins':0,'xp':0,'earnedDiamonds':-earned}};
      rows['$root/receipts/$key']=receipt;
      rows['$root/events/$key']={'format':1,'accountKey':uid,'eventKey':key,'receipt':receipt,
        'receiptId':key,'appliedVersion':progressVersion,'afterBalances':balances,'createdAt':now};
      rows[root]={...profile._source.progress,'version':progressVersion,'balances':balances};
    }
    if(gifted>0)rows['deda_diamond_gift_balances/$original']={...gift,'balance':wallet.giftResidual-gifted,'updatedAt':now};
    if(manager>0)rows['deda_gm_personal_diamond_wallets/$uid']={...personal!,'balance':wallet.managerPersonal-manager,'updatedAt':now};
    rows['deda_lab_frame_receipts/$original/frames/$frameId']={'publicId':original,
      'frameId':frameId,'kind':'lab_frame','cost':1000,'createdAt':now};
    rows['deda_lab_owned_frames/$original/frames/$frameId']={'publicId':original,
      'frameId':frameId,'receiptId':'${original}_$frameId','createdAt':now};
    rows['deda_native_account_cosmetics/$original']={...native,'ownedFrames':[...owned,frameId],'updatedAt':now};
    rows['$root/framePurchases/$frameId']={'format':1,'uid':uid,'originalId':original,'frameId':frameId,
      'cost':1000,'payment':{'earnedDiamonds':earned,'giftedDiamonds':gifted,'managerDiamonds':manager},
      'progressVersion':progressVersion,'eventKey':earned>0?key:null,'createdMs':createdMs};
    rows['$root/inventorySources/current']=inventory;
    rows['$root/inventory/current']=inventory;
    rows['$root/inventoryHistory/$revision']=inventory;
    rows['$root/wallet/current']={...walletRow,'progressVersion':progressVersion,'inventoryRevision':revision,
      'giftResidual':wallet.giftResidual-gifted,'managerPersonal':wallet.managerPersonal-manager};
    return rows;
  }
}

/// Exact synthetic campaign event identities, derived from the existing
/// reconcile-core eventKey. Not a new ledger or a real prize-code issuer.
class DedaStage04TierState {
  const DedaStage04TierState(this.reserved,this.claimed,{this.finalPoints});
  final Set<int> reserved, claimed;
  final int? finalPoints;
  // Fixed synthetic display reference, never a secret or real prize issuer.
  static String get syntheticPrizeCode => 'Q4'+key(25000,false).substring(0,14);
  String? codePart(int threshold) {
    final index=keys.keys.toList().indexOf(threshold);
    if(index<0 || !reserved.contains(threshold))return null;
    const starts=[0,3,6,9,12],ends=[3,6,9,12,16];
    return syntheticPrizeCode.substring(starts[index],ends[index]);
  }
  bool get prizeReady => reserved.length==5 && keys.keys.every(reserved.contains) &&
      claimed.length==4 && keys.keys.where((t)=>t!=25000).every(claimed.contains) &&
      finalPoints!=null && finalPoints!>=0;
  static int terminalPoints(Map<String,dynamic> marker,String uid,int version) {
    verifyMarker(marker,uid,25000,false,version);
    final b=marker['afterBalances'];
    if(b is! Map || b['points'] is! int || (b['points'] as int)<0 ||
        (b['points'] as int)>9007199254740990)throw const FormatException('point-tier-final-balance');
    return b['points'] as int;
  }
  static const keys = <int,(String,String?)>{
    5000: ('98b23cc67f5935396196b43e3d14a53df5f219d4500f604a7e441933b938c487', '82561d03bf50f6d1be2423cfd8a8ff7c4214ccbcf37beb094669cc7870cb6558'),
    10000: ('fbcac52e26c152299ad7a44db26ca4d84a834d009427500fe91c90072018d232', 'e1faec921eea72ebedb060eba865cb2e0d606a7ff286dc9ed0d14511205b4d35'),
    15000: ('982b842a04fb09bfc0783c4333464f5599afca103a36dc4f0a0fe70754a16f57', '094b51b881b8ca7060b28623da964af30c66f711c74159bf4175530611edb6b1'),
    20000: ('cd3b2ccc888e1a36fb7462f8267f3811a5363213edbd45db38dba84bf5728e9a', '2ae5367718616332d15dbca27a62ea3cce170044b5998a1b38b690d3c02b16fa'),
    25000: ('4741009ed027a9ad4ea139232be5c42841eea0ff1dbd5a7a3b96290dd664c579', null),
  };
  static String key(int threshold,bool claim) {
    final k=keys[threshold];
    if(k==null || (claim && k.$2==null)) throw const FormatException('point-tier-ineligible');
    return claim ? k.$2! : k.$1;
  }
  static Map<String,Object?> receipt(String uid,int threshold,bool claim) {
    key(threshold,claim);
    final reserveKey=key(threshold,false);
    return {'format':1,'accountKey':uid,'source':claim?'point-tier-return-v1':'point-reservation-v1',
      'sourceId':'stage04-synthetic-tier|$threshold'+(claim?'|$reserveKey':''),
      'kind':claim?'award':'spend','delta':{'points':claim?threshold+threshold~/100:-threshold,
        'coins':0,'xp':0,'earnedDiamonds':0}};
  }
  static void verifyMarker(Map<String,dynamic> marker,String uid,int threshold,bool claim,int version) {
    final k=key(threshold,claim),expected=receipt(uid,threshold,claim),r=marker['receipt'];
    if(marker['accountKey']!=uid || marker['format']!=1 || marker['eventKey']!=k ||
       marker['receiptId']!=k || marker['appliedVersion'] is! int ||
       (marker['appliedVersion'] as int)<2 || (marker['appliedVersion'] as int)>version ||
       r is! Map || r.length!=expected.length ||
       expected.keys.where((x)=>x!='delta').any((x)=>r[x]!=expected[x]) ||
       r['delta'] is! Map || (r['delta'] as Map).length!=4 ||
       (expected['delta'] as Map).keys.any((x)=>(r['delta'] as Map)[x]!=(expected['delta'] as Map)[x])) {
      throw const FormatException('point-tier-marker-invalid');
    }
  }
}

/// A view admitted only by the current lab session. The caller must use
/// requireCurrent at presentation and action boundaries, not retain an old
/// view across a session transition.
class DedaStage04ProfileRead {
  DedaStage04ProfileRead._(this._view, this._current);
  final DedaStage04ProfileView _view;
  final bool Function() _current;
  DedaStage04ProfileView requireCurrent() {
    if (!_current()) throw const DedaPrivateDataStale();
    return _view;
  }
}

/// 04/02: relationship presentation over the same protected account.
/// Both parties are Firebase UID keys; public identifiers are display data.
/// No directory discovery, notification, task award or relationship writer.
class DedaStage04FriendRow {
  const DedaStage04FriendRow._(this.ownerUid, this.pairKey, this.peerUid,
      this.peerPublicId, this.peerName, this.incoming, this.status, this.requestRevision);
  final String ownerUid, pairKey, peerUid, peerPublicId, peerName, status;
  final bool incoming;
  final int? requestRevision;
  String get notificationKey => '$pairKey:${requestRevision ?? "legacy"}';
}

/// Full account-scoped snapshot; do not replace missing fields with a
/// placeholder name, zero friends, or an identity inferred from an alias.
class DedaStage04FriendsView {
  DedaStage04FriendsView._(this.uid, this.originalId, this.revision, this.rows);
  final String uid, originalId;
  final int revision;
  final List<DedaStage04FriendRow> rows;
  List<DedaStage04FriendRow> get accepted =>
      List.unmodifiable(rows.where((r) => r.status == 'accepted'));
  List<DedaStage04FriendRow> get incomingRequests =>
      List.unmodifiable(rows.where((r) => r.status == 'pending' && r.incoming));
  List<DedaStage04FriendRow> get outgoingRequests =>
      List.unmodifiable(rows.where((r) => r.status == 'pending' && !r.incoming));

  /// A rendered row is not a permission. Require the current accepted
  /// canonical relationship and its display key before reading a preview.
  DedaStage04FriendRow requireAcceptedPeer(String pairKey, String peerPublicId) {
    final matches=accepted.where((r)=>r.pairKey==pairKey &&
        r.peerPublicId==peerPublicId);
    if(matches.length!=1)throw StateError('friends-preview-not-accepted');
    return matches.single;
  }

  /// Recheck after directory I/O. No old relationship or public-ID takeover
  /// may authorize a preview, even when the displayed ID is unchanged.
  void verifyPreview(DedaStage04FriendRow opening, String directoryUid,
      String directoryPublicId) {
    final current=requireAcceptedPeer(opening.pairKey,opening.peerPublicId);
    if(opening.ownerUid!=uid || opening.status!='accepted' ||
        opening.peerUid!=current.peerUid || directoryUid!=current.peerUid ||
        directoryPublicId!=current.peerPublicId) {
      throw StateError('friends-preview-owner-conflict');
    }
  }

  /// Prepare a command from the freshly verified account. The trusted
  /// worker must independently validate it; this never writes Firestore.
  Map<String,Object?> prepareAction(String action,String peerUid,String peerPublicId,
      {String? renderedEvent}) {
    if(!['send','accept','reject','remove'].contains(action) ||
        peerUid==uid || peerPublicId==originalId ||
        !RegExp(r'^[A-Za-z0-9_-]{6,128}$').hasMatch(peerUid) ||
        !RegExp(r'^@DEDA-[A-Z0-9]{6}$').hasMatch(peerPublicId))
      throw StateError('friends-action-invalid');
    final pair=[uid,peerUid]..sort();
    final pairKey=pair.join('__');
    final matches=rows.where((r)=>r.peerUid==peerUid || r.peerPublicId==peerPublicId).toList();
    if(matches.length>1 || (matches.isNotEmpty &&
        (matches.single.peerUid!=peerUid || matches.single.peerPublicId!=peerPublicId)))
      throw StateError('friends-action-peer-conflict');
    final row=matches.isEmpty?null:matches.single;
    if(action=='send') {
      if(row!=null && row.status!='rejected')throw StateError('friends-action-exists');
    } else {
      if(row==null || renderedEvent!=row.notificationKey)
        throw StateError('friends-action-stale-row');
      if(action=='remove' ? row.status!='accepted' : row.status!='pending' || !row.incoming)
        throw StateError('friends-action-not-authorized');
    }
    return Map<String,Object?>.unmodifiable({'format':1,'action':action,
      'peerUid':peerUid,'peerPublicId':peerPublicId,'pairKey':pairKey,
      'expectedRevision':revision,'requestRevision':row?.requestRevision});
  }

  static DedaStage04FriendsView fromProfile(DedaStage04ProfileView profile) {
    // The existing profile projection already checks owner participation,
    // canonical pair, unique peer and status. Enforce the complete trusted
    // parseAccount relationship schema before exposing names and public IDs.
    final raw = profile._source.account['friends'] as List;
    if (raw.length > 200) throw const FormatException('friends-source-limit');
    const fields = {'pairKey','members','requesterUid','recipientUid',
      'requesterPublicId','recipientPublicId','requesterName','recipientName','status'};
    bool member(Object? v) => v is String &&
        RegExp(r'^[A-Za-z0-9_-]{6,128}$').hasMatch(v);
    bool alias(Object? v) => v is String &&
        RegExp(r'^@DEDA-[A-Z0-9]{4,12}$').hasMatch(v);
    bool name(Object? v) => v is String && v.isNotEmpty && v.length <= 96 &&
        v.trim() == v && !RegExp(r'[<>\x00-\x1f]').hasMatch(v);
    final rows = <DedaStage04FriendRow>[];
    for (final value in raw) {
      if (value is! Map ||
          value.length != fields.length + (value.containsKey('requestRevision') ? 1 : 0) ||
          (value.containsKey('requestRevision') &&
            (value['requestRevision'] is! int || (value['requestRevision'] as int) < 1 ||
             (value['requestRevision'] as int) > profile.accountRevision)) ||
          !fields.every(value.containsKey) ||
          !member(value['requesterUid']) || !member(value['recipientUid']) ||
          !alias(value['requesterPublicId']) || !alias(value['recipientPublicId']) ||
          !name(value['requesterName']) || !name(value['recipientName'])) {
        throw const FormatException('friends-source-incomplete');
      }
      final incoming = value['recipientUid'] == profile.uid;
      final ownId = value[incoming ? 'recipientPublicId' : 'requesterPublicId'];
      final peerId = value[incoming ? 'requesterPublicId' : 'recipientPublicId'] as String;
      if (ownId != profile.originalId || peerId == profile.originalId ||
          peerId == profile.activeId) {
        throw const FormatException('friends-public-id-owner-conflict');
      }
      rows.add(DedaStage04FriendRow._(profile.uid, value['pairKey'] as String,
          value[incoming ? 'requesterUid' : 'recipientUid'] as String, peerId,
          value[incoming ? 'requesterName' : 'recipientName'] as String,
          incoming, value['status'] as String, value['requestRevision'] as int?));
    }
    final publicIds = <String>{};
    if (rows.any((r) => !publicIds.add(r.peerPublicId))) {
      throw const FormatException('friends-ambiguous-peer-public-id');
    }
    rows.sort((a,b) {
      final nameOrder = a.peerName.compareTo(b.peerName);
      return nameOrder != 0 ? nameOrder : a.pairKey.compareTo(b.pairKey);
    });
    final view = DedaStage04FriendsView._(profile.uid, profile.originalId,
        profile.accountRevision, List.unmodifiable(rows));
    if (view.accepted.length != profile.acceptedFriends) {
      throw const FormatException('friends-count-inconsistent');
    }
    return view;
  }
}

/// Keep the existing session-generation guard for every presentation read.
/// A fresh action must still obtain a fresh trusted relationship revision.
class DedaStage04FriendsRead {
  DedaStage04FriendsRead._(this._profile, this._friends);
  final DedaStage04ProfileRead _profile;
  final DedaStage04FriendsView _friends;
  DedaStage04ProfileView requireProfile() => _profile.requireCurrent();
  DedaStage04FriendsView requireCurrent() {
    _profile.requireCurrent();
    return _friends;
  }
}

/// 04/03: reuse the protected account as the sole owner-score authority.
/// Ranking additionally requires an independently complete server score set.
class DedaStage04LeagueRead {
  DedaStage04LeagueRead._(this._profile);
  final DedaStage04ProfileRead _profile;
  DedaStage04ProfileView requireCurrent()=>_profile.requireCurrent();
  static String day(DateTime utc)=>DedaWeeklyCommunityOutbox.baghdadDay(utc);
  static String weekId(DateTime utc)=>day(DedaWeeklyLeagueClock.at(utc).weekStart);

  /// Check claimed task evidence and all stored weekly records, including
  /// omission and duplicate keys. Unclaimed or frozen tasks never count.
  static Map<String,Set<String>> verifiedWeeks(DedaStage04ProfileView p) {
    final tasks=p._source.account['tasks'] as List, leagues=p._source.account['league'] as List;
    if(tasks.length>20000 || leagues.length>520)throw const FormatException('league-source-limit');
    final taskKeys=<String>{}, expected=<String,Set<String>>{};
    for(final r in tasks){
      if(r is! Map || r.length!=5 || !['claimKey','dayId','taskId','completedMs','claimedMs'].every(r.containsKey) ||
          r['dayId'] is! String || !DedaWeeklyCommunityOutbox.tasks.contains(r['taskId']) ||
          r['claimKey']!=r['dayId'].toString()+'|'+r['taskId'].toString() || r['completedMs'] is! int ||
          (r['completedMs'] as int)<=0 || !taskKeys.add(r['claimKey'] as String))
        throw const FormatException('league-task-proof');
      final completed=DateTime.fromMillisecondsSinceEpoch(r['completedMs'] as int,isUtc:true);
      if(day(completed)!=r['dayId'])throw const FormatException('league-task-day');
      final claimed=r['claimedMs'];
      if(claimed==null)continue;
      if(claimed is! int || claimed<(r['completedMs'] as int))
        throw const FormatException('league-claim-proof');
      final stamp=DateTime.fromMillisecondsSinceEpoch(claimed,isUtc:true);
      if(day(stamp)!=r['dayId'])throw const FormatException('league-claim-day');
      if(DedaWeeklyLeagueClock.at(stamp).canAccumulate){
        final keys=expected.putIfAbsent(weekId(stamp),()=> <String>{});
        keys.add(r['claimKey'] as String);
        if(keys.length>56)throw const FormatException('league-claim-limit');
      }
    }
    final actual=<String,Set<String>>{};
    for(final r in leagues){
      if(r is! Map || r.length!=4 || !['weekId','claimedKeys','completedTasks','weeklyXp'].every(r.containsKey) ||
          r['weekId'] is! String || r['claimedKeys'] is! List ||
          !(r['claimedKeys'] as List).every((v)=>v is String))
        throw const FormatException('league-week-proof');
      final id=r['weekId'] as String, values=(r['claimedKeys'] as List).cast<String>();
      final set=values.toSet();
      final date=DateTime.tryParse(id+'T03:00:00Z');
      if(date==null || !DedaWeeklyLeagueClock.at(date).canAccumulate || weekId(date)!=id ||
          DedaWeeklyLeagueClock.at(date).weekStart!=date || actual.containsKey(id) ||
          set.length!=values.length || set.length>56 ||
          r['completedTasks']!=set.length || r['weeklyXp']!=set.length*20 ||
          (expected[id]?.length??0)!=set.length ||
          !(expected[id]??<String>{}).containsAll(set))
        throw const FormatException('league-week-proof');
      actual[id]=Set.unmodifiable(set);
    }
    if(expected.keys.any((k)=>!actual.containsKey(k)))
      throw const FormatException('league-omitted-claims');
    return Map.unmodifiable(actual);
  }

  /// Match the original Hadaya receipt to the one protected weekly UID receipt.
  /// A display ID, score, cached card or planned amount is never claim proof.
  static Map<String,dynamic> verifyWeeklyGift(
      DedaStage04ProfileView profile, String giftId, Map<String,dynamic> gift) {
    final matching=<Map>[];
    for(final raw in profile.diamondGiftRecords){
      if(raw is! Map)throw const FormatException('league-gift-protected-row');
      if(raw['sourceType']!='weekly_league')continue;
      final week=raw['weekId'];
      if(week is! String || !RegExp(r'^20[0-9]{2}-[0-9]{2}-[0-9]{2}$').hasMatch(week) ||
          raw['uid']!=profile.uid || raw['giftId']!='deda-weekly-$week-${profile.uid}'){
        throw const FormatException('league-gift-protected-owner');
      }
      if(giftId=='deda-weekly-$week-${profile.originalId.substring(1)}')matching.add(raw);
    }
    if(matching.length!=1)throw StateError('league-gift-proof-missing-or-duplicate');
    final r=matching.single, created=gift['createdAt'], claimed=gift['claimedAt'];
    if(gift['giftId']!=giftId || gift['sourceType']!='weekly_league' ||
        gift['adminUid']!='deda-weekly-league-system' ||
        gift['targetPublicId']!=profile.originalId || r['amount'] is! int ||
        (r['amount'] as int)<=0 || (r['amount'] as int)>1000000 ||
        gift['amount']!=r['amount'] || gift['status']!=r['status'] ||
        created is! Timestamp || created.millisecondsSinceEpoch!=r['createdMs'] ||
        (r['status']=='pending' ? claimed!=null || r['receivedMs']!=null :
          r['status']!='received' || claimed is! Timestamp ||
          claimed.millisecondsSinceEpoch!=r['receivedMs'] ||
          claimed.millisecondsSinceEpoch<created.millisecondsSinceEpoch)){
      throw StateError('league-gift-original-receipt-conflict');
    }
    return Map<String,dynamic>.unmodifiable(gift);
  }

  Set<String> claims(String id)=>verifiedWeeks(requireCurrent())[id]??const <String>{};

  void verifyOwnerScore(String week,Map<String,dynamic>? score){
    validateOwnerScore(requireCurrent(),week,score);
  }
  static void validateOwnerScore(DedaStage04ProfileView p,String week,Map<String,dynamic>? score){
    final keys=verifiedWeeks(p)[week]??const <String>{};
    if(score==null){
      if(keys.isNotEmpty)throw StateError('league-owner-score-missing');
      return;
    }
    final raw=score['claimedKeys'];
    if(score['publicId']!=p.originalId || score['weekId']!=week ||
        raw is! List || !raw.every((v)=>v is String) ||
        raw.length!=keys.length || raw.toSet().length!=keys.length ||
        !keys.containsAll(raw.cast<String>()) ||
        score['completedTasks']!=keys.length || score['weeklyXp']!=keys.length*20)
      throw StateError('league-owner-score-conflict');
  }
  /// A complete server fixture must match every score document, not merely
  /// the viewer. No unproven empty set, omitted competitor or stale score.
  static Map<String,Map<String,dynamic>> verifyRankingProof(
      DedaStage04ProfileView p,String week,Map<String,dynamic>? proof,
      Map<String,Map<String,dynamic>> scores) {
    if(proof==null || proof.length!=7 || proof['format']!=1 ||
        proof['synthetic']!=true || proof['complete']!=true ||
        proof['ownerUid']!=p.uid || proof['weekId']!=week ||
        proof['accountRevision']!=p.accountRevision || proof['rows'] is! List ||
        (proof['rows'] as List).length!=scores.length || scores.length>2)
      throw StateError('league-fixture-completeness');
    final result=<String,Map<String,dynamic>>{};
    final start=DateTime.tryParse(week+'T03:00:00Z');
    if(start==null || weekId(start)!=week ||
        DedaWeeklyLeagueClock.at(start).weekStart!=start)
      throw StateError('league-fixture-week');
    for(final raw in proof['rows'] as List){
      if(raw is! Map || raw.length!=6 || !['publicId','ownerUid','activeId','displayName','claimedKeys','reachedMs'].every(raw.containsKey))
        throw StateError('league-fixture-row');
      final id=raw['publicId'], owner=raw['ownerUid'], active=raw['activeId'];
      if(id is! String || result.containsKey(id) ||
          !(id==p.originalId && owner==p.uid && active==p.activeId && raw['displayName']==p.displayName ||
            id=='@DEDA-QA5678' && owner=='synthetic-peer-001' && active==id) ||
          raw['displayName'] is! String || raw['claimedKeys'] is! List ||
          raw['reachedMs'] is! int)
        throw StateError('league-fixture-identity');
      final reached=DateTime.fromMillisecondsSinceEpoch(raw['reachedMs'] as int,isUtc:true);
      final keys=raw['claimedKeys'] as List;
      if(keys.isEmpty || keys.length>56 || keys.toSet().length!=keys.length ||
          weekId(reached)!=week || !DedaWeeklyLeagueClock.at(reached).canAccumulate ||
          !keys.every((k){
            if(k is! String)return false;
            final parts=k.split('|');
            if(parts.length!=2 || !DedaWeeklyCommunityOutbox.tasks.contains(parts[1]))return false;
            final d=DateTime.tryParse(parts[0]+'T09:00:00Z');
            return d!=null && day(d)==parts[0] && weekId(d)==week;
          }))throw StateError('league-fixture-receipts');
      final s=scores[id], sk=s?['claimedKeys'], at=s?['updatedAt'];
      if(s==null || s['weekId']!=week || s['publicId']!=id ||
          s['displayName']!=raw['displayName'] || sk is! List ||
          sk.length!=keys.length || sk.toSet().length!=keys.length ||
          !keys.toSet().containsAll(sk) || s['completedTasks']!=keys.length ||
          s['weeklyXp']!=keys.length*20 || at is! Timestamp ||
          at.millisecondsSinceEpoch!=raw['reachedMs'])
        throw StateError('league-fixture-score-conflict');
      result[id]=Map<String,dynamic>.unmodifiable(Map<String,dynamic>.from(raw));
    }
    validateOwnerScore(p,week,scores[p.originalId]);
    return Map.unmodifiable(result);
  }

  void verifyUnchanged(DedaStage04LeagueRead fresh){
    final a=requireCurrent(),b=fresh.requireCurrent();
    if(a.uid!=b.uid || a.accountRevision!=b.accountRevision ||
        a.originalId!=b.originalId || a.activeId!=b.activeId ||
        a.displayName!=b.displayName)throw const DedaPrivateDataConflict();
  }
}

/// The restored private revision used to open the existing profile editor.
/// A selection never confers an entitlement. The base is held for CAS.
class DedaStage04AppearanceRead {
  DedaStage04AppearanceRead._(this._profile, this._revision, this.selection);
  final DedaStage04ProfileRead _profile;
  final DedaPrivateDataRevision _revision;
  final DedaStage04Appearance? selection;
  int get privateVersion => _revision.version;
  String? get freeCardChoice {
    requireCurrent();
    final fields = _revision.payload!.fields;
    return fields.containsKey(DedaStage04FreeCardChoice.key)
        ? DedaStage04FreeCardChoice.decode(fields[DedaStage04FreeCardChoice.key]) : null;
  }
  DedaStage04ProfileView requireCurrent() => _profile.requireCurrent();
}

/// Original PlaceInfo-shaped private records; no local phone fallback.
/// Keep untouched serialized records byte-for-byte; identity is supplied
/// by the existing DedaPlacesStore.placeId at the original UI boundary.
class DedaStage04PlaceData {
  DedaStage04PlaceData._(this.revision, this.favorites, this.recent);
  final DedaPrivateDataRevision revision;
  final List<String> favorites, recent;

  static Map<String,dynamic> decodeRecord(String raw) {
    final row=jsonDecode(raw);
    if (row is! Map<String,dynamic>) throw const FormatException('profile-place-record');
    const fields={'name','type','lat','lon','address','phone','website','openingHours',
      'isDedaRegistered','isAvailableNow'};
    bool coordinate(Object? v,num min,num max) => v is num && v.isFinite && v>=min && v<=max;
    if (!row.keys.every(fields.contains) || row['name'] is! String ||
        (row['name'] as String).trim().isEmpty || row['type'] is! String ||
        (row['type'] as String).trim().isEmpty ||
        !coordinate(row['lat'],-90,90) || !coordinate(row['lon'],-180,180) ||
        ['address','phone','website','openingHours'].any((k)=>row[k]!=null && row[k] is! String) ||
        ['isDedaRegistered','isAvailableNow'].any((k)=>row.containsKey(k) && row[k] is! bool)) {
      throw const FormatException('profile-place-record');
    }
    return row;
  }

  static DedaStage04PlaceData fromRevision(DedaPrivateDataRevision revision,
      String Function(String) keyOf) {
    revision.validate();
    final fields=revision.payload?.fields;
    if (fields==null) throw StateError('profile-places-source-held');
    List<String> records(String key,int limit) {
      final raw=fields[key];
      if (raw is! List || raw.length>limit || !raw.every((v)=>v is String)) {
        throw const FormatException('profile-places-source-held');
      }
      final seen=<String>{}, rows=raw.cast<String>();
      for(final row in rows){
        decodeRecord(row);
        if(!seen.add(keyOf(row))) throw const FormatException('profile-place-duplicate');
      }
      return List<String>.unmodifiable(rows);
    }
    return DedaStage04PlaceData._(revision,records('favorites',100),records('recent',30));
  }

  /// Only a place already present in the opened account list can be edited.
  /// Explicit removal never toggles an absent favorite back on.
  DedaPrivateDataPayload prepare(String raw, {required String Function(String) keyOf,
      bool? favorite, bool recordRecent=false}) {
    if(favorite==null && !recordRecent) throw const FormatException('profile-place-no-action');
    decodeRecord(raw);
    if(!favorites.contains(raw) && !recent.contains(raw)) {
      throw const FormatException('profile-place-not-in-opening');
    }
    final id=keyOf(raw), f=List<String>.of(favorites), r=List<String>.of(recent);
    final wasFavorite=f.any((v)=>keyOf(v)==id);
    if(favorite==false && wasFavorite) f.removeWhere((v)=>keyOf(v)==id);
    if(favorite==true && !wasFavorite) {
      f.insert(0,raw);
      if(f.length>100) throw StateError('profile-favorites-limit');
    }
    if(recordRecent){
      r.removeWhere((v)=>keyOf(v)==id);
      r.insert(0,raw);
      if(r.length>30) r.removeRange(30,r.length);
    }
    return DedaPrivateDataPayload({...revision.payload!.fields,'favorites':f,'recent':r},
      uidScoped:true);
  }
}

class DedaStage04PlacesRead {
  DedaStage04PlacesRead._(this._profile,this._data);
  final DedaStage04ProfileRead _profile;
  final DedaStage04PlaceData _data;
  DedaStage04PlaceData requireCurrent() {
    _profile.requireCurrent();
    return _data;
  }
}

/// Lab only, default off. No legacy account/phone/ID routing, no wallet,
/// rewards, role, ownership or authoritative score writes from this class.
/// Existing DedaPrivateDataSync provides revision and journal coordination.
class DedaStage03LabStorage implements DedaPrivateDataIo {
  DedaStage03LabStorage._();
  static const enabled = bool.fromEnvironment('DEDA_STAGE03_LAB_STORAGE');
  static const uid = DedaStage02LabSingleUid.approvedUid;
  static final _io = DedaStage03LabStorage._();
  static final _sync = DedaPrivateDataSync.uidScoped(_io);

  static bool _matches() {
    try {
      return enabled && DedaStage02LabSingleUid.inspect(expectedUid: uid) == uid;
    } catch (_) { return false; }
  }
  static bool Function() _intent() {
    if (!_matches()) throw StateError('stage03-lab-identity-required');
    final snapshot = DedaAuthRuntime.capture();
    return () {
      try {
        return _matches() && snapshot != null &&
            snapshot.matches(DedaAuthRuntime.capture()!);
      } catch (_) { return false; }
    };
  }

  static Future<DedaPrivateDataResult> backup(DedaPrivateDataPayload payload) =>
      _sync.backup(account: uid, original: uid, payload: payload, isCurrent: _intent());
  static Future<DedaPrivateDataResult> restore() =>
      _sync.restore(account: uid, original: uid, isCurrent: _intent());

  /// Server transaction reads all protected views under the same UID.
  /// No write, no partial or cached fallback if a source is unavailable.
  static Future<DedaStage03ProtectedSnapshot> readProtected() async {
    final current = _intent();
    void check() {
      if (!current()) throw const DedaPrivateDataStale();
      _io._check(uid, uid);
    }
    await _io.verifyOwner(uid, uid, check);
    check();
    final db = FirebaseFirestore.instanceFor(app: Firebase.app());
    final base = db.doc('deda_lab_uid_authority/$uid');
    final result = await db.runTransaction<DedaStage03ProtectedSnapshot>((tx) async {
      check();
      final p = await tx.get(base);
      check();
      final i = await tx.get(base.collection('inventory').doc('current'));
      check();
      final a = await tx.get(base.collection('account').doc('current'));
      check();
      for (final row in [p,i,a]) {
        if (!row.exists || row.metadata.isFromCache || row.metadata.hasPendingWrites) {
          throw StateError('protected-server-source-required');
        }
      }
      return DedaStage03ProtectedSnapshot.decode(expectedUid: uid,
          progress: p.data(), inventory: i.data(), account: a.data());
    }, timeout: const Duration(seconds: 15));
    check();
    return result;
  }

  /// Stage 04/01 read binding, using the one existing session and storage
  /// transaction. No new collection, notifier, write or implicit login.
  static Future<DedaStage04ProfileRead> readProfile() async {
    final current = _intent();
    final protected = await readProtected();
    if (!current()) throw const DedaPrivateDataStale();
    final view = DedaStage04ProfileView.fromProtected(protected);
    if (!current()) throw const DedaPrivateDataStale();
    return DedaStage04ProfileRead._(view, current);
  }


  /// 04/02 reads the exact existing account projection. No separate
  /// collection, public-ID login, listener that leaks an old UID, or write.
  static Future<DedaStage04FriendsRead> readFriends() async {
    final profile = await readProfile();
    final friends = DedaStage04FriendsView.fromProfile(profile.requireCurrent());
    profile.requireCurrent();
    return DedaStage04FriendsRead._(profile, friends);
  }

  /// Exact one-owner synthetic candidate. No production or general client
  /// authority. The emulator-tested candidate rules are separately required.
  static const friendActionsCandidateEnabled =
      bool.fromEnvironment('DEDA_STAGE04_FRIEND_ACTIONS_CANDIDATE');

  static Future<String> performFriendCandidate(String action,String peerUid,
      String peerPublicId,{String? renderedEvent}) async {
    if(!friendActionsCandidateEnabled || peerUid!='synthetic-peer-001' ||
        peerPublicId!='@DEDA-QA5678')throw StateError('friends-lab-authority-held');
    final opening=await readFriends(), current=_intent();
    final view=opening.requireCurrent();
    final cmd=view.prepareAction(action,peerUid,peerPublicId,renderedEvent:renderedEvent);
    final pair=cmd['pairKey'] as String;
    void check(){
      if(!current())throw const DedaPrivateDataStale();
      opening.requireCurrent();_io._check(uid,uid);
    }
    await _io.verifyOwner(uid,uid,check);
    final db=FirebaseFirestore.instanceFor(app:Firebase.app());
    final base=db.doc('deda_lab_uid_authority/$uid');
    final account=base.collection('account').doc('current');
    final graph=db.collection('deda_friendships').doc(pair);
    await db.runTransaction<void>((tx) async {
      check();
      final a=await tx.get(account),g=await tx.get(graph);
      final p=await tx.get(db.collection('deda_social_profiles').doc(peerPublicId));
      final r=await tx.get(db.collection('deda_share_ids').doc(peerPublicId));
      check();
      for(final s in [a,g,p,r]){
        if(s.metadata.isFromCache || s.metadata.hasPendingWrites)
          throw const DedaPrivateDataConflict();
      }
      final old=a.data(), peer=p.data(), route=r.data();
      if(old==null || old['revision']!=cmd['expectedRevision'] ||
          old['uid']!=uid || old['friends'] is! List ||
          (old['friends'] as List).length>1 || view.originalId!='@DEDA-QA1234' ||
          peer==null || peer['ownerUid']!=peerUid || peer['publicId']!=peerPublicId ||
          peer['displayName'] is! String || route==null || route['ownerUid']!=peerUid ||
          route['publicId']!=peerPublicId || route['kind']!='personal' || route['active']!=true)
        throw const DedaPrivateDataConflict();
      final rows=old['friends'] as List;
      final previous=rows.isEmpty?null:Map<String,dynamic>.from(rows.single as Map);
      if(previous!=null && previous['pairKey']!=pair)
        throw const DedaPrivateDataConflict();
      // Rules repeat full equality to the graph and immutable history.
      if(g.exists!=(previous!=null) || previous?['requestRevision']!=cmd['requestRevision'])
        throw const DedaPrivateDataConflict();
      final revision=view.revision+1;
      Map<String,dynamic>? nextRow;
      if(action=='send'){
        nextRow={'pairKey':pair,'members':[uid,peerUid],'requesterUid':uid,
          'recipientUid':peerUid,'requesterPublicId':view.originalId,
          'recipientPublicId':peerPublicId,'requesterName':opening.requireProfile().displayName,
          'recipientName':peer['displayName'],'status':'pending','requestRevision':revision};
      }else if(action!='remove'){
        nextRow={...previous!,'status':action=='accept'?'accepted':'rejected'};
      }
      final next={...old,'revision':revision,'friends':nextRow==null?[]:[nextRow]};
      check();
      tx.set(account,next);
      tx.set(base.collection('accountSources').doc('current'),next);
      tx.set(base.collection('accountHistory').doc('$revision'),next);
      if(nextRow==null){tx.delete(graph);}else{tx.set(graph,nextRow);}
    },timeout:const Duration(seconds:15));
    check();
    final fresh=await readFriends();check();
    if(fresh.requireCurrent().revision<=view.revision)throw const DedaPrivateDataConflict();
    return pair;
  }

  static const leagueLabMode=bool.fromEnvironment('DEDA_STAGE04_LEAGUE_LAB');
  static String leagueAccountKey()=>leagueLabMode && _matches()?uid:'';

  static Future<DedaStage04LeagueRead> readLeague() async {
    if(!leagueLabMode)throw StateError('league-lab-disabled');
    final p=await readProfile();
    DedaStage04LeagueRead.verifiedWeeks(p.requireCurrent());
    return DedaStage04LeagueRead._(p);
  }

  // Candidate only; default closed. No change to financial rules or issuer.
  static const leagueGiftClaimCandidateEnabled =
      bool.fromEnvironment('DEDA_STAGE04_LEAGUE_GIFT_CLAIM_CANDIDATE');

  /// Original gift list, scoped to the protected original ID, never a phone
  /// alias. A weekly row must have both the original receipt and UID proof.
  static Stream<List<Map<String,dynamic>>> watchLeagueGiftCandidate(String originalId) async* {
    if(!leagueLabMode)throw StateError('league-lab-disabled');
    final opening=await readProfile(), p=opening.requireCurrent();
    if(originalId!=p.originalId)throw StateError('league-gift-owner-required');
    final db=FirebaseFirestore.instanceFor(app:Firebase.app());
    await for(final snap in db.collection('deda_diamond_gifts')
        .where('targetPublicId',isEqualTo:originalId)
        .snapshots(includeMetadataChanges:true)){
      opening.requireCurrent();
      if(snap.metadata.isFromCache || snap.metadata.hasPendingWrites)continue;
      final current=await readProfile(), fresh=current.requireCurrent();
      opening.requireCurrent();
      if(fresh.uid!=p.uid || fresh.originalId!=originalId)throw const DedaPrivateDataStale();
      final rows=<Map<String,dynamic>>[], seen=<String>{};
      for(final row in snap.docs){
        final data=row.data();
        if(data['giftId']!=row.id || data['targetPublicId']!=originalId || !seen.add(row.id)){
          throw StateError('league-gift-row-conflict');
        }
        rows.add(data['sourceType']=='weekly_league'
            ? DedaStage04LeagueRead.verifyWeeklyGift(fresh,row.id,data)
            : Map<String,dynamic>.unmodifiable(data));
      }
      for(final raw in fresh.diamondGiftRecords){
        if(raw is! Map)throw const FormatException('league-gift-protected-row');
        if(raw['sourceType']=='weekly_league' &&
            !seen.contains('deda-weekly-${raw['weekId']}-${originalId.substring(1)}')){
          throw StateError('league-gift-original-receipt-missing');
        }
      }
      rows.sort((a,b){
        final x=a['createdAt'], y=b['createdAt'];
        return (y is Timestamp?y.millisecondsSinceEpoch:0)
            .compareTo(x is Timestamp?x.millisecondsSinceEpoch:0);
      });
      current.requireCurrent();opening.requireCurrent();
      yield List.unmodifiable(rows);
    }
  }

  static Future<DedaStage04ProfileRead> openLeagueGiftClaim(String originalId) async {
    if(!leagueLabMode || !leagueGiftClaimCandidateEnabled)
      throw StateError('league-gift-claim-held');
    final read=await readProfile();
    if(read.requireCurrent().originalId!=originalId)
      throw StateError('league-gift-owner-required');
    return read;
  }

  /// Called inside the EXISTING claim transaction before any wallet write.
  /// Verify the same protected account and inventory revisions on each retry.
  static Future<void> verifyLeagueGiftClaim(
      Transaction tx,FirebaseFirestore db,DedaStage04ProfileRead opening,
      String originalId,String giftId,Map<String,dynamic> gift) async {
    final old=opening.requireCurrent();
    if(!leagueLabMode || !leagueGiftClaimCandidateEnabled ||
        old.originalId!=originalId || gift['status']!='pending')
      throw StateError('league-gift-claim-held');
    final base=db.doc('deda_lab_uid_authority/$uid');
    final account=await tx.get(base.collection('account').doc('current'));
    final inventory=await tx.get(base.collection('inventory').doc('current'));
    opening.requireCurrent();
    if(!account.exists || !inventory.exists || account.metadata.isFromCache ||
        inventory.metadata.isFromCache || account.metadata.hasPendingWrites ||
        inventory.metadata.hasPendingWrites)throw const DedaPrivateDataConflict();
    final fresh=DedaStage04ProfileView.fromProtected(DedaStage03ProtectedSnapshot.decode(
      expectedUid:uid,progress:old._source.progress,account:account.data(),inventory:inventory.data()));
    if(fresh.originalId!=originalId || fresh.accountRevision!=old.accountRevision ||
        fresh.inventoryRevision!=old.inventoryRevision)throw const DedaPrivateDataConflict();
    DedaStage04LeagueRead.verifyWeeklyGift(fresh,giftId,gift);
    opening.requireCurrent();
  }

  /// Confirm existing evidence only; no legacy phone journal or XP issuance.
  static Future<bool> confirmLeagueClaim(String key,String taskId) async {
    if(!leagueLabMode || key!=leagueAccountKey())return false;
    try{
      final now=DateTime.now().toUtc(), clock=DedaWeeklyLeagueClock.at(now);
      if(!clock.canAccumulate)return false;
      final read=await readLeague(),live=DateTime.now().toUtc();
      return DedaWeeklyLeagueClock.at(live).canAccumulate &&
          DedaStage04LeagueRead.weekId(live)==DedaStage04LeagueRead.weekId(now) &&
          DedaStage04LeagueRead.day(live)==DedaStage04LeagueRead.day(now) &&
          read.claims(DedaStage04LeagueRead.weekId(now))
            .contains(DedaStage04LeagueRead.day(now)+'|'+taskId);
    }catch(_){return false;}
  }

  /// Direct read-only residual sources in the unpublished synthetic candidate.
  /// No wallet issuance or writes; default closed.
  static const walletCandidateEnabled =
      bool.fromEnvironment('DEDA_STAGE04_PROFILE_WALLET_CANDIDATE');

  /// Read the candidate view and the three protected documents in one
  /// transaction, never substituting a phone balance or historical gifts.
  /// The opening view must still match. No wallet mutation or permission grant.
  static Future<DedaStage04PersonalWallet> readWalletCandidate(
      DedaStage04ProfileRead opening) async {
    if (!walletCandidateEnabled) {
      throw StateError('profile-wallet-candidate-disabled');
    }
    final current = _intent();
    final old = opening.requireCurrent();
    void check() {
      if (!current()) throw const DedaPrivateDataStale();
      opening.requireCurrent();
      _io._check(uid, uid);
    }
    await _io.verifyOwner(uid, uid, check);
    check();
    final db = FirebaseFirestore.instanceFor(app: Firebase.app());
    final base = db.doc('deda_lab_uid_authority/$uid');
    final result = await db.runTransaction<DedaStage04PersonalWallet>((tx) async {
      check();
      final p = await tx.get(base);
      final i = await tx.get(base.collection('inventory').doc('current'));
      final a = await tx.get(base.collection('account').doc('current'));
      final gift=await tx.get(db.collection('deda_diamond_gift_balances').doc(old.originalId));
      final personal=await tx.get(db.collection('deda_gm_personal_diamond_wallets').doc(uid));
      check();
      if(gift.metadata.isFromCache || gift.metadata.hasPendingWrites ||
          personal.metadata.isFromCache || personal.metadata.hasPendingWrites) {
        throw const DedaPrivateDataConflict();
      }
      for (final row in [p,i,a]) {
        if (!row.exists || row.metadata.isFromCache || row.metadata.hasPendingWrites) {
          throw StateError('profile-wallet-server-source-required');
        }
      }
      final fresh = DedaStage04ProfileView.fromProtected(
          DedaStage03ProtectedSnapshot.decode(expectedUid: uid,
            progress: p.data(), inventory: i.data(), account: a.data()));
      return DedaStage04PersonalWallet.fromSources(old,fresh,gift.data(),personal.data());
    }, timeout: const Duration(seconds: 15));
    check();
    return result;
  }

  /// Default-off, exact synthetic lab candidate. Requires the separately
  /// emulator-tested Spark rules; never publish those rules to production.
  static const actionsCandidateEnabled =
      bool.fromEnvironment('DEDA_STAGE04_PROFILE_ACTIONS_CANDIDATE');

  static Future<DedaStage04TierState> readPointTierCandidate(
      DedaStage04ProfileRead opening) async {
    if (!actionsCandidateEnabled) throw StateError('profile-actions-disabled');
    final old=opening.requireCurrent(), current=_intent();
    void check(){if(!current())throw const DedaPrivateDataStale();opening.requireCurrent();_io._check(uid,uid);}
    await _io.verifyOwner(uid,uid,check);
    final db=FirebaseFirestore.instanceFor(app:Firebase.app());
    final base=db.doc('deda_lab_uid_authority/$uid');
    final result=await db.runTransaction<DedaStage04TierState>((tx) async {
      check();
      final p=await tx.get(base);
      if(!p.exists || p.metadata.isFromCache || p.metadata.hasPendingWrites ||
         p.data()?['version']!=old.progressRevision)throw const DedaPrivateDataConflict();
      final reserved=<int>{},claimed=<int>{};
      int? previous, finalPoints;
      for(final t in DedaStage04TierState.keys.keys){
        for(final claim in [false,true]){
          if(claim && t==25000)continue;
          final s=await tx.get(base.collection('events').doc(DedaStage04TierState.key(t,claim)));
          check();
          if(s.metadata.isFromCache || s.metadata.hasPendingWrites)throw const DedaPrivateDataConflict();
          if(s.exists){
            DedaStage04TierState.verifyMarker(s.data()!,uid,t,claim,old.progressRevision);
            if(claim && !reserved.contains(t) || !claim && previous!=null && !claimed.contains(previous)) {
              throw const FormatException('point-tier-sequence-invalid');
            }
            if(t==25000)finalPoints=DedaStage04TierState.terminalPoints(s.data()!,uid,old.progressRevision);
            (claim?claimed:reserved).add(t);
          }
        }
        previous=t;
      }
      return DedaStage04TierState(Set.unmodifiable(reserved),Set.unmodifiable(claimed),finalPoints:finalPoints);
    });
    check();return result;
  }

  static Future<void> performPointTierCandidate(DedaStage04ProfileRead opening,int threshold,bool claim) async {
    if (!actionsCandidateEnabled) throw StateError('profile-actions-disabled');
    final old=opening.requireCurrent(),current=_intent();
    final k=DedaStage04TierState.key(threshold,claim),r=DedaStage04TierState.receipt(uid,threshold,claim);
    void check(){if(!current())throw const DedaPrivateDataStale();opening.requireCurrent();_io._check(uid,uid);}
    await _io.verifyOwner(uid,uid,check);
    final db=FirebaseFirestore.instanceFor(app:Firebase.app()), base=db.doc('deda_lab_uid_authority/$uid');
    final ref=base.collection('events').doc(k);
    await db.runTransaction<void>((tx) async {
      check();
      final p=await tx.get(base), e=await tx.get(ref);
      check();
      if(!p.exists || p.metadata.isFromCache || p.metadata.hasPendingWrites ||
          e.metadata.isFromCache || e.metadata.hasPendingWrites ||
          p.data()?['version']!=old.progressRevision || e.exists)throw const DedaPrivateDataConflict();
      final data=p.data()!, balances=Map<String,dynamic>.from(data['balances'] as Map);
      final delta=(r['delta'] as Map)['points'] as int;
      final nextPoints=(balances['points'] as int)+delta;
      if(nextPoints<0 || nextPoints>9007199254740990)throw const DedaPrivateDataConflict();
      final nextVersion=old.progressRevision+1;
      balances['points']=nextPoints;
      tx.set(base,{...data,'version':nextVersion,'balances':balances});
      tx.set(base.collection('receipts').doc(k),Map<String,dynamic>.from(r));
      tx.set(ref,{'format':1,'accountKey':uid,'eventKey':k,'receipt':r,'receiptId':k,
        'appliedVersion':nextVersion,'afterBalances':balances,'createdAt':FieldValue.serverTimestamp()});
    });
    check();
    final fresh=await readProfile();
    final history=await readPointTierCandidate(fresh);
    check();
    if(!(claim?history.claimed:history.reserved).contains(threshold))throw const DedaPrivateDataConflict();
  }

  // Fixed candidate only; no phone route, admin reply or payout.
  static DocumentReference<Map<String,dynamic>> _prizeRef(FirebaseFirestore db) =>
      db.collection('prize_winner_requests').doc('prize_v1_$uid');
  static Map<String,dynamic>? _readPrizeRow(DocumentSnapshot<Map<String,dynamic>> row) {
    if(row.metadata.isFromCache || row.metadata.hasPendingWrites)throw const DedaPrivateDataConflict();
    if(!row.exists)return null;
    final d=row.data()!;
    if(d['ownerUid']!=uid || d['accountKey']!=uid || d['cycleId']!='prize_v1' ||
        d['rewardCode']!=DedaStage04TierState.syntheticPrizeCode ||
        !const {'new','reviewing','needs_info','approved','prize_sent','rejected','delivered'}.contains(d['status']) ||
        d['phone']!='' || d['finalReservedPoints']!=25000 ||
        d['adminMessage'] is! String || d['prizeDetails'] is! String || d['userReply'] is! String ||
        (const {'prize_sent','delivered'}.contains(d['status']) && (d['prizeDetails'] as String).isEmpty)) {
      throw const FormatException('profile-prize-request-unproven');
    }
    return d;
  }
  static Stream<Map<String,dynamic>?> watchPrizeCandidate(DedaStage04ProfileRead opening) =>
      Stream<Map<String,dynamic>?>.multi((controller) {
        // Every attachment re-verifies its owner and server state, including
        // a card flipped away and then back. Cancel the old listener.
        final subscription=_watchPrizeCandidate(opening).listen(
          controller.add,onError:controller.addError,onDone:controller.close);
        controller.onCancel=subscription.cancel;
      },isBroadcast:true);
  static Stream<Map<String,dynamic>?> _watchPrizeCandidate(DedaStage04ProfileRead opening) async* {
    if(!actionsCandidateEnabled)throw StateError('profile-actions-disabled');
    final current=_intent();
    void check(){if(!current())throw const DedaPrivateDataStale();opening.requireCurrent();_io._check(uid,uid);}
    await _io.verifyOwner(uid,uid,check);
    final tiers=await readPointTierCandidate(opening);
    if(!tiers.prizeReady)throw const DedaPrivateDataConflict();
    final db=FirebaseFirestore.instanceFor(app:Firebase.app());
    bool confirmed=false;
    await for(final row in _prizeRef(db).snapshots(includeMetadataChanges:true)){
      check();
      if(row.metadata.hasPendingWrites)continue;
      if(row.metadata.isFromCache){
        if(confirmed)throw const DedaPrivateDataConflict();
        continue;
      }
      final data=_readPrizeRow(row);
      if(data!=null && data['pointsAtCompletion']!=tiers.finalPoints)throw const DedaPrivateDataConflict();
      confirmed=true;
      yield data;
    }
  }
  static Future<void> submitPrizeCandidate(DedaStage04ProfileRead opening) async {
    if(!actionsCandidateEnabled)throw StateError('profile-actions-disabled');
    final current=_intent();
    void check(){if(!current())throw const DedaPrivateDataStale();opening.requireCurrent();_io._check(uid,uid);}
    await _io.verifyOwner(uid,uid,check);
    final fresh=await readProfile(),view=fresh.requireCurrent();
    final tiers=await readPointTierCandidate(fresh);
    if(!tiers.prizeReady)throw const DedaPrivateDataConflict();
    final db=FirebaseFirestore.instanceFor(app:Firebase.app()),base=db.doc('deda_lab_uid_authority/$uid');
    final ref=_prizeRef(db);
    await db.runTransaction<void>((tx) async {
      check();
      final old=await tx.get(ref);
      final a=await tx.get(base.collection('account').doc('current'));
      final finalEvent=await tx.get(base.collection('events').doc(DedaStage04TierState.key(25000,false)));
      check();
      if(!a.exists || a.metadata.isFromCache || a.metadata.hasPendingWrites ||
          a.data()?['revision']!=view.accountRevision || !finalEvent.exists ||
          finalEvent.metadata.isFromCache || finalEvent.metadata.hasPendingWrites ||
          DedaStage04TierState.terminalPoints(finalEvent.data()!,uid,view.progressRevision)!=tiers.finalPoints) {
        throw const DedaPrivateDataConflict();
      }
      final existing=_readPrizeRow(old);
      if(existing!=null){
        if(existing['pointsAtCompletion']!=tiers.finalPoints)throw const DedaPrivateDataConflict();
        return;
      }
      tx.set(ref,{'ownerUid':uid,'cycleId':'prize_v1','accountKey':uid,
        'name':view.displayName,'phone':'','dedaId':view.originalId,
        'rewardCode':DedaStage04TierState.syntheticPrizeCode,'pointsAtCompletion':tiers.finalPoints,
        'completedThresholds':[5000,10000,15000,20000,25000],'finalReservedPoints':25000,
        'status':'new','adminMessage':'','prizeDetails':'','userReply':'',
        'createdAt':FieldValue.serverTimestamp(),'updatedAt':FieldValue.serverTimestamp()});
    });
    check();
    final saved=_readPrizeRow(await ref.get(const GetOptions(source:Source.server)));
    check();
    if(saved==null || saved['pointsAtCompletion']!=tiers.finalPoints)throw const DedaPrivateDataConflict();
  }

  static Future<void> replyPrizeCandidate(DedaStage04ProfileRead opening,String message) =>
      _updatePrizeCandidate(opening,message:message);
  static Future<void> confirmPrizeCandidate(DedaStage04ProfileRead opening) =>
      _updatePrizeCandidate(opening);
  static Future<void> _updatePrizeCandidate(DedaStage04ProfileRead opening,{String? message}) async {
    if(!actionsCandidateEnabled)throw StateError('profile-actions-disabled');
    final current=_intent();
    void check(){if(!current())throw const DedaPrivateDataStale();opening.requireCurrent();_io._check(uid,uid);}
    await _io.verifyOwner(uid,uid,check);
    final fresh=await readProfile(),tiers=await readPointTierCandidate(fresh);
    if(!tiers.prizeReady)throw const DedaPrivateDataConflict();
    final reply=message?.trim(), target=message==null?'delivered':'reviewing';
    if(reply!=null && (reply.isEmpty || reply.length>600))throw const FormatException('profile-prize-reply-invalid');
    final db=FirebaseFirestore.instanceFor(app:Firebase.app()),ref=_prizeRef(db);
    await db.runTransaction<void>((tx) async {
      check();
      final row=_readPrizeRow(await tx.get(ref));check();
      if(row==null || row['pointsAtCompletion']!=tiers.finalPoints)throw const DedaPrivateDataConflict();
      if(row['status']==target && (reply==null || row['userReply']==reply))return;
      if(row['status']!=(reply==null?'prize_sent':'needs_info'))throw const DedaPrivateDataConflict();
      tx.update(ref,{'status':target,'updatedAt':FieldValue.serverTimestamp(),
        if(reply!=null)...{'userReply':reply,'userReplyAt':FieldValue.serverTimestamp()}
        else ...{'winnerConfirmedAt':FieldValue.serverTimestamp(),'deliveredAt':FieldValue.serverTimestamp()}});
    });
    check();
    final saved=_readPrizeRow(await ref.get(const GetOptions(source:Source.server)));check();
    if(saved==null || saved['status']!=target || saved['pointsAtCompletion']!=tiers.finalPoints ||
        (reply!=null && saved['userReply']!=reply))throw const DedaPrivateDataConflict();
  }

  /// Atomic owner selection, account history and existing public directory.
  /// Rules independently repeat proof of the fixed accepted lab gift.
  static Future<DedaStage04ProfileRead> useIdentifierCandidate(DedaStage04ProfileRead opening,String id) async {
    if(!actionsCandidateEnabled)throw StateError('profile-actions-disabled');
    final old=opening.requireCurrent(),current=_intent();
    void check(){if(!current())throw const DedaPrivateDataStale();opening.requireCurrent();_io._check(uid,uid);}
    await _io.verifyOwner(uid,uid,check);
    final db=FirebaseFirestore.instanceFor(app:Firebase.app()),base=db.doc('deda_lab_uid_authority/$uid');
    final aRef=base.collection('account').doc('current');
    await db.runTransaction<void>((tx) async {
      check();
      final p=await tx.get(base),i=await tx.get(base.collection('inventory').doc('current')),a=await tx.get(aRef);
      check();
      for(final row in [p,i,a]){
        if(!row.exists || row.metadata.isFromCache || row.metadata.hasPendingWrites)throw const DedaPrivateDataConflict();
      }
      final fresh=DedaStage04ProfileView.fromProtected(DedaStage03ProtectedSnapshot.decode(
        expectedUid:uid,progress:p.data(),inventory:i.data(),account:a.data()));
      if(fresh.accountRevision!=old.accountRevision || fresh.inventoryRevision!=old.inventoryRevision ||
         fresh.originalId!=old.originalId || id==fresh.activeId)throw const DedaPrivateDataConflict();
      String? color;
      if(id!=fresh.originalId){
        if(!fresh.acceptedGiftIds.contains(id))throw const FormatException('profile-id-not-owned');
        final g=fresh.identifierGiftRecords.singleWhere((x)=>(x as Map)['identifier']==id) as Map;
        color=(g['grant'] as Map)['baseColor'] as String;
      }
      final revision=fresh.accountRevision+1,original=fresh.originalId;
      final row=<String,dynamic>{...fresh._source.account,'revision':revision,
        'profile':{...Map<String,Object?>.from(fresh._profile),'activeId':id,'fixedColor':color}};
      tx.set(aRef,row);
      tx.set(base.collection('accountSources').doc('current'),row);
      tx.set(base.collection('accountHistory').doc('$revision'),row);
      tx.set(db.collection('deda_stage71_active_identifier').doc(original),
        {'originalId':original,'activeId':id,'updatedAt':FieldValue.serverTimestamp()});
      tx.set(db.collection('deda_public_active_aliases').doc(original),
        {'originalId':original,'activeId':id,'baseColor':color,'updatedAt':FieldValue.serverTimestamp()});
      if(id!=original)tx.set(db.collection('deda_public_alias_routes').doc(id),
        {'aliasId':id,'originalId':original,'baseColor':color,'updatedAt':FieldValue.serverTimestamp()});
    });
    check();
    final fresh=await readProfile();check();
    if(fresh.requireCurrent().activeId!=id)throw const DedaPrivateDataConflict();
    return fresh;
  }

  /// Review-only client integration. Default closed; the existing live
  /// laboratory rules do not permit this candidate write. Never call from
  /// the UI until the candidate rules and combined save policy are approved.
  static const nameCandidateEnabled =
      bool.fromEnvironment('DEDA_STAGE04_PROFILE_NAME_CANDIDATE');

  static Future<DedaStage04ProfileRead> saveNameCandidate(
      DedaStage04ProfileRead opening, String name) async {
    if (!nameCandidateEnabled) {
      throw StateError('profile-name-candidate-disabled');
    }
    final current = _intent();
    final old = opening.requireCurrent();
    void check() {
      if (!current()) throw const DedaPrivateDataStale();
      opening.requireCurrent();
      _io._check(uid, uid);
    }
    await _io.verifyOwner(uid, uid, check);
    check();
    final db = FirebaseFirestore.instanceFor(app: Firebase.app());
    final base = db.doc('deda_lab_uid_authority/$uid');
    final account = base.collection('account').doc('current');
    final plan = await db.runTransaction<DedaStage04NameChange>((tx) async {
      check();
      final p = await tx.get(base);
      final i = await tx.get(base.collection('inventory').doc('current'));
      final a = await tx.get(account);
      check();
      for (final row in [p,i,a]) {
        if (!row.exists || row.metadata.isFromCache || row.metadata.hasPendingWrites) {
          throw StateError('protected-server-source-required');
        }
      }
      final fresh = DedaStage04ProfileView.fromProtected(
          DedaStage03ProtectedSnapshot.decode(expectedUid: uid,
            progress: p.data(), inventory: i.data(), account: a.data()));
      final change = DedaStage04NameChange.prepare(old, fresh, name);
      check();
      final data = Map<String,dynamic>.from(change.account);
      tx.set(account, data);
      tx.set(base.collection('accountSources').doc('current'), data);
      tx.set(base.collection('accountHistory').doc('${change.revision}'), data);
      return change;
    });
    // A failed acknowledgement is not a confirmed save. No automatic
    // second write or rollback; a caller must reopen the server revision.
    check();
    final readback = await readProfile();
    check();
    if (!plan.confirmedBy(readback.requireCurrent())) {
      throw const DedaPrivateDataConflict();
    }
    return readback;
  }

  /// The original editor uses these two existing guarded writers only.
  /// Candidate remains default-off and no live rules are changed here.
  static Future<DedaStage04ProfileSaveOutcome> saveProfileCandidate(
      DedaStage04AppearanceRead opening, String name,
      DedaStage04Appearance selection) async {
    if (!nameCandidateEnabled) throw StateError('profile-name-candidate-disabled');
    final old = opening.requireCurrent();
    return DedaStage04ProfileSaveOutcome.run(
      nameChanged: name != old.displayName,
      appearanceChanged: opening.selection?.encode() != selection.encode(),
      saveName: () async {
        await saveNameCandidate(opening._profile, name);
      },
      saveAppearance: () async {
        opening.requireCurrent();
        final result = await saveAppearance(opening, selection);
        return result.status == DedaPrivateDataStatus.saved;
      },
    );
  }

  /// Restore existing private data, retaining every field and its revision.
  /// Absence of a selection is not a saved default.
  static Future<DedaStage04AppearanceRead> readAppearance(DedaStage04ProfileRead profile) async {
    profile.requireCurrent();
    final current = _intent();
    final restored = await restore();
    if (!current()) throw const DedaPrivateDataStale();
    final view = profile.requireCurrent();
    if (restored.status != DedaPrivateDataStatus.saved || restored.revision.payload == null) {
      throw StateError('profile-appearance-private-source-held');
    }
    final fields = restored.revision.payload!.fields;
    final selection = fields.containsKey(DedaStage04Appearance.key)
        ? DedaStage04Appearance.decode(fields[DedaStage04Appearance.key]) : null;
    if (selection?.paid == true) selection!.requireOwned(view.verifiedPaidFrameIds);
    return DedaStage04AppearanceRead._(profile,restored.revision,selection);
  }

  /// Only a display selection may change; no protected document is written.
  /// Recheck paid entitlement from the server at save time, then use the
  /// opening revision, the original UID journal and its existing receipts.
  static Future<DedaPrivateDataResult> saveAppearance(
      DedaStage04AppearanceRead opening, DedaStage04Appearance selection) async {
    opening.requireCurrent();
    final current = _intent();
    final fresh = await readProfile();
    final view = fresh.requireCurrent();
    if (!current() || opening.requireCurrent().uid != view.uid) {
      throw const DedaPrivateDataStale();
    }
    if (selection.paid) selection.requireOwned(view.verifiedPaidFrameIds);
    // Previously saved legacy choices can be kept; do not create new legacy
    // avatar/background choices that the original picker no longer offers.
    if ((selection.avatar > 5 && selection.avatar != opening.selection?.avatar) ||
        (selection.background >= 3 && selection.background <= 5 &&
         selection.background != opening.selection?.background) ||
        (!selection.paid && selection.frameStyle((_)=>null) < 3 &&
         selection.frame != opening.selection?.frame)) {
      throw const FormatException('profile-legacy-choice-not-selected');
    }
    final payload = DedaPrivateDataPayload({
      ...opening._revision.payload!.fields,
      DedaStage04Appearance.key: selection.encode(),
    },uidScoped:true);
    return _sync.backup(account:uid, original:uid, payload:payload,
        expectedBase:opening._revision, isCurrent:() {
      if (!current()) return false;
      try { opening.requireCurrent(); fresh.requireCurrent(); return true; }
      catch (_) { return false; }
    });
  }

  // 04/04: reuse the single account guard and existing private journal.
  // No legacy phone, new wallet, ownership or UID.
  static const storeLabMode = bool.fromEnvironment('DEDA_STAGE04_STORE_LAB');

  // Default off. The protected exact approval is produced by the same
  // synthetic checkout engine in emulator QA. It never accepts a client
  // proposed balance, price, ownership or write list. No production fallback.
  static const storeCheckoutCandidateEnabled = storeLabMode &&
      bool.fromEnvironment('DEDA_STAGE04_STORE_CHECKOUT_CANDIDATE');
  // Separately gated; the exact existing approval route remains available
  // for its earlier emulator regression. No fallback on direct failure.
  static const storeDirectCandidateEnabled = storeCheckoutCandidateEnabled &&
      bool.fromEnvironment('DEDA_STAGE04_STORE_DIRECT_CANDIDATE');

  static Future<int> readStorePurchaseBalance(String originalId) async {
    if (!storeCheckoutCandidateEnabled) {
      throw StateError('store-central-spend-authority-held');
    }
    final opening=await readStoreProfile(originalId),current=_intent();
    void check(){if(!current())throw const DedaPrivateDataStale();opening.requireCurrent();}
    await _io.verifyOwner(uid,uid,check);
    final ref=FirebaseFirestore.instanceFor(app:Firebase.app())
        .doc('deda_lab_uid_authority/$uid/wallet/current');
    final row=await ref.get(const GetOptions(source:Source.server));
    check();
    if(!row.exists || row.metadata.isFromCache || row.metadata.hasPendingWrites) {
      throw StateError('store-wallet-source-held');
    }
    final view=opening.requireCurrent();
    final wallet=DedaStage04PersonalWallet.decode(row.data()!,view);
    return wallet.hasManagerPersonal ? wallet.managerPersonal :
      wallet.earnedResidual+wallet.giftResidual;
  }

  static Future<void> performStoreCheckoutCandidate(String originalId,String frameId) async {
    if (!storeCheckoutCandidateEnabled) {
      throw StateError('store-central-spend-authority-held');
    }
    if(!RegExp(r'^FRAME_(03|0[5-9]|1[0-6])$').hasMatch(frameId)) {
      throw ArgumentError('unknown-paid-frame');
    }
    final opening=await readStoreProfile(originalId), current=_intent();
    void check(){if(!current())throw const DedaPrivateDataStale();opening.requireCurrent();}
    await _io.verifyOwner(uid,uid,check);
    final db=FirebaseFirestore.instanceFor(app:Firebase.app());
    final base=db.doc('deda_lab_uid_authority/$uid');
    await db.runTransaction<void>((tx) async {
      check();
      final p=await tx.get(base);
      final i=await tx.get(base.collection('inventory').doc('current'));
      final a=await tx.get(base.collection('account').doc('current'));
      check();
      for(final row in [p,i,a]){
        if(!row.exists || row.metadata.isFromCache || row.metadata.hasPendingWrites) {
          throw const DedaPrivateDataConflict();
        }
      }
      final fresh=DedaStage04ProfileView.fromProtected(
        DedaStage03ProtectedSnapshot.decode(expectedUid:uid,
          progress:p.data(),inventory:i.data(),account:a.data()));
      if(fresh.originalId!=originalId)throw const DedaPrivateDataStale();
      if(fresh.verifiedPaidFrameIds.contains(frameId))return;
      if(storeDirectCandidateEnabled){
        final w=await tx.get(base.collection('wallet').doc('current'));
        final gift=await tx.get(db.doc('deda_diamond_gift_balances/$originalId'));
        final native=await tx.get(db.doc('deda_native_account_cosmetics/$originalId'));
        check();
        for(final row in [w,gift,native]){
          if(!row.exists||row.metadata.isFromCache||row.metadata.hasPendingWrites) {
            throw const DedaPrivateDataConflict();
          }
        }
        final wallet=DedaStage04PersonalWallet.decode(w.data()!,fresh);
        Map<String,dynamic>? personal;
        if(wallet.hasManagerPersonal){
          final m=await tx.get(db.doc('deda_gm_personal_diamond_wallets/$uid'));
          check();
          if(!m.exists||m.metadata.isFromCache||m.metadata.hasPendingWrites) {
            throw const DedaPrivateDataConflict();
          }
          personal=m.data()!;
        }
        final writes=DedaStage04StoreDirectRows.prepare(profile:fresh,frameId:frameId,
          walletRow:w.data()!,gift:gift.data()!,personal:personal,native:native.data()!,
          createdMs:DateTime.now().millisecondsSinceEpoch);
        check();
        for(final entry in writes.entries){tx.set(db.doc(entry.key),entry.value);}
        return;
      }
      final plan=await tx.get(base.collection('storeCheckoutPlans').doc(frameId));
      check();
      if(!plan.exists || plan.metadata.isFromCache || plan.metadata.hasPendingWrites) {
        throw StateError('store-exact-approval-held');
      }
      final approved=plan.data()!;
      if(approved.length!=9 || approved['format']!=1 || approved['uid']!=uid ||
          approved['originalId']!=originalId || approved['frameId']!=frameId ||
          approved['cost']!=1000 || approved['progressRevision']!=fresh.progressRevision ||
          approved['inventoryRevision']!=fresh.inventoryRevision ||
          approved['accountRevision']!=fresh.accountRevision || approved['rows'] is! List) {
        throw const DedaPrivateDataConflict();
      }
      final rows=approved['rows'] as List;
      final root=base.path,revision=fresh.inventoryRevision+1;
      final mandatory=<String>{
        '$root/inventory/current','$root/inventorySources/current',
        '$root/inventoryHistory/$revision','$root/wallet/current',
        '$root/framePurchases/$frameId',
        'deda_lab_frame_receipts/$originalId/frames/$frameId',
        'deda_lab_owned_frames/$originalId/frames/$frameId',
        'deda_native_account_cosmetics/$originalId',
      };
      final allowed=<String>{...mandatory,root,
        'deda_diamond_gift_balances/$originalId',
        'deda_gm_personal_diamond_wallets/$uid'};
      final seen=<String>{},writes=<String,Map<String,dynamic>>{};
      final eventKeys=<String>{},receiptKeys=<String>{};
      if(rows.length<9 || rows.length>12)throw const FormatException('store-plan-size');
      for(final row in rows){
        if(row is! Map || row.length!=3 || !row.containsKey('before') ||
            row['p'] is! String || row['after'] is! Map) {
          throw const FormatException('store-plan-row');
        }
        final path=row['p'] as String;
        if(!seen.add(path))throw const FormatException('store-plan-duplicate');
        final data=Map<String,dynamic>.from(row['after'] as Map);
        if(!allowed.contains(path)){
          final event=RegExp('^$root/events/([a-f0-9]{64})\$').firstMatch(path);
          final receipt=RegExp('^$root/receipts/([a-f0-9]{64})\$').firstMatch(path);
          if(event!=null){eventKeys.add(event.group(1)!);}
          else if(receipt!=null){receiptKeys.add(receipt.group(1)!);}
          else {throw const FormatException('store-plan-path');}
        }
        writes[path]=data;
      }
      if(!seen.containsAll(mandatory) || eventKeys.length!=receiptKeys.length ||
          !eventKeys.containsAll(receiptKeys) || eventKeys.length>1 ||
          (seen.contains(root)!=eventKeys.isNotEmpty)) {
        throw const FormatException('store-plan-incomplete');
      }
      final audit=writes['$root/framePurchases/$frameId']!;
      if(audit['uid']!=uid || audit['originalId']!=originalId ||
          audit['frameId']!=frameId || audit['cost']!=1000) {
        throw const FormatException('store-plan-audit');
      }
      check();
      // The separately emulator-tested exact before/after rules enforce every
      // target document and the all-or-nothing ring. This is not a generic
      // writer: only the protected approval for this frame may be submitted.
      for(final entry in writes.entries){tx.set(db.doc(entry.key),entry.value);}
    });
    check();
    final confirmed=await readStoreProfile(originalId);
    check();
    if(!confirmed.requireCurrent().verifiedPaidFrameIds.contains(frameId)) {
      throw StateError('store-purchase-not-confirmed');
    }
  }

  static Future<DedaStage04ProfileRead> readStoreProfile(String originalId) async {
    if (!storeLabMode) throw StateError('store-lab-disabled');
    final p = await readProfile();
    if (p.requireCurrent().originalId != originalId) {
      throw const DedaPrivateDataStale();
    }
    return p;
  }

  static Future<DedaStage04AppearanceRead> readStoreFreeCard(String originalId) async {
    final p = await readStoreProfile(originalId);
    return readAppearance(p);
  }

  static Future<DedaPrivateDataResult> saveStoreFreeCard(
      DedaStage04AppearanceRead opening,String originalId,String choice) async {
    if (!storeLabMode || opening.requireCurrent().originalId != originalId) {
      throw const DedaPrivateDataStale();
    }
    final current = _intent();
    final fresh = await readStoreProfile(originalId);
    if (!current() || fresh.requireCurrent().uid != opening.requireCurrent().uid) {
      throw const DedaPrivateDataStale();
    }
    final payload = DedaStage04FreeCardChoice.apply(opening._revision.payload!,choice);
    return _sync.backup(account:uid,original:uid,payload:payload,
      expectedBase:opening._revision,isCurrent:(){
        if (!current()) return false;
        try { opening.requireCurrent(); fresh.requireCurrent(); return true; }
        catch (_) { return false; }
      });
  }

  /// Both lists share the same existing UID private journal. Never convert
  /// a missing or malformed list into an empty list.
  static Future<DedaStage04PlacesRead> readProfilePlaces(
      DedaStage04ProfileRead profile, String Function(String) keyOf) async {
    profile.requireCurrent();
    final current=_intent(), result=await restore();
    if(!current()) throw const DedaPrivateDataStale();
    profile.requireCurrent();
    if(result.status!=DedaPrivateDataStatus.saved) {
      throw StateError('stage04-profile-places-not-confirmed');
    }
    return DedaStage04PlacesRead._(profile,DedaStage04PlaceData.fromRevision(result.revision,keyOf));
  }

  /// Original user-initiated private action, guarded by the opening
  /// revision. No monetary, role, map or authoritative document is written.
  static Future<DedaPrivateDataResult> saveProfilePlace(
      DedaStage04PlacesRead opening, String raw, String Function(String) keyOf,
      {bool? favorite, bool recordRecent=false}) async {
    final current=_intent(), data=opening.requireCurrent();
    final payload=data.prepare(raw,keyOf:keyOf,favorite:favorite,recordRecent:recordRecent);
    bool valid(){
      if(!current()) return false;
      try { opening.requireCurrent(); return true; } catch(_) { return false; }
    }
    if(!valid()) throw const DedaPrivateDataStale();
    // The existing compare-and-set path also handles identical payloads.
    return _sync.backup(account:uid,original:uid,payload:payload,
      expectedBase:data.revision,isCurrent:valid);
  }

  void _check(String account, [String? original]) {
    if (!_matches() || account != uid || (original != null && original != uid)) {
      throw const DedaPrivateDataStale();
    }
  }

  String _key(String account) => 'deda_stage03_lab_uid_journal_v1_$account';
  DocumentReference<Map<String, dynamic>> _head(String account) {
    _check(account);
    return FirebaseFirestore.instanceFor(app: Firebase.app())
        .doc('deda_lab_uid_private/$account');
  }

  @override
  String newMutationId() {
    final rng = Random.secure();
    return List.generate(24, (_) => rng.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }
  @override
  Future<String?> readJournal(String account) async {
    _check(account);
    final prefs = await SharedPreferences.getInstance();
    _check(account);
    return prefs.getString(_key(account));
  }
  @override
  Future<void> writeJournal(String account, String text) async {
    _check(account);
    final prefs = await SharedPreferences.getInstance();
    _check(account);
    if (!await prefs.setString(_key(account), text)) throw StateError('journal-write-failed');
    _check(account);
  }
  @override
  Future<void> preserveJournal(String account, String text) async {
    _check(account);
    final prefs = await SharedPreferences.getInstance();
    _check(account);
    if (!await prefs.setString('${_key(account)}_archive_${newMutationId()}', text)) {
      throw StateError('journal-preserve-failed');
    }
    _check(account);
  }
  @override
  Future<void> verifyOwner(String account, String original, void Function() check) async {
    check(); _check(account, original);
    final snapshot = await DedaStage02LabSingleUid.verifyServer(expectedUid: uid);
    check(); _check(account, original);
    DedaAuthRuntime.checkSnapshot(snapshot);
  }

  DedaPrivateDataRevision _decode(DocumentSnapshot<Map<String, dynamic>> snap) {
    if (snap.metadata.isFromCache || snap.metadata.hasPendingWrites) {
      throw StateError('server-revision-required');
    }
    if (!snap.exists) return const DedaPrivateDataRevision(0, null, null);
    final d = snap.data();
    const fields = {'format','uid','version','mutationId','payload','updatedAt'};
    if (d == null || d.length != fields.length || !fields.every(d.containsKey) ||
        d['format'] != 1 || d['uid'] != uid || d['version'] is! int ||
        d['mutationId'] is! String || d['payload'] is! String || d['updatedAt'] is! Timestamp) {
      throw const FormatException('invalid-lab-revision');
    }
    final revision = DedaPrivateDataRevision(d['version'] as int,
      d['mutationId'] as String, DedaPrivateDataPayload.decode(d['payload'] as String, uidScoped: true));
    revision.validate();
    return revision;
  }
  @override
  Future<DedaPrivateDataRevision> readServer(String account, String original, void Function() check) async {
    check(); _check(account, original);
    final snap = await _head(account).get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 15));
    check(); _check(account, original);
    return _decode(snap);
  }
  @override
  Future<DedaPrivateDataRevision> compareAndSet(String account, String original,
      int baseVersion, String mutationId, DedaPrivateDataPayload payload, void Function() check) async {
    check(); _check(account, original);
    final ref = _head(account);
    final receipt = ref.collection('versions').doc(mutationId);
    final db = FirebaseFirestore.instanceFor(app: Firebase.app());
    await db.runTransaction<void>((tx) async {
      check(); _check(account, original);
      final old = _decode(await tx.get(ref));
      check(); _check(account, original);
      if (old.mutationId == mutationId) {
        if (old.payload?.encode() != payload.encode()) throw const FormatException('replay-mismatch');
        return;
      }
      if (old.version != baseVersion) throw const DedaPrivateDataConflict();
      final prior = await tx.get(receipt);
      check(); _check(account, original);
      if (prior.exists) throw const DedaPrivateDataConflict();
      final data = <String,dynamic>{'format': 1, 'uid': uid, 'version': baseVersion+1,
        'mutationId': mutationId, 'payload': payload.encode(), 'updatedAt': FieldValue.serverTimestamp()};
      tx.set(ref,data); tx.set(receipt,data);
    });
    // No outer timeout/retry of a mutation. Read actual committed revision.
    check(); _check(account, original);
    return readServer(account, original, check);
  }
}
