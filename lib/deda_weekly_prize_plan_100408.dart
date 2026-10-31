import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'deda_backend.dart';
import 'deda_weekly_league_clock.dart';

/// A manager-approved weekly PRIZE PLAN only; NEVER a payout writer.
/// Existing real XP, claim receipts, real diamond wallets and Hadaya are
/// explicitly out of scope. Firestore rules independently require GM + pause.
class DedaWeeklyPrizePlan {
  static const minimum = <int>[150, 100, 50, 10, 10, 10, 10, 10, 10, 10];
  static final _db = FirebaseFirestore.instance;
  static const collection = 'deda_weekly_direct_prize_plans';

  static String get thisWeekId {
    final local = DedaWeeklyLeagueClock.at(DateTime.now().toUtc())
        .weekStart.add(const Duration(hours: 3));
    return '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  }

  static DocumentReference<Map<String, dynamic>> ref(String weekId) =>
      _db.collection(collection).doc(weekId);

  static List<int> amounts(Map<String, dynamic>? data) {
    final raw = data?['amounts'];
    if (raw is! List || raw.length != 10) return List.of(minimum);
    final values = <int>[];
    for (var index = 0; index < 10; index++) {
      final n = raw[index];
      if (n is! int || n < minimum[index] || n > 1000000) {
        return List.of(minimum);
      }
      values.add(n);
    }
    return values;
  }

  static Future<List<int>> fetch(String weekId) async {
    final doc = await ref(weekId).get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 12));
    return amounts(doc.data());
  }

  static Future<void> increase({
    required String weekId,
    required List<int> values,
    required String reason,
  }) async {
    if (weekId != thisWeekId ||
        !DedaWeeklyLeagueClock.at(DateTime.now().toUtc()).canAccumulate ||
        values.length != 10 ||
        reason.trim().length < 8 || reason.trim().length > 200) {
      throw StateError('invalid-week-prize-editor-input');
    }
    for (var i = 0; i < 10; i++) {
      if (values[i] < minimum[i] || values[i] > 1000000) {
        throw StateError('prize-cannot-decrease-below-original');
      }
    }
    final profile = await DedaBackend.currentAdminProfile(forceRefresh: true);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null ||
        DedaBackend.normalizeAdminRole(profile['role']) != 'general_manager' ||
        DedaBackend.normalizeAdminStatus(profile) != 'active') {
      throw StateError('active-manager-required');
    }
    final control = _db.collection('deda_weekly_direct_control').doc('active');
    final plan = ref(weekId);
    final event = _db.collection('deda_weekly_direct_admin_events').doc();
    await _db.runTransaction<void>((tx) async {
      final status = (await tx.get(control)).data();
      final previous = (await tx.get(plan)).data();
      if (status?['paused'] != true || status?['weekId'] != weekId ||
          thisWeekId != weekId ||
          FirebaseAuth.instance.currentUser?.uid != uid) {
        throw StateError('league-must-be-paused-by-manager');
      }
      final prior = amounts(previous);
      for (var i = 0; i < 10; i++) {
        if (values[i] < prior[i]) {
          throw StateError('only-increases-are-allowed');
        }
      }
      if (List.generate(10, (i) => values[i] == prior[i]).every((same) => same)) {
        throw StateError('no-prize-increases-requested');
      }
      tx.set(plan, <String, dynamic>{
        'weekId': weekId,
        'amounts': values,
        'reason': reason.trim(),
        'updatedBy': uid,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      tx.set(event, <String, dynamic>{
        'action': 'prizes_increase',
        'weekId': weekId, 'publicId': '',
        'reason': reason.trim(),
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': uid,
      });
    });
  }
}

/// The public league displays actual server-approved amounts; 10 places do
/// not receive any diamonds until an independent audited payout is activated.
class DedaWeeklyPrizeAmount extends StatelessWidget {
  const DedaWeeklyPrizeAmount({
    super.key, required this.place, this.color = Colors.white,
    this.fontSize = 12,
  });
  final int place;
  final Color color;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    if (place < 1 || place > 10) return const SizedBox.shrink();
    if (Firebase.apps.isEmpty) {
      return Text('💎 ${DedaWeeklyPrizePlan.minimum[place - 1]} ماسة',
        style: TextStyle(color: color, fontSize: fontSize));
    }
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: DedaWeeklyPrizePlan.ref(DedaWeeklyPrizePlan.thisWeekId).snapshots(),
      builder: (context, snapshot) {
        // Never display unverified pending local writes as saved prizes.
        final trusted = snapshot.hasData &&
            !snapshot.data!.metadata.hasPendingWrites;
        final values = trusted
            ? DedaWeeklyPrizePlan.amounts(snapshot.data!.data())
            : DedaWeeklyPrizePlan.minimum;
        return FittedBox(
          fit: BoxFit.scaleDown,
          child: Text('💎 ${values[place - 1]} ماسة',
            textDirection: TextDirection.rtl,
            style: TextStyle(color: color, fontSize: fontSize,
                fontWeight: FontWeight.w800)),
        );
      },
    );
  }
}

/// Always show the confirmed current-week plan, even after resuming; never
/// display a stale hardcoded total once the manager has raised an amount.
class DedaAdminLeaguePrizeSummary extends StatelessWidget {
  const DedaAdminLeaguePrizeSummary({super.key});

  Widget _amounts(List<int> values) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (var i=0; i<10; i++)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [Text('المركز ${i+1}'),
              Text('${values[i]} ماسة',
                style: const TextStyle(fontWeight: FontWeight.bold))],
          ),
        ),
      const Divider(),
      Text('إجمالي جوائز الأسبوع: ${values.fold<int>(0,(a,b)=>a+b)} ماسة',
        style: const TextStyle(fontWeight: FontWeight.bold)),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    if (Firebase.apps.isEmpty) return _amounts(DedaWeeklyPrizePlan.minimum);
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: DedaWeeklyPrizePlan.ref(DedaWeeklyPrizePlan.thisWeekId).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Text('تعذر تأكيد المبالغ الحالية من Firebase.');
        }
        if (!snapshot.hasData) return const LinearProgressIndicator();
        if (snapshot.data!.metadata.hasPendingWrites) {
          return const Text('جارِ تأكيد مبالغ الجوائز من الخادم...');
        }
        return _amounts(DedaWeeklyPrizePlan.amounts(snapshot.data!.data()));
      },
    );
  }
}

/// Local draft validation only. Does not authorize or write prizes.
class DedaPrizeDraftGuard100412 {
  static String? validate(List<int> proposed, List<int>? saved, String reason) {
    final text = reason.trim();
    if (text.length < 8 || text.length > 200) {
      return 'اكتب سبب تعديل الجوائز من 8 إلى 200 حرف.';
    }
    if (saved == null || proposed.length != 10 || saved.length != 10) {
      return 'جارِ تأكيد مبالغ الجوائز الحالية من الخادم.';
    }
    var raised = false;
    for (var i = 0; i < 10; i++) {
      if (proposed[i] < DedaWeeklyPrizePlan.minimum[i] ||
          proposed[i] > 1000000) {
        return 'تأكد أن مبالغ الجوائز ضمن الحدود المسموحة.';
      }
      if (proposed[i] < saved[i]) {
        return 'لا يمكن تخفيض مبلغ سبق اعتماده.';
      }
      if (proposed[i] > saved[i]) raised = true;
    }
    if (!raised) return 'ارفع جائزة مركز واحد على الأقل قبل الحفظ.';
    return null;
  }

  static String errorMessage(Object error) {
    if (error is FirebaseException) {
      switch (error.code) {
        case 'permission-denied':
          return 'رفض الخادم تعديل الجوائز. تحقق من صلاحية المدير العام.';
        case 'unavailable':
        case 'deadline-exceeded':
          return 'تعذر تأكيد الحفظ من الخادم. تحقق من الاتصال وحالة الجوائز قبل إعادة المحاولة.';
      }
    }
    final code = error.toString();
    if (code.contains('league-must-be-paused-by-manager')) {
      return 'لا يمكن الحفظ حتى يؤكد الخادم أن الدوري موقوف لهذا الأسبوع.';
    }
    if (code.contains('no-prize-increases-requested')) {
      return 'لا توجد زيادة جديدة لحفظها.';
    }
    if (code.contains('only-increases-are-allowed')) {
      return 'لا يمكن خفض جوائز سبق اعتمادها.';
    }
    if (code.contains('invalid-week-prize-editor-input')) {
      return 'انتهت صلاحية الأسبوع أو بيانات التعديل غير مكتملة.';
    }
    if (code.contains('active-manager-required')) {
      return 'صلاحية المدير العام غير مؤكدة؛ لم تنفذ عملية الحفظ.';
    }
    if (code.contains('timeout') || code.contains('unavailable')) {
      return 'تعذر التأكد من الحفظ الآن. راجع المبالغ الحالية قبل إعادة المحاولة.';
    }
    return 'تعذر تأكيد حفظ الجوائز. أعد قراءة الخطة ثم حاول مرة أخرى.';
  }
}

class DedaAdminLeaguePrizeEditor extends StatefulWidget {
  const DedaAdminLeaguePrizeEditor({super.key});
  @override
  State<DedaAdminLeaguePrizeEditor> createState() => _DedaAdminLeaguePrizeEditorState();
}
class _DedaAdminLeaguePrizeEditorState extends State<DedaAdminLeaguePrizeEditor> {
  late Future<List<int>> _original;
  late final Stream<DocumentSnapshot<Map<String, dynamic>>>? _controlStream;
  late final String _openedWeekId;
  final _reason = TextEditingController();
  List<int> _edited = List.of(DedaWeeklyPrizePlan.minimum);
  List<int>? _lastConfirmed;
  String? _errorMessage;
  bool _initialized = false, _saving = false;
  int _formVersion = 0;

  @override
  void initState() {
    super.initState();
    _openedWeekId = DedaWeeklyPrizePlan.thisWeekId;
    final ready = Firebase.apps.isNotEmpty;
    // An inline snapshots() call in build creates a NEW stream on every
    // keystroke/setState. That discards the form and may lose typed values.
    _controlStream = ready
        ? FirebaseFirestore.instance.collection('deda_weekly_direct_control')
            .doc('active').snapshots(includeMetadataChanges: true)
        : null;
    _original = ready
        ? DedaWeeklyPrizePlan.fetch(_openedWeekId)
        : Future.value(List.of(DedaWeeklyPrizePlan.minimum));
    _reason.addListener(_reasonChanged);
  }

  void _reasonChanged() {
    if (!mounted) return;
    setState(() => _errorMessage = null);
  }

  void _retryRead() {
    if (_saving) return;
    setState(() {
      _original = DedaWeeklyPrizePlan.fetch(_openedWeekId);
      _initialized = false;
      _lastConfirmed = null;
      _errorMessage = null;
    });
  }
  @override
  void dispose() {
    _reason.removeListener(_reasonChanged);
    _reason.dispose();
    super.dispose();
  }

  Future<void> _save(String weekId) async {
    if (_saving) return;
    final problem = DedaPrizeDraftGuard100412.validate(
        _edited, _lastConfirmed, _reason.text);
    if (problem != null) {
      setState(() => _errorMessage = problem);
      return; // Invalid drafts must NOT attempt any Firebase write.
    }
    if (weekId != _openedWeekId) {
      setState(() => _errorMessage =
          'بدأ أسبوع جديد؛ أغلق هذه الصفحة وافتحها لتأكيد جوائزه.');
      return;
    }
    setState(() {
      _saving = true;
      _errorMessage = null;
    });
    try {
      // No automatic write retry: a slow transaction may commit after timeout.
      await DedaWeeklyPrizePlan.increase(
        weekId: weekId,
        values: List<int>.from(_edited),
        reason: _reason.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حفظ زيادة الجوائز للأسبوع الحالي.')));
      setState(() {
        _original = DedaWeeklyPrizePlan.fetch(weekId);
        _initialized = false;
        _lastConfirmed = null;
        _formVersion++;
      });
    } catch (error) {
      if (mounted) setState(() =>
          _errorMessage = DedaPrizeDraftGuard100412.errorMessage(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (Firebase.apps.isEmpty) return const Text('إدارة الجوائز تحتاج اتصال Firebase.');
    final weekId = DedaWeeklyPrizePlan.thisWeekId;
    if (weekId != _openedWeekId) {
      return const Text('بدأ أسبوع جديد؛ أعد فتح إدارة الجوائز لتحديث البيانات.');
    }
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _controlStream,
      builder: (context, control) {
        if (control.hasError) {
          return const Text('تعذر التحقق من حالة إيقاف الدوري من Firebase.');
        }
        if (!control.hasData) return const LinearProgressIndicator();
        // A cache-only "paused" flag cannot authorize a new prize write.
        if (control.data!.metadata.hasPendingWrites ||
            control.data!.metadata.isFromCache) {
          return const Text('جارِ تأكيد إيقاف الدوري من الخادم...');
        }
        final c = control.data!.data();
        final paused = c?['weekId'] == weekId && c?['paused'] == true;
        if (!paused) {
          return const Text('لتعديل الجوائز، أوقف الدوري مؤقتاً أولاً. '
              'لا يتأثر رصيد أي مستخدم قبل التوزيع.');
        }
        return FutureBuilder<List<int>>(
          future: _original,
          builder: (context, snap) {
            if (!snap.hasData) return snap.hasError
                ? Column(children: [
                    const Text('تعذر تأكيد خطة الجوائز من Firebase.'),
                    TextButton(onPressed: _retryRead,
                      child: const Text('إعادة قراءة الجوائز')),
                  ])
                : const LinearProgressIndicator();
            if (!_initialized) {
              _edited = List<int>.from(snap.data!);
              _initialized = true;
            }
            _lastConfirmed = List<int>.from(snap.data!);
            final formError = DedaPrizeDraftGuard100412.validate(
                _edited, _lastConfirmed, _reason.text);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('تعديل زيادة الجوائز للمراكز العشرة فقط أثناء الإيقاف.'),
                const SizedBox(height: 8),
                for (var i = 0; i < 10; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(children: [
                      SizedBox(width: 85, child: Text('المركز ${i+1}')),
                      Expanded(child: TextFormField(
                        key: ValueKey('deda_prize_${weekId}_${_formVersion}_${i}'),
                        initialValue: '${_edited[i]}',
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          suffixText: 'ماسة', isDense: true,
                          border: OutlineInputBorder()),
                        onChanged: (text) => setState(() {
                          _edited[i] = int.tryParse(text) ?? 0;
                        }),
                      )),
                    ]),
                  ),
                const SizedBox(height: 6),
                Text('إجمالي الجوائز: ${_edited.fold<int>(0, (a, b) => a+b)} ماسة'),
                TextField(
                  key: const Key('deda_100412_prize_reason'),
                  controller: _reason, maxLength: 200,
                  decoration: const InputDecoration(
                    labelText: 'سبب تعديل الجوائز (8 أحرف على الأقل)'),
                ),
                if (_errorMessage != null)
                  Text(_errorMessage!,
                      style: const TextStyle(color: Colors.red)),
                if (formError != null && _errorMessage == null)
                  Text(formError,
                      style: const TextStyle(color: Colors.deepOrange)),
                FilledButton.icon(
                  key: const Key('deda_gm_save_weekly_prize_increase'),
                  onPressed: _saving || formError != null
                      ? null : () => _save(weekId),
                  icon: const Icon(Icons.save_outlined),
                  label: Text(_saving ? 'جارِ التحقق والحفظ...' : 'حفظ زيادة الجوائز'),
                ),
                const Text('هذه خطة جوائز فقط؛ لا تُصرف ماسات قبل اعتماد '
                    'نتائج الأسبوع وتنفيذ التوزيع الآمن.',
                  style: TextStyle(fontSize: 11)),
              ],
            );
          },
        );
      },
    );
  }
}
