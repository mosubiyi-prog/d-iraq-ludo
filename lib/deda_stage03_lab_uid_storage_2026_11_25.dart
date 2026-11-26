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

/// The restored private revision used to open the existing profile editor.
/// A selection never confers an entitlement. The base is held for CAS.
class DedaStage04AppearanceRead {
  DedaStage04AppearanceRead._(this._profile, this._revision, this.selection);
  final DedaStage04ProfileRead _profile;
  final DedaPrivateDataRevision _revision;
  final DedaStage04Appearance? selection;
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
    final token = await FirebaseAuth.instance.currentUser!.getIdToken(true)
        .timeout(const Duration(seconds: 15));
    check(); _check(account, original);
    if (token == null || token.isEmpty) throw StateError('server-auth-required');
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
