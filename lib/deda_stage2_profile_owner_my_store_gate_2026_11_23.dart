import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'deda_100377_my_store_page_staged.dart';

/// Account-rotation guard in front of the ONE original My Store renderer.
/// This does not authenticate an account or grant any paid inventory.
/// The original page is created only while the same public owner remains.
class DedaStage2ProfileOwnerBoundMyStore extends StatelessWidget {
  const DedaStage2ProfileOwnerBoundMyStore({
    super.key,
    required this.originalId,
    required this.items,
    required this.initialUid,
    required this.ownerStillCurrent,
    this.isArabic = true,
    this.onOpenIdentifierShop,
    this.onOpenEditProfile,
  });

  final String originalId;
  final List<DedaMyStoreItem> items;
  final String? initialUid;
  final bool Function() ownerStillCurrent;
  final bool isArabic;
  final VoidCallback? onOpenIdentifierShop;
  final VoidCallback? onOpenEditProfile;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: Firebase.apps.isEmpty
          ? Stream<User?>.value(null)
          : FirebaseAuth.instance.authStateChanges(),
      builder: (context, _) {
        final uid = Firebase.apps.isEmpty
            ? null : FirebaseAuth.instance.currentUser?.uid;
        if (uid != initialUid || !ownerStillCurrent()) {
          return Scaffold(
            appBar: AppBar(title: const Text('متجري')),
            body: const Center(
              child: Text('تغيّر الحساب. أعد فتح متجري من الملف الحالي.',
                  textAlign: TextAlign.center),
            ),
          );
        }
        return DedaMyStorePage(
          originalId: originalId,
          items: items,
          isArabic: isArabic,
          onOpenIdentifierShop: onOpenIdentifierShop,
          onOpenEditProfile: onOpenEditProfile,
        );
      },
    );
  }
}
