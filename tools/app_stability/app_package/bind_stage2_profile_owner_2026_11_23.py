#!/usr/bin/env python3
"""Guard the ONE existing DEDA profile/My Store in disposable full-app source.

This is a SOURCE-ONLY, no-deploy safety binder, not another profile or UID.
The previously approved original account, editing, colors, store, levels,
frames, IDs, badges, gifts and wallets remain owned by their original code.
"""
import argparse
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
MARK = '// DEDA_STAGE2_PROFILE_ONE_OWNER_MY_STORE_2026_11_23'
MAIN_ANCHOR = ("        builder: (_) => DedaMyStorePage(\n"
               "          originalId: originalId,\n"
               "          items: items,")
MAIN_GUARD = """        builder: (_) => DedaMyStorePage(
          originalId: originalId,
          items: items,
          // Same existing read-only inventory, never a second store.
          // Freeze the public owner, original ID and signed UID at entry.
          guardAccountState: true,
          guardUidAtOpen: signedUidAtOpen,
          isOriginalOwnerCurrent: () =>
              mounted &&
              DedaPreferences.isLoggedIn &&
              DedaPreferences.phone == accountPhone &&
              _dedaId == originalId &&
              (Firebase.apps.isEmpty
                  ? signedUidAtOpen == null
                  : FirebaseAuth.instance.currentUser?.uid == signedUidAtOpen),"""
IMPORT = "import 'package:flutter/material.dart';"
OWNER_IMPORTS = """import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';"""
CTOR = "    required this.originalId,\n    required this.items,"
GUARD_CTOR = """    required this.originalId,
    required this.items,
    this.guardAccountState = false,
    this.guardUidAtOpen,
    this.isOriginalOwnerCurrent,"""
FIELDS = "  final String originalId;\n  final List<DedaMyStoreItem> items;"
GUARD_FIELDS = """  final String originalId;
  final List<DedaMyStoreItem> items;
  // This does not verify ownership. It DENIES display if the old page outlives
  // the original local account or default Firebase principal.
  final bool guardAccountState;
  final String? guardUidAtOpen;
  final bool Function()? isOriginalOwnerCurrent;"""
BUILD = """  @override
  Widget build(BuildContext context) {
    return Scaffold("""
GUARD_BUILD = """  // DEDA_STAGE2_PROFILE_ONE_OWNER_MY_STORE_2026_11_23
  @override
  Widget build(BuildContext context) {
    if (!guardAccountState) return _buildOriginalMyStore(context);
    return StreamBuilder<User?>(
      stream: Firebase.apps.isEmpty
          ? Stream<User?>.value(null)
          : FirebaseAuth.instance.authStateChanges(),
      builder: (context, _) {
        final currentUid = Firebase.apps.isEmpty
            ? null : FirebaseAuth.instance.currentUser?.uid;
        if (currentUid != guardUidAtOpen ||
            isOriginalOwnerCurrent?.call() != true) {
          return Scaffold(
            appBar: AppBar(title: const Text('متجري')),
            body: const Center(child: Text(
              'تغيّر الحساب. أعد فتح متجري من ملف الحساب الحالي.',
              textAlign: TextAlign.center,
            )),
          );
        }
        return _buildOriginalMyStore(context);
      },
    );
  }

  Widget _buildOriginalMyStore(BuildContext context) {
    return Scaffold("""


def once(source: str, old: str, replacement: str, label: str) -> str:
    if source.count(old) != 1:
        raise ValueError(f'PROFILE_STOP_SOURCE_DRIFT:{label}:{source.count(old)}')
    return source.replace(old, replacement, 1)


def patched(main: str, store: str) -> tuple[str, str]:
    if MARK in store or 'guardAccountState: true,' in main:
        raise ValueError('PROFILE_ALREADY_BOUND_USE_VERIFY_ONLY')
    # The real assembled profile, its unique store route and current owner
    # snapshot must exist. Never inject a second screen or overwrite source.
    for label, value in (
        ('profile-class', 'class _DedaProfilePhase2PageState'),
        ('original-edit', '  Future<void> _openEditProfile() async {'),
        ('original-store', '  Future<void> _openDedaMyStore() async {'),
        ('owner-frozen-uid', 'final signedUidAtOpen = Firebase.apps.isEmpty'),
        ('original-id', 'final originalId = _dedaId;'),
        ('single-store-class', 'class DedaMyStorePage extends StatelessWidget'),
    ):
        where = store if label == 'single-store-class' else main
        if where.count(value) != 1:
            raise ValueError(f'PROFILE_STOP_MISSING_SINGLE_ORIGINAL:{label}:{where.count(value)}')
    store = once(store, IMPORT, OWNER_IMPORTS, 'imports')
    store = once(store, CTOR, GUARD_CTOR, 'constructor')
    store = once(store, FIELDS, GUARD_FIELDS, 'fields')
    store = once(store, BUILD, GUARD_BUILD, 'original-store-widget')
    main = once(main, MAIN_ANCHOR, MAIN_GUARD, 'existing-profile-store-route')
    verify(main, store)
    return main, store


def verify(main: str, store: str):
    for name, condition in (
        ('one-profile', main.count('class _DedaProfilePhase2PageState') == 1),
        ('one-store-route', main.count('builder: (_) => DedaMyStorePage(') == 1),
        ('one-owner-check', main.count('guardAccountState: true,') == 1),
        ('original-phone', 'DedaPreferences.phone == accountPhone' in main),
        ('original-id', '_dedaId == originalId' in main),
        ('signed-uid', 'FirebaseAuth.instance.currentUser?.uid == signedUidAtOpen' in main),
        ('one-my-store', store.count('class DedaMyStorePage extends StatelessWidget') == 1),
        ('one-guard', store.count(MARK) == 1),
        ('auth-stream', 'FirebaseAuth.instance.authStateChanges()' in store),
        ('store-retained', "key: const Key('deda_p12_my_store_read_only')" in store),
        ('original-shop-retained', "key: const Key('deda_p12_original_identifier_shop_entry')" in store),
        ('edit-retained', "key: const Key('deda_p12_original_edit_profile_entry')" in store),
        ('no-direct-deduction', "collection('deda_diamond_gift_balances')" not in store),
    ):
        if not condition:
            raise ValueError('PROFILE_VERIFY_FAILED:' + name)


def bind(project: Path, verify_only=False):
    project = project.resolve()
    if project == REPO or project in REPO.parents or REPO in project.parents:
        raise ValueError('PROFILE_REPOSITORY_OR_PROTECTED_SOURCE_WRITE_REFUSED')
    main_path = project/'lib/main.dart'
    store_path = project/'lib/deda_100377_my_store_page_staged.dart'
    if not main_path.is_file() or not store_path.is_file():
        raise ValueError('PROFILE_REQUIRES_COMPLETE_ASSEMBLED_DEDA')
    main, store = main_path.read_text(), store_path.read_text()
    if verify_only:
        verify(main, store)
    else:
        proposed_main, proposed_store = patched(main, store)
        # All anchors and cross-file safety checks passed before either write.
        main_path.write_text(proposed_main)
        store_path.write_text(proposed_store)
    return 'PASS_PROFILE_ORIGINAL_MY_STORE_SINGLE_OWNER_NO_NEW_UID_NO_WALLET_WRITES'


if __name__ == '__main__':
    p = argparse.ArgumentParser()
    p.add_argument('project', type=Path)
    p.add_argument('--verify-only', action='store_true')
    args = p.parse_args()
    print(bind(args.project, args.verify_only))
