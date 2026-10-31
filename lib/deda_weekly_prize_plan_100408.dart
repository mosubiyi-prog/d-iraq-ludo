import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
    final doc = await ref(weekId).get(const GetOptions(source: Source.server));
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
    if (uid == null || FirebaseAuth.instance.currentUser?.isAnonymous == true ||
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

class DedaAdminLeaguePrizeEditor extends StatefulWidget {
  const DedaAdminLeaguePrizeEditor({super.key});
  @override
  State<DedaAdminLeaguePrizeEditor> createState() => _DedaAdminLeaguePrizeEditorState();
}
class _DedaAdminLeaguePrizeEditorState extends State<DedaAdminLeaguePrizeEditor> {
  late Future<List<int>> _original;
  final _reason = TextEditingController();
  List<int> _edited = List.of(DedaWeeklyPrizePlan.minimum);
  bool _initialized = false, _saving = false;
  int _formVersion = 0;

  @override
  void initState() {
    super.initState();
    _original = DedaWeeklyPrizePlan.fetch(DedaWeeklyPrizePlan.thisWeekId);
  }
  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _save(String weekId) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await DedaWeeklyPrizePlan.increase(
        weekId: weekId,
        values: List<int>.from(_edited),
        reason: _reason.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حفظ زيادة الجوائز للأسبوع الحالي.')));
      setState(() {
        _original = DedaWeeklyPrizePlan.fetch(weekId);
        _initialized = false;
        _formVersion++;
      });
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(
          'لم تُحفظ الجوائز؛ تحقق من إيقاف الدوري وصلاحيات Firebase والأرقام.')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final weekId = DedaWeeklyPrizePlan.thisWeekId;
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection(
        'deda_weekly_direct_control').doc('active').snapshots(),
      builder: (context, control) {
        if (!control.hasData) return const LinearProgressIndicator();
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
                ? const Text('تعذر تأكيد خطة الجوائز من Firebase.')
                : const LinearProgressIndicator();
            if (!_initialized) {
              _edited = List<int>.from(snap.data!);
              _initialized = true;
            }
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
                  controller: _reason, maxLength: 200,
                  decoration: const InputDecoration(
                    labelText: 'سبب تعديل الجوائز (8 أحرف على الأقل)'),
                ),
                FilledButton.icon(
                  key: const Key('deda_gm_save_weekly_prize_increase'),
                  onPressed: _saving ? null : () => _save(weekId),
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
