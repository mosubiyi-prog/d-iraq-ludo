import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'deda_stage71_free_manager_200_service.dart';
import 'deda_stage74_id_gift_service.dart';
import 'deda_qa32_spark_public_identifier_directory.dart';
import 'main.dart' show DedaPremiumIdCard, DedaPremiumIdCardColor;

/// Stage71: permanent gifted/self-used identifiers accessible by the verified
/// recipient's original DEDA account. No change to the actual canonical
/// original ID or to diamonds. One active display name at a time.
class DedaStage71OwnedIdentifier {
  final String identifier;
  final String baseColor;
  final String recipientOriginalId;
  final String group;
  /// Proof source: gifted requires a received gift receipt; self_used is
  /// the original owner's already-assigned administrator record.
  final String kind;
  const DedaStage71OwnedIdentifier({
    required this.identifier, required this.baseColor,
    required this.recipientOriginalId, required this.group,
    this.kind = 'self_used',
  });

  static DedaStage71OwnedIdentifier read(
      String id, Map<String, dynamic> data, String ownerId) {
    final owner = (data['recipientOriginalId'] ?? '').toString();
    final color = (data['baseColor'] ?? '').toString();
    final group = (data['group'] ?? '').toString();
    if (data['identifier'] != id ||
        !RegExp(r'^@DEDA-[A-Z0-9]{4,12}$').hasMatch(id) ||
        owner != ownerId ||
        !{'gold','diamond','royal','pink'}.contains(color) ||
        !{'001','002'}.contains(group) ||
        !{'gifted','self_used'}.contains(data['kind'])) {
      throw StateError('unverified-free-owned-identifier');
    }
    return DedaStage71OwnedIdentifier(
      identifier:id, baseColor:color,recipientOriginalId:owner,group:group,
      kind: data['kind'] as String,
    );
  }
}

/// Notifies visible owner-identity widgets after a server-confirmed
/// active-identifier change. This is a UI refresh only, not authority.
class DedaStage71ActiveIdRefresh {
  DedaStage71ActiveIdRefresh._();
  static final ValueNotifier<int> notifier = ValueNotifier<int>(0);
  static void changed() => notifier.value = notifier.value + 1;
}

class DedaStage71OwnedIdentifierService {
  DedaStage71OwnedIdentifierService._();
  static bool get enabled => DedaStage71Admin200.enabled;
  static const activeCollection = 'deda_stage71_active_identifier';

  static Future<String> _requireOriginal(String id) async {
    if (!enabled || Firebase.apps.isEmpty ||
        !RegExp(r'^@DEDA-[A-Z0-9]{6}$').hasMatch(id)) {
      throw StateError('free-identifier-rules-not-live');
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('no-firebase-account');
    final db = FirebaseFirestore.instance;
    final docs = await Future.wait([
      db.collection('users').doc(user.uid).get(),
      db.collection('deda_sessions').doc(user.uid).get(),
    ]);
    final profile=docs[0].data() ?? {};
    final session=docs[1].data() ?? {};
    if (FirebaseAuth.instance.currentUser?.uid!=user.uid ||
        profile['sharePersonalId'] != id ||
        profile['accountKey']==null ||
        profile['accountKey'] != session['accountKey']) {
      throw StateError('different-original-account');
    }
    return user.uid;
  }

  static Future<List<DedaStage71OwnedIdentifier>> owned(String originalId) async {
    final uid=await _requireOriginal(originalId);
    final db=FirebaseFirestore.instance;
    final records=await db.collection(DedaStage71Admin200.registry)
        .where('recipientOriginalId', isEqualTo:originalId).limit(200).get();
    if (FirebaseAuth.instance.currentUser?.uid!=uid) {
      throw StateError('account-rotated');
    }
    return records.docs.map((d)=>
      DedaStage71OwnedIdentifier.read(d.id,d.data(),originalId)).toList();
  }

  /// DEDA_100377_READONLY_ACCEPTED_OWNED_IDS_P12_P13
  /// Fetch from the server under the authenticated original owner. An
  /// allocated-but-unreceived gift is NEVER counted as the owner's inventory.
  /// This never changes grants, the active alias, the original routing ID,
  /// administrative stock or balances.
  static Future<List<DedaStage71OwnedIdentifier>> acceptedOwnedForMyStore(
      String originalId) async {
    final uid = await _requireOriginal(originalId);
    final records = await FirebaseFirestore.instance
        .collection(DedaStage71Admin200.registry)
        .where('recipientOriginalId', isEqualTo: originalId)
        .limit(200)
        .get(const GetOptions(source: Source.server));
    if (FirebaseAuth.instance.currentUser?.uid != uid) {
      throw StateError('account-rotated-during-inventory');
    }
    final accepted = <DedaStage71OwnedIdentifier>[];
    for (final record in records.docs) {
      final data = record.data();
      final verified = DedaStage71OwnedIdentifier.read(
        record.id, data, originalId,
      );
      if (verified.kind == 'gifted') {
        // Receipt is checked from Source.server by the existing gift service;
        // a pending/failed/unreceived gift stays outside My Store.
        final received = await DedaStage74IdGiftService.isReceived(
          originalId, verified.identifier,
        );
        if (!received) continue;
      } else if (verified.kind != 'self_used') {
        continue;
      }
      if (FirebaseAuth.instance.currentUser?.uid != uid) {
        throw StateError('account-switched-during-gift-check');
      }
      accepted.add(verified);
    }
    if (FirebaseAuth.instance.currentUser?.uid != uid) {
      throw StateError('account-switched-before-inventory-return');
    }
    return List<DedaStage71OwnedIdentifier>.unmodifiable(accepted);
  }

  static Future<String> active(String originalId) async {
    final uid=await _requireOriginal(originalId);
    final db=FirebaseFirestore.instance;
    final doc=await db.collection(activeCollection).doc(originalId).get();
    if (FirebaseAuth.instance.currentUser?.uid!=uid) {
      throw StateError('account-rotated');
    }
    if (!doc.exists) return originalId;
    final data=doc.data() ?? {};
    if (data['originalId']!=originalId || data['activeId'] is! String) {
      throw StateError('corrupt-active-identifier');
    }
    final current=data['activeId'] as String;
    if (current==originalId) return originalId;
    final ownedDoc=await db.collection(DedaStage71Admin200.registry)
        .doc(current).get();
    final owner = DedaStage71OwnedIdentifier.read(
      ownedDoc.id, ownedDoc.data() ?? {}, originalId,
    );
    if (ownedDoc.data()?['kind'] == 'gifted' &&
        !await DedaStage74IdGiftService.isReceived(
          owner.recipientOriginalId, current,
        )) {
      throw StateError('premium-id-gift-awaits-recipient-receipt');
    }
    return current;
  }

  static Future<void> use(String originalId,String identifier) async {
    final uid=await _requireOriginal(originalId);
    final db=FirebaseFirestore.instance;
    if (identifier!=originalId) {
      final owner=await db.collection(DedaStage71Admin200.registry)
          .doc(identifier).get();
      DedaStage71OwnedIdentifier.read(
        owner.id,owner.data() ?? {},originalId);
      if (owner.data()?['kind']=='gifted' &&
          !await DedaStage74IdGiftService.isReceived(
            originalId, identifier,
          )) {
        throw StateError('premium-id-gift-not-yet-received');
      }
    }
    if (FirebaseAuth.instance.currentUser?.uid!=uid) {
      throw StateError('account-rotated');
    }
    await db.collection(activeCollection).doc(originalId).set({
      'originalId':originalId,
      'activeId':identifier,
      'updatedAt':FieldValue.serverTimestamp(),
    });
    final persisted=await active(originalId);
    if(persisted!=identifier) throw StateError('active-id-readback-failed');
    // Spark owner publication only after original ID, selection, grant
    // and (if gifted) receipt have already been confirmed on the server.
    if (DedaQa32SparkPublicIdentifierDirectory.enabled) {
      String? foil;
      if (identifier != originalId) {
        final rows = await owned(originalId);
        final matching = rows.where((r) => r.identifier == identifier).toList();
        if (matching.length != 1) throw StateError('spark-owner-foil-not-proven');
        foil = matching.single.baseColor;
      }
      await DedaQa32SparkPublicIdentifierDirectory.publishOwnerVerified(
        originalId: originalId,
        selectedAlias: identifier,
        permanentColor: foil,
      );
    }
    DedaStage71ActiveIdRefresh.changed();
  }
}

/// User's Edit Profile: one compact owned list, usable without any price.
class DedaStage71OwnedIdsPanel extends StatefulWidget {
  final String originalId;
  const DedaStage71OwnedIdsPanel({super.key,required this.originalId});

  @override
  State<DedaStage71OwnedIdsPanel> createState()=>_DedaStage71OwnedIdsPanelState();
}

class _DedaStage71OwnedIdsPanelState
    extends State<DedaStage71OwnedIdsPanel> {
  List<DedaStage71OwnedIdentifier>? _ids;
  String? _active;
  bool _busy = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    DedaStage71ActiveIdRefresh.notifier.addListener(_onActiveChanged);
    _load();
  }

  void _onActiveChanged() {
    if (!_busy) _load();
  }

  @override
  void didUpdateWidget(covariant DedaStage71OwnedIdsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.originalId != widget.originalId) {
      // DEDA_100377_POINT09_OWNED_IDS_ACCOUNT_SWITCH_NO_STALE_ROWS
      // Clear the previous user's entitlement and active alias immediately.
      // Invalidate all previous loads or Use replies before reading new UID.
      ++_generation;
      _ids = null;
      _active = null;
      _busy = false;
      _load();
    }
  }

  @override
  void dispose() {
    ++_generation;
    DedaStage71ActiveIdRefresh.notifier.removeListener(_onActiveChanged);
    super.dispose();
  }

  Future<void> _load() async {
    if (!DedaStage71OwnedIdentifierService.enabled || _busy) return;
    final generation = ++_generation;
    final original = widget.originalId;
    try {
      final all = await DedaStage71OwnedIdentifierService.owned(original);
      final received = await DedaStage74IdGiftService.receivedNames(original);
      // Only a valid grant or a received gift may be presented as owned.
      final db = FirebaseFirestore.instance;
      final rows = <DedaStage71OwnedIdentifier>[];
      for (final item in all) {
        if (received.contains(item.identifier)) {
          rows.add(item);
          continue;
        }
        final record = await db.collection(DedaStage71Admin200.registry)
            .doc(item.identifier)
            .get(const GetOptions(source: Source.server));
        if (record.data()?['kind'] == 'self_used') rows.add(item);
      }
      final chosen = await DedaStage71OwnedIdentifierService.active(original);
      if (!mounted || generation != _generation ||
          widget.originalId != original) return;
      setState(() {
        _ids = rows;
        _active = chosen;
      });
    } catch (_) {
      if (mounted && generation == _generation &&
          widget.originalId == original) {
        setState(() {
          _ids = null;
          _active = null;
        });
      }
    }
  }

  Future<void> _use(String id) async {
    if (_busy) return;
    final original = widget.originalId;
    final generation = ++_generation;
    setState(() => _busy = true);
    try {
      await DedaStage71OwnedIdentifierService.use(original, id);
      if (!mounted || generation != _generation ||
          widget.originalId != original) return;
      setState(() => _active = id);
    } catch (_) {
      if (mounted && generation == _generation &&
          widget.originalId == original) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('تعذّر تأكيد استخدام المعرف. حدث القائمة وحاول ثانية.'),
        ));
      }
    } finally {
      if (mounted && generation == _generation &&
          widget.originalId == original) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if(!DedaStage71OwnedIdentifierService.enabled){
      return const SizedBox.shrink();
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch,
          children:[
            Row(children:[
              const Expanded(child:Text('معرّفاتي',
                style:TextStyle(fontWeight:FontWeight.bold))),
              IconButton(onPressed:_busy?null:_load,
                icon:const Icon(Icons.refresh)),
            ]),
            if(_ids==null) const Text('الملكية بانتظار التحقق من الخادم'),
            if(_ids!=null && _ids!.isEmpty)
              const Text('لا توجد معرّفات ممنوحة بعد'),
            // QA32: original is never lost and is always available to
            // reactivate when a gifted or self-used premium ID is active.
            // Switching only changes the ACTIVE display alias, not the
            // immutable original account/share routing identifier.
            if (_ids != null)
              ListTile(
                key: const Key('deda_qa32_permanent_original_owned_row'),
                dense: true,
                title: Text(widget.originalId,
                    textDirection: TextDirection.ltr),
                subtitle: const Text('المعرّف الأصلي • محفوظ دائمًا'),
                trailing: OutlinedButton(
                  onPressed: _busy || _active == widget.originalId
                      ? null
                      : () => _use(widget.originalId),
                  child: Text(_active == widget.originalId
                      ? 'مستخدم' : 'استخدام'),
                ),
              ),
            for(final owned in _ids ?? <DedaStage71OwnedIdentifier>[])
              ListTile(
                dense:true,
                title:Text(owned.identifier,textDirection:TextDirection.ltr),
                subtitle:Text('لون أصلي ثابت • مجموعة ${owned.group}'),
                trailing:OutlinedButton(
                  onPressed:_busy||_active==owned.identifier
                    ?null:()=>_use(owned.identifier),
                  child:Text(_active==owned.identifier
                    ?'مستخدم':'استخدام'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// On the user's personal hero, display the confirmed fixed-color active
/// granted identifier. Original free foil remains the fallback, unchanged.
/// This does not rewrite the permanent original ID or friend/share keys.
class DedaStage71ActiveProfileFoil extends StatefulWidget {
  final String originalId;
  final Widget fallback;
  const DedaStage71ActiveProfileFoil({
    super.key,required this.originalId,required this.fallback,
  });

  @override
  State<DedaStage71ActiveProfileFoil> createState()=>
      _DedaStage71ActiveProfileFoilState();
}
class _DedaStage71ActiveProfileFoilState
    extends State<DedaStage71ActiveProfileFoil> {
  String? _active;
  String? _color;
  String? _verifiedOriginal;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    DedaStage71ActiveIdRefresh.notifier.addListener(_load);
    _load();
  }

  @override
  void didUpdateWidget(covariant DedaStage71ActiveProfileFoil oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.originalId != widget.originalId) {
      // DEDA_100377_POINT09_ACTIVE_FOIL_ACCOUNT_SWITCH_SAFE_FALLBACK
      ++_generation;
      _active = null;
      _color = null;
      _verifiedOriginal = null;
      _load();
    }
  }

  @override
  void dispose() {
    ++_generation;
    DedaStage71ActiveIdRefresh.notifier.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    final original = widget.originalId;
    if (_active != null || _color != null || _verifiedOriginal != null) {
      if (mounted) setState(() {
        _active = null;
        _color = null;
        _verifiedOriginal = null;
      });
    }
    if (!DedaStage71OwnedIdentifierService.enabled) return;
    try {
      final active = await DedaStage71OwnedIdentifierService.active(original);
      if (!mounted || generation != _generation ||
          widget.originalId != original) return;
      if (active == original) {
        // The original-ID fallback remains the only permitted visual state.
        return;
      }
      final rows = await DedaStage71OwnedIdentifierService.owned(original);
      final matching = rows.where((r) => r.identifier == active).toList();
      if (matching.length != 1) throw StateError('active-id-not-owned');
      if (!mounted || generation != _generation ||
          widget.originalId != original) return;
      setState(() {
        _active = active;
        _color = matching.single.baseColor;
        _verifiedOriginal = original;
      });
      // Preserve the existing optional Spark projection refresh. Do not
      // invent remote ownership, change original identity or touch wallets.
      if (DedaQa32SparkPublicIdentifierDirectory.enabled &&
          mounted && generation == _generation &&
          widget.originalId == original) {
        try {
          final style = await DedaQa32SparkPublicIdentifierDirectory
              .readVerifiedStyle(original);
          if (!mounted || generation != _generation ||
              widget.originalId != original) return;
          if (style == null ||
              style['displayId'] != active ||
              style['permanentColor'] != matching.single.baseColor) {
            await DedaQa32SparkPublicIdentifierDirectory.publishOwnerVerified(
              originalId: original,
              selectedAlias: active,
              permanentColor: matching.single.baseColor,
            );
          }
        } catch (_) {
          // Owner-only fallback remains safe if public projection is not live.
        }
      }
    } catch (_) {
      if (mounted && generation == _generation &&
          widget.originalId == original) {
        setState(() {
          _active = null;
          _color = null;
          _verifiedOriginal = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_verifiedOriginal != widget.originalId ||
        _active == null || _color == null) return widget.fallback;
    final color=DedaPremiumIdCardColor.values.firstWhere(
      (c)=>c.name==_color!,
    );
    return GestureDetector(
      key:const Key('deda_stage71_active_granted_id_hero'),
      onTap:()=>Clipboard.setData(ClipboardData(text:_active!)),
      child:DedaPremiumIdCard(
        identifier:_active!,color:color,height:50,
      ),
    );
  }
}
