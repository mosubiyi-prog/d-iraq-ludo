import 'deda_stage50_verified_friend_ink_badge.dart';
import 'main.dart' show DedaPreferences;
import 'deda_stage71_free_owned_use_profile.dart';
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
            return DedaStage50FriendIdInkText(originalId: originalId,
              verified: DedaStage50PublicIdStyle.parse(verified, originalId),
              fallback: fallback);
          });
      });
  }
}

/// User-facing Copy/Share follows the same verified current identity as the
/// label. Reward, friendship and location storage continue to use canonical IDs.
class DedaSixIdentityCopy {
  static Future<String?> resolve(String original) async {
    final phone=DedaPreferences.phone;
    if(Firebase.apps.isEmpty) return original;
    final uid=FirebaseAuth.instance.currentUser?.uid;
    if(uid==null) return null;
    bool same()=>DedaPreferences.phone==phone &&
        FirebaseAuth.instance.currentUser?.uid==uid;
    try {
      final active=await DedaStage71OwnedIdentifierService.active(original);
      return same()?active:null;
    } catch(_) {return same()?original:null;}
  }
}
