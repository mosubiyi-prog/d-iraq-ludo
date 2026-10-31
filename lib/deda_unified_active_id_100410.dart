import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'deda_qa32_spark_public_identifier_directory.dart';
import 'deda_stage71_free_manager_200_service.dart';
import 'deda_stage71_free_owned_use_profile.dart';
import 'deda_verified_active_id_store.dart';

/// Unified presentation authority. Never rekeys any score, account, share,
/// gift or purchase: the original account ID is still the internal key.
/// A missing public projection is UNKNOWN, not evidence that the old ID
/// remains suitable for display.
class DedaUnifiedActiveId100410 {
  DedaUnifiedActiveId100410._();
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);
  static final Map<String,DedaVerifiedActiveId> _public={};
  static final Set<String> _normal={};
  static final Map<String,StreamSubscription<DocumentSnapshot<Map<String,dynamic>>>> _streams={};
  static final Map<String,int> _refCounts={};
  static final Map<(String,String),Future<void>> _ownerReads={};

  static bool get ready => Firebase.apps.isNotEmpty;
  static String? get uid {
    if (!ready) return null;
    try { return FirebaseAuth.instance.currentUser?.uid; }
    catch (_) { return null; }
  }
  static bool valid(String id) => RegExp(r'^@DEDA-[A-Z0-9]{6}$').hasMatch(id);

  static String? display(String original) {
    if (!valid(original)) return null;
    final current=uid;
    if (current!=null) {
      final own=DedaVerifiedActiveIdStore.read(current,original);
      if (own!=null && own.wellFormed) return own.displayId;
    }
    final projection=_public[original];
    if (projection!=null && projection.wellFormed) return projection.displayId;
    return _normal.contains(original) ? original : null;
  }

  @visibleForTesting
  static bool accept(String original,Map<String,dynamic>? data) {
    if(!valid(original) || data==null) return false;
    final proof=DedaQa32SparkPublicIdentifierDirectory
        .styleFromProjection(original,data);
    if(proof!=null) {
      final id=proof['displayId'], color=proof['permanentColor'];
      if (id is! String || color is! String) return false;
      final record=DedaVerifiedActiveId(
        uid:'public-server',originalId:original,displayId:id,fixedColor:color);
      if(!record.wellFormed) return false;
      final previous=_public[original];
      final changed=previous?.displayId!=id || previous?.fixedColor!=color ||
          _normal.contains(original);
      _normal.remove(original);_public[original]=record;
      if(changed) revision.value++;
      return true;
    }
    if(data.length==4 && data['originalId']==original &&
        data['activeId']==original && data['baseColor']==null &&
        data['updatedAt']!=null) {
      final changed=_public.remove(original)!=null || !_normal.contains(original);
      _normal.add(original);
      if(changed) revision.value++;
      return true;
    }
    return false;
  }

  static void _unknown(String original) {
    final changed=_public.remove(original)!=null || _normal.remove(original);
    if(changed) revision.value++;
  }

  /// All public UI sections share ONE live source subscription for each ID.
  static void Function() watch(String original) {
    if(!valid(original) || !ready) return () {};
    _refCounts[original]=(_refCounts[original]??0)+1;
    if(!_streams.containsKey(original)) {
      _streams[original]=FirebaseFirestore.instance
          .collection('deda_public_active_aliases').doc(original)
          .snapshots(includeMetadataChanges:true).listen((snap) {
        if(snap.metadata.isFromCache || snap.metadata.hasPendingWrites) return;
        if(!accept(original,snap.data())) _unknown(original);
      },onError:(Object error) {
        debugPrint('DEDA unified ID read failure: ${error.runtimeType}');
      });
    }
    bool released=false;
    return () {
      if(released) return;
      released=true;
      final remaining=(_refCounts[original]??1)-1;
      if(remaining>0) {_refCounts[original]=remaining;return;}
      _refCounts.remove(original);
      final sub=_streams.remove(original);
      if(sub!=null) unawaited(sub.cancel());
    };
  }

  /// A shared owner verification read: Stage71.active already checks
  /// authenticated owner, original account route, registry and gift receipt.
  static Future<void> ensureOwner(String original) async {
    final current=uid;
    if(current==null || !valid(original) ||
        !DedaStage71OwnedIdentifierService.enabled) return;
    final key=(current,original);
    final pending=_ownerReads[key];
    if(pending!=null) { await pending; return; }
    final task=_verifyOwner(current,original);
    _ownerReads[key]=task;
    try { await task; }
    finally { if(identical(_ownerReads[key],task)) _ownerReads.remove(key); }
  }

  static Future<void> _verifyOwner(String current,String original) async {
    await DedaVerifiedActiveIdStore.restore(current,original);
    if(uid!=current) return;
    final active=await DedaStage71OwnedIdentifierService.active(original);
    if(uid!=current) return;
    String? color;
    if(active!=original) {
      final doc=await FirebaseFirestore.instance
          .collection(DedaStage71Admin200.registry).doc(active)
          .get(const GetOptions(source:Source.server));
      color=DedaStage71OwnedIdentifier.read(
          doc.id,doc.data()??{},original).baseColor;
    }
    if(uid!=current) return;
    DedaVerifiedActiveIdStore.confirmed(
        uid:current,originalId:original,displayId:active,fixedColor:color);
  }

  /// This is invoked ONLY after server-persisted use() + ownership readback.
  static void confirmedUse(String current,String original,String id,String? color) {
    if(uid!=current) return;
    DedaVerifiedActiveIdStore.confirmed(
        uid:current,originalId:original,displayId:id,fixedColor:color);
  }

  @visibleForTesting
  static void resetPublicForTest() {
    _public.clear();_normal.clear();revision.value++;
  }
}

/// Identical reactive label for manager rows, all league players and profile.
class DedaUnifiedActiveIdLabel100410 extends StatefulWidget {
  const DedaUnifiedActiveIdLabel100410({
    super.key,required this.originalId,this.style,this.textAlign,
  });
  final String originalId;
  final TextStyle? style;
  final TextAlign? textAlign;
  @override
  State<DedaUnifiedActiveIdLabel100410> createState() =>
      _DedaUnifiedActiveIdLabel100410State();
}
class _DedaUnifiedActiveIdLabel100410State
    extends State<DedaUnifiedActiveIdLabel100410> {
  void Function()? _release;
  StreamSubscription<User?>? _auth;
  void _repaint() {if(mounted) setState(() {});}
  void _attach() {
    _release?.call();
    _release=DedaUnifiedActiveId100410.watch(widget.originalId);
    if(DedaUnifiedActiveId100410.uid!=null) {
      unawaited(DedaUnifiedActiveId100410
          .ensureOwner(widget.originalId).catchError((Object _) {}));
    }
  }
  @override
  void initState() {
    super.initState();
    DedaUnifiedActiveId100410.revision.addListener(_repaint);
    DedaVerifiedActiveIdStore.revision.addListener(_repaint);
    _attach();
    if(DedaUnifiedActiveId100410.ready) {
      _auth=FirebaseAuth.instance.authStateChanges().listen((_) {
        if(mounted) {_attach();_repaint();}
      });
    }
  }
  @override
  void didUpdateWidget(covariant DedaUnifiedActiveIdLabel100410 old) {
    super.didUpdateWidget(old);
    if(old.originalId!=widget.originalId) _attach();
  }
  @override
  void dispose() {
    _release?.call();_auth?.cancel();
    DedaUnifiedActiveId100410.revision.removeListener(_repaint);
    DedaVerifiedActiveIdStore.revision.removeListener(_repaint);
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    final value=DedaUnifiedActiveId100410.display(widget.originalId);
    return Text(
      value??(DedaUnifiedActiveId100410.ready ?
          'جارِ تأكيد الآيدي...' : 'معرّف غير متاح'),
      textDirection:TextDirection.ltr,
      textAlign:widget.textAlign,
      maxLines:1,overflow:TextOverflow.ellipsis,
      style:widget.style??const TextStyle(fontSize:11),
    );
  }
}


/// Lets existing ID cards use the same shared authority without ever making
/// a loading placeholder copyable as though it were a real identifier.
class DedaUnifiedActiveIdBuilder100410 extends StatefulWidget {
  const DedaUnifiedActiveIdBuilder100410({
    super.key,required this.originalId,required this.builder,
  });
  final String originalId;
  final Widget Function(BuildContext context,String? active) builder;
  @override
  State<DedaUnifiedActiveIdBuilder100410> createState() =>
      _DedaUnifiedActiveIdBuilder100410State();
}
class _DedaUnifiedActiveIdBuilder100410State
    extends State<DedaUnifiedActiveIdBuilder100410> {
  void Function()? _release;
  StreamSubscription<User?>? _auth;
  void _repaint() {if(mounted) setState(() {});}
  void _start() {
    _release?.call();
    _release=DedaUnifiedActiveId100410.watch(widget.originalId);
    if(DedaUnifiedActiveId100410.uid!=null) {
      unawaited(DedaUnifiedActiveId100410
          .ensureOwner(widget.originalId).catchError((Object _) {}));
    }
  }
  @override
  void initState() {
    super.initState();
    DedaUnifiedActiveId100410.revision.addListener(_repaint);
    DedaVerifiedActiveIdStore.revision.addListener(_repaint);
    _start();
    if(DedaUnifiedActiveId100410.ready) {
      _auth=FirebaseAuth.instance.authStateChanges().listen((_) {
        if(mounted) {_start();_repaint();}
      });
    }
  }
  @override
  void didUpdateWidget(covariant DedaUnifiedActiveIdBuilder100410 old) {
    super.didUpdateWidget(old);
    if(old.originalId!=widget.originalId) _start();
  }
  @override
  void dispose() {
    _release?.call();_auth?.cancel();
    DedaUnifiedActiveId100410.revision.removeListener(_repaint);
    DedaVerifiedActiveIdStore.revision.removeListener(_repaint);
    super.dispose();
  }
  @override
  Widget build(BuildContext context) =>
      widget.builder(context,DedaUnifiedActiveId100410.display(widget.originalId));
}
