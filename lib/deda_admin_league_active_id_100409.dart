import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'deda_qa32_spark_public_identifier_directory.dart';
import 'deda_verified_active_id_store.dart';

/// Independent display component for ALL manager league rows.
///
/// - Reads the same UID-scoped Stage71-confirmed store as the owner profile.
/// - Reuses one stable Firestore subscription per row, not on every rebuild.
/// - Handles server errors and slow/offline streams; never shows infinite
///   "checking ID..." or silently replaces a known premium alias with old ID.
/// - Does not alter any score document identifier, account, grant or wallet.
class DedaAdminLeagueActiveId extends StatefulWidget {
  const DedaAdminLeagueActiveId({
    super.key, required this.originalId, this.style,
  });
  final String originalId;
  final TextStyle? style;

  @override
  State<DedaAdminLeagueActiveId> createState() =>
      _DedaAdminLeagueActiveIdState();
}

class _DedaAdminLeagueActiveIdState extends State<DedaAdminLeagueActiveId> {
  Stream<DocumentSnapshot<Map<String, dynamic>>>? _stream;
  Timer? _limit;
  StreamSubscription<User?>? _authSubscription;
  bool _slow = false;

  void _rebuild() {
    if (mounted) setState(() {});
  }

  void _connect() {
    _limit?.cancel();
    _slow = false;
    if (Firebase.apps.isEmpty) return;
    // Never construct a new Firestore Stream from build() on scroll/repaint.
    _stream = FirebaseFirestore.instance
        .collection('deda_public_active_aliases')
        .doc(widget.originalId)
        .snapshots(includeMetadataChanges: true);
    _limit = Timer(const Duration(seconds: 6), () {
      if (mounted) setState(() => _slow = true);
    });
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      unawaited(DedaVerifiedActiveIdStore.restore(uid, widget.originalId));
    }
  }

  @override
  void initState() {
    super.initState();
    DedaVerifiedActiveIdStore.revision.addListener(_rebuild);
    _connect();
    if (Firebase.apps.isNotEmpty) {
      _authSubscription = FirebaseAuth.instance.authStateChanges().listen((_) {
        if (mounted) setState(_connect);
      });
    }
  }

  @override
  void didUpdateWidget(covariant DedaAdminLeagueActiveId oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.originalId != widget.originalId) _connect();
  }

  @override
  void dispose() {
    _limit?.cancel();
    _authSubscription?.cancel();
    DedaVerifiedActiveIdStore.revision.removeListener(_rebuild);
    super.dispose();
  }

  Widget _label(String value) => Text(
        value,
        textDirection: TextDirection.ltr,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: widget.style ?? const TextStyle(fontSize: 11),
      );

  @override
  Widget build(BuildContext context) {
    if (Firebase.apps.isEmpty) {
      // Existing pure widget-test fixtures have no Firebase backend;
      // display their supplied original ID without issuing network reads.
      return _label(widget.originalId);
    }
    if (_stream == null) return _label('تعذر تأكيد الآيدي');
    return ValueListenableBuilder<int>(
      valueListenable: DedaVerifiedActiveIdStore.revision,
      builder: (context, _, __) {
        final uid = FirebaseAuth.instance.currentUser?.uid;
        final own = uid == null ? null :
            DedaVerifiedActiveIdStore.read(uid, widget.originalId);
        if (own != null && own.wellFormed) {
          return _label(own.displayId);
        }
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _stream,
          builder: (context, snap) {
            if (snap.hasData && !snap.data!.metadata.isFromCache) {
              final data = snap.data!.data();
              final proof =
                  DedaQa32SparkPublicIdentifierDirectory.styleFromProjection(
                      widget.originalId, data);
              if (proof?['displayId'] is String) {
                return _label(proof!['displayId'] as String);
              }
              if (data != null && data.length == 4 &&
                  data['originalId'] == widget.originalId &&
                  data['activeId'] == widget.originalId &&
                  data['baseColor'] == null) {
                // Explicitly verified normal ID after returning from a
                // purchased ID: do not leave the old premium display here.
                return _label(widget.originalId);
              }
              // If the owner has never published an alias, we cannot safely
              // assume the immutable account key is the current display ID.
              // Never display a potentially retired premium identifier.
              return _label('بانتظار توثيق الآيدي');
            }
            if (snap.hasError) {
              return _label('تعذر تأكيد الآيدي');
            }
            return _label(_slow
                ? 'تعذر التحقق، أعد التحديث'
                : 'جارِ التحقق من الآيدي...');
          },
        );
      },
    );
  }
}
