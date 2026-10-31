import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'deda_qa32_spark_public_identifier_directory.dart';
import 'deda_verified_active_id_store.dart';

/// Presentation only: manager actions, score documents, freeze and restore
/// continue to use the original immutable Firebase account route.
class DedaAdminLeagueActiveId extends StatelessWidget {
  const DedaAdminLeagueActiveId({
    super.key, required this.originalId, this.style,
  });
  final String originalId;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final own = uid == null ? null :
        DedaVerifiedActiveIdStore.read(uid, originalId);
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('deda_public_active_aliases')
          .doc(originalId).snapshots(),
      builder: (context, snap) {
        // On this phone the server-confirmed own cache may be shown right away.
        // Other players require a verified server projection before display.
        var id = own?.displayId;
        if (snap.hasData && !snap.data!.metadata.isFromCache) {
          final checked =
              DedaQa32SparkPublicIdentifierDirectory.styleFromProjection(
                  originalId, snap.data!.data());
          id = checked?['displayId'] as String? ?? originalId;
        }
        return Text(id ?? 'جارِ التحقق من الآيدي...',
          textDirection: TextDirection.ltr,
          maxLines: 1, overflow: TextOverflow.ellipsis,
          style: style ?? const TextStyle(fontSize: 11));
      },
    );
  }
}
