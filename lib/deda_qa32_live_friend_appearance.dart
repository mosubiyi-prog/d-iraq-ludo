import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'deda_social_service.dart';

typedef DedaQa32PublicFriendBuilder = Widget Function(
    BuildContext context, DedaSocialProfile verified);

/// Safe friend public appearance. Never reads wallets or private user docs.
/// The already fetched public profile is used if Firebase is not initialized,
/// the logged-in viewer changes, the network fails or owner identity drifts.
///
/// Firestore security rules are still the authoritative permission boundary;
/// unlike a locally guessed premium ID, only existing public-profile fields
/// can change via this widget. The separate verified-ID callable remains OFF.
class DedaQa32LiveFriendAppearance extends StatelessWidget {
  final DedaSocialProfile initial;
  final DedaQa32PublicFriendBuilder builder;

  const DedaQa32LiveFriendAppearance({
    super.key,
    required this.initial,
    required this.builder,
  });

  static DedaSocialProfile verifiedUpdate(
      DedaSocialProfile initial, DedaSocialProfile? candidate) {
    if (candidate == null ||
        candidate.publicId != initial.publicId ||
        initial.ownerUid.isEmpty ||
        candidate.ownerUid != initial.ownerUid) {
      return initial;
    }
    return candidate;
  }

  bool get _firebaseReady {
    try {
      return Firebase.apps.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_firebaseReady ||
        initial.publicId.isEmpty ||
        initial.ownerUid.isEmpty ||
        !RegExp(r'^@DEDA-[A-Z0-9]{6}$').hasMatch(initial.publicId)) {
      return builder(context, initial);
    }
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, session) {
        if (session.data == null) return builder(context, initial);
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('deda_social_profiles')
              .doc(initial.publicId)
              .snapshots(),
          builder: (context, snapshot) {
            DedaSocialProfile? latest;
            if (snapshot.hasData && snapshot.data!.exists) {
              final data = snapshot.data!.data();
              if (data != null) {
                try {
                  latest = DedaSocialProfile.fromMap(data);
                } catch (_) {
                  // Reject malformed public data, never guess an appearance.
                }
              }
            }
            return builder(context, verifiedUpdate(initial, latest));
          },
        );
      },
    );
  }
}
