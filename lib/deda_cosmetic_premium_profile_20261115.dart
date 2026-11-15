/// STEP 2 — owner-verified PREMIUM COSMETIC ONLY, in the existing profile slot.
/// No calls to Stage71.use, active(), server alias publication or UID changes.
/// Original ID remains the canonical ID for every backend operation.
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'deda_stage71_free_owned_use_profile.dart'
    show DedaStage71OwnedIdentifier, DedaStage71OwnedIdentifierService;
import 'deda_stage74_id_gift_service.dart';
import 'main.dart' show DedaPremiumIdCard, DedaPremiumIdCardColor;

/// A local, UID-and-original-scoped *visual preference*, not an active alias.
/// Only the cosmetic widgets read this key. No backend code reads it.
class DedaCosmeticPremiumChoice20261115 {
  DedaCosmeticPremiumChoice20261115._();

  static final Map<String, ValueNotifier<int>> _revisions = {};

  static String _key(String uid, String original) =>
      'deda_cosmetic_premium_profile_v1_${uid}_${original}';

  static ValueNotifier<int> revisions(String uid, String original) =>
      _revisions.putIfAbsent(_key(uid, original), () => ValueNotifier<int>(0));

  static Future<String?> read(String uid, String original) async {
    if (Firebase.apps.isEmpty ||
        FirebaseAuth.instance.currentUser?.uid != uid) {
      return null;
    }
    final preferences = await SharedPreferences.getInstance();
    if (FirebaseAuth.instance.currentUser?.uid != uid) return null;
    final selected = preferences.getString(_key(uid, original));
    return selected == null || selected == original || selected.isEmpty
        ? null : selected;
  }

  static Future<void> select(
    String uid, String original, String? cosmeticId,
  ) async {
    if (Firebase.apps.isEmpty ||
        FirebaseAuth.instance.currentUser?.uid != uid) {
      throw StateError('cosmetic-owner-changed');
    }
    final preferences = await SharedPreferences.getInstance();
    if (FirebaseAuth.instance.currentUser?.uid != uid) {
      throw StateError('cosmetic-owner-changed-before-save');
    }
    final key = _key(uid, original);
    final ok = cosmeticId == null
        ? await preferences.remove(key)
        : await preferences.setString(key, cosmeticId);
    if (!ok) throw StateError('cosmetic-choice-not-saved');
    // If auth rotated after saving, only the old UID's own local entry changed.
    // Its new owner never sees the old entry; no backend record was written.
    if (FirebaseAuth.instance.currentUser?.uid != uid) return;
    revisions(uid, original).value++;
  }
}

/// Verified entitlement only: real server grant + accepted receipt when gifted.
/// Never infers ownership from a local choice or an old server active alias.
class DedaCosmeticPremiumEntitlements20261115 {
  DedaCosmeticPremiumEntitlements20261115._();

  static Future<List<DedaStage71OwnedIdentifier>> accepted(
    String uid, String original,
  ) async {
    if (Firebase.apps.isEmpty ||
        FirebaseAuth.instance.currentUser?.uid != uid) {
      throw StateError('cosmetic-owner-unavailable');
    }
    // owned() proves original ownership against server records and validates
    // the 200-ID registry. A cosmetic preference does not satisfy this proof.
    final inventory = await DedaStage71OwnedIdentifierService.owned(original);
    if (FirebaseAuth.instance.currentUser?.uid != uid) {
      throw StateError('cosmetic-owner-changed-after-registry');
    }
    final accepted = <DedaStage71OwnedIdentifier>[];
    for (final item in inventory) {
      if (item.kind == 'gifted' &&
          !await DedaStage74IdGiftService.isReceived(
            original, item.identifier,
          )) {
        continue;
      }
      if (FirebaseAuth.instance.currentUser?.uid != uid) {
        throw StateError('cosmetic-owner-changed-after-receipt');
      }
      accepted.add(item);
    }
    if (FirebaseAuth.instance.currentUser?.uid != uid) {
      throw StateError('cosmetic-owner-changed-after-inventory');
    }
    return List<DedaStage71OwnedIdentifier>.unmodifiable(accepted);
  }
}

/// Same personal-profile placement/height as Stage71's former premium foil.
/// Original fallback is painted immediately, even without Firebase/network.
/// A verified, locally activated premium only replaces the *artwork*.
class DedaCosmeticPremiumProfileFoil20261115 extends StatefulWidget {
  final String originalId;
  final Widget fallback;
  const DedaCosmeticPremiumProfileFoil20261115({
    super.key, required this.originalId, required this.fallback,
  });

  @override
  State<DedaCosmeticPremiumProfileFoil20261115> createState() =>
      _DedaCosmeticPremiumProfileFoil20261115State();
}

class _DedaCosmeticPremiumProfileFoil20261115State
    extends State<DedaCosmeticPremiumProfileFoil20261115> {
  StreamSubscription<User?>? _auth;
  ValueNotifier<int>? _selection;
  String? _selectedUid;
  DedaStage71OwnedIdentifier? _approved;
  int _generation = 0;

  String? _uid() {
    try {
      return Firebase.apps.isEmpty ? null : FirebaseAuth.instance.currentUser?.uid;
    } catch (_) {
      return null;
    }
  }

  void _listenChoice() {
    final uid = _uid();
    if (_selectedUid == uid && _selection != null) return;
    _selection?.removeListener(_load);
    _selectedUid = uid;
    _selection = uid == null ? null :
        DedaCosmeticPremiumChoice20261115.revisions(uid, widget.originalId);
    _selection?.addListener(_load);
  }

  @override
  void initState() {
    super.initState();
    _listenChoice();
    if (Firebase.apps.isNotEmpty) {
      _auth = FirebaseAuth.instance.authStateChanges().listen((_) {
        if (!mounted) return;
        _listenChoice();
        _load();
      });
    }
    _load();
  }

  @override
  void didUpdateWidget(covariant DedaCosmeticPremiumProfileFoil20261115 old) {
    super.didUpdateWidget(old);
    if (old.originalId != widget.originalId) {
      // Same UID but different original requires a different local key.
      _selectedUid = null;
      _listenChoice();
      _load();
    }
  }

  Future<void> _load() async {
    final epoch = ++_generation;
    final uid = _uid();
    final original = widget.originalId;
    if (mounted && _approved != null) {
      setState(() => _approved = null);
    }
    if (uid == null) return;
    try {
      final chosen = await
          DedaCosmeticPremiumChoice20261115.read(uid, original);
      if (chosen == null) return; // Original is ALWAYS the default.
      final allowed = await
          DedaCosmeticPremiumEntitlements20261115.accepted(uid, original);
      if (!mounted || epoch != _generation ||
          _uid() != uid || widget.originalId != original) return;
      for (final item in allowed) {
        if (item.identifier == chosen) {
          setState(() => _approved = item);
          return;
        }
      }
      // Removed/unreceived ownership => original fallback; never forge grants.
    } catch (_) {
      // Missing server proof only affects optional cosmetic art.
    }
  }

  @override
  void dispose() {
    ++_generation;
    _selection?.removeListener(_load);
    _auth?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final premium = _uid() != null &&
            _uid() == _selectedUid &&
            _approved?.recipientOriginalId == widget.originalId
        ? _approved : null;
    if (premium == null) return widget.fallback;
    final color = DedaPremiumIdCardColor.values.firstWhere(
      (c) => c.name == premium.baseColor,
    );
    // Intentionally NO tap/copy/search/share handler on premium artwork.
    return DedaPremiumIdCard(
      key: const Key('deda_cosmetic_premium_profile_only'),
      identifier: premium.identifier,
      color: color,
      height: 50,
    );
  }
}

/// Replaces ONLY the owner's old Stage71 panel, in the SAME existing slot.
/// Buttons persist a cosmetic choice locally; they NEVER invoke Stage71.use.
class DedaCosmeticPremiumSelectorPanel20261115 extends StatefulWidget {
  final String originalId;
  const DedaCosmeticPremiumSelectorPanel20261115({
    super.key, required this.originalId,
  });

  @override
  State<DedaCosmeticPremiumSelectorPanel20261115> createState() =>
      _DedaCosmeticPremiumSelectorPanel20261115State();
}

class _DedaCosmeticPremiumSelectorPanel20261115State
    extends State<DedaCosmeticPremiumSelectorPanel20261115> {
  StreamSubscription<User?>? _auth;
  List<DedaStage71OwnedIdentifier>? _owned;
  String? _verifiedUid;
  String? _cosmetic;
  bool _busy = false;
  bool _failed = false;
  int _generation = 0;

  String? _uid() {
    try {
      return Firebase.apps.isEmpty ? null : FirebaseAuth.instance.currentUser?.uid;
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    if (Firebase.apps.isNotEmpty) {
      _auth = FirebaseAuth.instance.authStateChanges().listen((_) {
        if (mounted) _load();
      });
    }
    _load();
  }

  @override
  void didUpdateWidget(covariant DedaCosmeticPremiumSelectorPanel20261115 old) {
    super.didUpdateWidget(old);
    if (old.originalId != widget.originalId) _load();
  }

  Future<void> _load() async {
    final epoch = ++_generation;
    final uid = _uid();
    final original = widget.originalId;
    if (mounted) {
      setState(() {
        _owned = null;
        _verifiedUid = null;
        _cosmetic = null;
        _failed = false;
      });
    }
    if (uid == null) return;
    try {
      final rows = await
          DedaCosmeticPremiumEntitlements20261115.accepted(uid, original);
      final chosen = await
          DedaCosmeticPremiumChoice20261115.read(uid, original);
      if (!mounted || epoch != _generation || _uid() != uid ||
          widget.originalId != original) return;
      setState(() {
        _verifiedUid = uid;
        _owned = rows;
        _cosmetic = rows.any((r) => r.identifier == chosen) ? chosen : null;
      });
    } catch (_) {
      if (mounted && epoch == _generation && _uid() == uid) {
        setState(() => _failed = true);
      }
    }
  }

  Future<void> _choose(String? candidate) async {
    if (_busy) return;
    final uid = _uid();
    final original = widget.originalId;
    if (uid == null) return;
    final epoch = ++_generation;
    setState(() => _busy = true);
    try {
      if (candidate != null) {
        // Fresh server proof immediately before cosmetic activation.
        final rows = await
            DedaCosmeticPremiumEntitlements20261115.accepted(uid, original);
        if (!rows.any((row) => row.identifier == candidate)) {
          throw StateError('cosmetic-premium-not-owned-or-received');
        }
      }
      if (!mounted || epoch != _generation || _uid() != uid ||
          widget.originalId != original) return;
      await DedaCosmeticPremiumChoice20261115.select(
        uid, original, candidate,
      );
      if (!mounted || epoch != _generation || _uid() != uid ||
          widget.originalId != original) return;
      setState(() => _cosmetic = candidate);
    } catch (_) {
      if (mounted && epoch == _generation && _uid() == uid) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('تعذّر حفظ اختيار الزينة. حدّث المعرفات وحاول ثانية.'),
        ));
      }
    } finally {
      if (mounted && epoch == _generation) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  void dispose() {
    ++_generation;
    _auth?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final owner = _uid() == _verifiedUid;
    final rows = owner ? _owned : null;
    final selected = owner ? _cosmetic : null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              const Expanded(child: Text('معرّفاتي • زينة الملف الشخصي',
                  style: TextStyle(fontWeight: FontWeight.bold))),
              IconButton(onPressed: _busy ? null : _load,
                  icon: const Icon(Icons.refresh)),
            ]),
            const Text('المعرّف الأصلي هو المعتمد لكل الوظائف؛ '
                'تفعيل المميز يغيّر الشكل هنا فقط.'),
            ListTile(
              key: const Key('deda_cosmetic_original_permanent_row'),
              dense: true,
              title: Text(widget.originalId,
                  textDirection: TextDirection.ltr),
              subtitle: const Text('المعرّف الأصلي • محفوظ دائماً'),
              trailing: OutlinedButton(
                onPressed: _busy || selected == null ? null :
                    () => _choose(null),
                child: Text(selected == null ? 'الأصلي ظاهر' : 'إظهار الأصلي'),
              ),
            ),
            if (!owner) Text(_failed
                ? 'تعذّر التحقق من ملكية المميز؛ الأصلي يبقى ظاهراً'
                : 'ملكية المميز بانتظار التحقق من الخادم'),
            if (owner && rows == null)
              const Text('جارِ تحميل المعرّفات المملوكة'),
            if (rows != null && rows.isEmpty)
              const Text('لا توجد معرّفات مميزة مملوكة ومؤكدة'),
            for (final premium in rows ?? <DedaStage71OwnedIdentifier>[])
              ListTile(
                dense: true,
                title: Text(premium.identifier,
                    textDirection: TextDirection.ltr),
                subtitle: const Text('للعرض الجمالي داخل الملف فقط'),
                trailing: OutlinedButton(
                  onPressed: _busy || selected == premium.identifier
                      ? null : () => _choose(premium.identifier),
                  child: Text(selected == premium.identifier
                      ? 'مفعّل للزينة' : 'تفعيل للزينة'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
