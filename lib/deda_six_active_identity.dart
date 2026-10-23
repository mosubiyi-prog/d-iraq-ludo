import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'deda_qa32_spark_public_identifier_directory.dart';
import 'package:flutter/material.dart';
import 'deda_qa32_active_account_scope.dart';

/// Resolves only verified owner identity; canonical ID remains the fallback
/// and stable backend route. No local alias cache or hardcoded owner name.
class DedaSixActiveIdentity extends StatelessWidget {
  const DedaSixActiveIdentity({super.key, required this.originalId,
    this.style, this.selectable = false, this.textAlign = TextAlign.center});
  final String originalId;
  final TextStyle? style;
  final bool selectable;
  final TextAlign textAlign;
  @override
  Widget build(BuildContext context) => DedaQa32ActiveAccountScope(
    originalId: originalId,
    builder: (context, proof) {
      final id = proof?.displayId ?? originalId;
      return Directionality(textDirection: TextDirection.ltr,
        child: selectable ? SelectableText(id, style: style, textAlign: textAlign)
          : Text(id, style: style, textAlign: textAlign));
    });
}

/// Live public projection for received-location sender labels. Canonical
/// sender IDs remain unchanged in saved shares and routing authorization.
class DedaSixReceivedIdentity extends StatelessWidget {
  const DedaSixReceivedIdentity({super.key, required this.originalId,
    required this.fallback});
  final String originalId;
  final Widget fallback;
  @override
  Widget build(BuildContext context) {
    if (Firebase.apps.isEmpty || !DedaQa32SparkPublicIdentifierDirectory.enabled ||
        !RegExp(r'^@DEDA-[A-Z0-9]{6}$').hasMatch(originalId)) return fallback;
    return StreamBuilder<User?>(stream: FirebaseAuth.instance.authStateChanges(),
      initialData: FirebaseAuth.instance.currentUser,
      builder: (context, auth) {
        final uid = auth.data?.uid;
        if (uid == null || uid != FirebaseAuth.instance.currentUser?.uid) return fallback;
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          key: ValueKey('$uid:$originalId'),
          stream: FirebaseFirestore.instance.collection('deda_public_active_aliases')
            .doc(originalId).snapshots(includeMetadataChanges: true),
          builder: (context, snapshot) {
            if (snapshot.hasError || snapshot.data?.metadata.isFromCache != false ||
                uid != FirebaseAuth.instance.currentUser?.uid)
              return fallback;
            final verified = DedaQa32SparkPublicIdentifierDirectory.styleFromProjection(
                originalId, snapshot.data?.data());
            if (verified == null) return fallback;
            return Text(verified['displayId'] as String,
              textDirection: TextDirection.ltr,
              style: const TextStyle(color: Color(0xFF5C635D),
                  fontWeight: FontWeight.w700));
          });
      });
  }
}
