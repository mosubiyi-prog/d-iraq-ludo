import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import 'deda_stage74_id_gift_service.dart';

/// A compact new section inside the ORIGINAL "هداياي" page. Old diamond
/// gift stream, claim buttons, balances and claim history remain unchanged.
class DedaStage74IdGiftsSection extends StatefulWidget {
  final String originalId;
  const DedaStage74IdGiftsSection({super.key, required this.originalId});

  @override
  State<DedaStage74IdGiftsSection> createState() =>
      _DedaStage74IdGiftsSectionState();
}

class _DedaStage74IdGiftsSectionState
    extends State<DedaStage74IdGiftsSection> {
  List<DedaStage74IdGift>? _gifts;
  bool _loading = false;
  String? _claimingId;
  Object? _claimToken; // One receipt callback belongs to one inbox lifetime.
  String? _error;
  int _generation = 0;
  // Stage2 profile: invalidate visible gifts immediately on Firebase UID rotation.
  StreamSubscription<User?>? _auth;
  String? _observedUid;
  // DEDA_100377_POINT08_GIFT_INBOX_FROZEN_FIREBASE_UID
  // A still-mounted gift inbox may outlive the signed-in recipient account.
  String? _verifiedUid;
  String? _currentUid() {
    try {
      if (Firebase.apps.isEmpty) return null;
      return FirebaseAuth.instance.currentUser?.uid;
    } catch (_) { return null; }
  }


  void _onAuthChanged(User? user) {
    final nextUid = user?.uid;
    if (nextUid == _observedUid) return;
    _observedUid = nextUid;
    ++_generation; // Reject every old in-flight read before any refresh.
    if (!mounted) return;
    setState(() {
      _loading = false;
      _claimingId = null;
      _claimToken = null;
      _gifts = null;
      _verifiedUid = null;
      _error = null;
    });
    // Existing owner verification remains authoritative; no new login/UID.
    if (nextUid != null) _refresh();
  }

  @override
  void initState() {
    super.initState();
    _observedUid = _currentUid();
    try {
      if (Firebase.apps.isNotEmpty) {
        _auth = FirebaseAuth.instance.authStateChanges().listen(_onAuthChanged);
      }
    } catch (_) {
      // Keep the existing no-Firebase/read-only fallback.
    }
    _refresh();
  }

  @override
  void didUpdateWidget(covariant DedaStage74IdGiftsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Point08: an old account's inbox must not remain visible while a new
    // account is being verified, even if the previous server read is pending.
    if (oldWidget.originalId != widget.originalId) {
      _generation++;
      _loading = false;
      _claimingId = null;
      _claimToken = null;
      _gifts = null;
      _verifiedUid = null;
      _error = null;
      _refresh();
    }
  }

  @override
  void dispose() {
    _generation++;
    _claimToken = null;
    _auth?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (!DedaStage74IdGiftService.enabled || _loading) return;
    final uid = _currentUid();
    if (uid == null) {
      _generation++;
      if (mounted) {
        setState(() {
          _gifts = null;
          _verifiedUid = null;
          _claimingId = null;
          _claimToken = null;
          _error = null;
        });
      }
      return;
    }
    final generation = ++_generation;
    final originalId = widget.originalId;
    setState(() {_loading = true; _error = null;});
    try {
      final gifts = await DedaStage74IdGiftService.load(originalId);
      if (!mounted || generation != _generation ||
          widget.originalId != originalId || _currentUid() != uid) return;
      _verifiedUid = uid;
      setState(() => _gifts = gifts);
    } catch (_) {
      if (mounted && generation == _generation &&
          _currentUid() == uid) {
        setState(() => _error =
            'تعذّر التحقق من هدايا المعرّفات. اضغط تحديث عند توفر الإنترنت.');
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() {
          _loading = false;
          if (_currentUid() != uid) {
            _gifts = null;
            _verifiedUid = null;
            _claimingId = null;
            _claimToken = null;
          }
        });
      }
    }
  }

  Future<void> _receive(DedaStage74IdGift gift, int rowGeneration) async {
    if (!mounted || _loading || rowGeneration != _generation) return;
    final uid = _currentUid();
    if (_claimingId != null || gift.received || uid == null ||
        _verifiedUid != uid || gift.originalId != widget.originalId) return;
    final originalId = widget.originalId;
    final token = Object();
    bool claimCurrent() => mounted && identical(_claimToken, token) &&
        widget.originalId == originalId && _currentUid() == uid;
    setState(() {
      _claimingId = gift.identifier;
      _claimToken = token;
    });
    try {
      await DedaStage74IdGiftService.receive(gift);
      // An expired receipt response cannot refresh or notify a newer inbox,
      // even after the UID returns to its original value.
      if (!claimCurrent()) return;
      await _refresh();
      if (claimCurrent()) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('تم استلام المعرّف وحفظه ضمن معرّفاتي.'),
        ));
      }
    } catch (_) {
      // A server readback is still the only proof of permanent reception.
      if (claimCurrent()) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('نتيجة الاستلام غير مؤكدة. حدّث القسم قبل المحاولة ثانية.'),
        ));
      }
    } finally {
      // Only this exact request can clear its own pending button.
      if (claimCurrent()) {
        setState(() {
          _claimingId = null;
          _claimToken = null;
        });
      }
    }
  }

  Widget _giftTile(DedaStage74IdGift gift) {
    final rowGeneration = _generation;
    return Card(
      key: ValueKey<String>('deda_stage74_gift_${gift.identifier}'),
      margin: const EdgeInsets.only(bottom: 7),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(children: [
          const Icon(Icons.card_giftcard, color: Color(0xFF8153BC)),
          const SizedBox(width: 8),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(gift.identifier,
                textDirection: TextDirection.ltr,
                style: const TextStyle(fontWeight: FontWeight.w900)),
              const Text('هدية معرّف مميز من إدارة DEDA',
                style: TextStyle(fontSize: 12)),
              Text(gift.received
                  ? 'مستلم ومحفوظ ضمن معرّفاتي'
                  : 'بانتظار استلامك — مجاني',
                style: const TextStyle(fontSize: 12)),
            ],
          )),
          if (gift.received)
            const Icon(Icons.verified, color: Color(0xFF256D3F))
          else
            FilledButton(
              key: ValueKey<String>('deda_stage74_receive_${gift.identifier}'),
              onPressed: !_loading && _claimingId == null
                  ? () => _receive(gift, rowGeneration) : null,
              child: Text(_claimingId == gift.identifier
                  ? 'انتظار' : 'استلام'),
            ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Old account gifts never remain visible after UID rotation.
    final visibleGifts = _verifiedUid != null &&
        _verifiedUid == _currentUid() ? _gifts : null;
    if (!DedaStage74IdGiftService.enabled) {
      return const SizedBox.shrink();
    }
    return Container(
      key: const Key('deda_stage74_identifier_gifts_in_hadaya'),
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F1FF),
        border: Border.all(color: const Color(0xFFD7C4EE)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch,children: [
        Row(children: [
          const Icon(Icons.wallet_giftcard, color: Color(0xFF7844A5)),
          const SizedBox(width: 8),
          const Expanded(child: Text('المعرّفات المميزة المستلمة',
            style: TextStyle(fontWeight: FontWeight.w900,fontSize: 15))),
          IconButton(
            key: const Key('deda_stage74_gift_inbox_refresh'),
            onPressed: _loading || _claimingId != null ? null : _refresh,
            icon: const Icon(Icons.refresh),
            tooltip: 'تحديث هدايا المعرّفات',
          ),
        ]),
        const Text(
          'استلم الآيدي هنا، ثم افتح «ملفي ← تعديل الملف ← معرّفاتي» '
          'لاستخدامه. يبقى الآيدي الأصلي محفوظًا.',
          style: TextStyle(fontSize: 12),
        ),
        if (_loading) const LinearProgressIndicator(),
        if (_error != null)
          Text(_error!, style: const TextStyle(color: Color(0xFFA03D3D))),
        if (!_loading && _error == null && (visibleGifts?.isEmpty ?? true))
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Text('ما عندك هدايا معرّفات مميزة حاليًا.'),
          ),
        if (visibleGifts != null && visibleGifts.isNotEmpty)
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 275),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: visibleGifts.length,
              itemBuilder: (context,i) => _giftTile(visibleGifts[i]),
            ),
          ),
      ]),
    );
  }
}
