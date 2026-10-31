import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'deda_admin_league_controls.dart';
import 'deda_admin_league_live_data.dart';
import 'deda_weekly_league_clock.dart';

Future<String?> _dedaAdminReason(BuildContext context, String title) async {
  final controller = TextEditingController();
  try {
    return await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller, autofocus: true, maxLength: 200,
          minLines: 2, maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'سبب القرار (8 أحرف على الأقل)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog),
              child: const Text('إلغاء')),
          FilledButton(
            onPressed: () {
              final reason = controller.text.trim();
              if (reason.length >= 8 && reason.length <= 200) {
                Navigator.pop(dialog, reason);
              }
            },
            child: const Text('تأكيد'),
          ),
        ],
      ),
    );
  } finally {
    controller.dispose();
  }
}

/// GM verified by original admin screen AND service before every write;
/// Firestore Rules also require role general_manager and active status.
class DedaAdminLeagueControlPanel extends StatelessWidget {
  const DedaAdminLeagueControlPanel({super.key});
  @override
  Widget build(BuildContext context) {
    final service = DedaAdminLeagueControls();
    final phase = DedaWeeklyLeagueClock.at(DateTime.now().toUtc());
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: service.control.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Text('تعذر قراءة إعدادات الدوري. التحكم غير متاح.');
        }
        if (!snapshot.hasData) return const LinearProgressIndicator();
        final nowWeek = DedaAdminLeagueLiveData.weekId(phase.weekStart);
        final record = snapshot.data!.data();
        final paused = record?['paused'] == true &&
            record?['weekId'] == nowWeek;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(paused ? 'الدوري موقوف يدوياً من الإدارة' :
                phase.phase == DedaWeeklyPhase.frozen
                  ? 'الدوري متجمد بنهاية الأسبوع حتى 6 صباحاً'
                  : phase.phase == DedaWeeklyPhase.beforeFirstWeek
                    ? 'يبدأ الدوري الأول الساعة 6 صباحاً'
                    : 'الدوري جارٍ وفق الجدول الأسبوعي'),
            const SizedBox(height: 7),
            const Text('التحكم لا يغيّر موعد 6 صباحاً، ولا نقاط المستوى.'),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 6, children: [
              ElevatedButton.icon(
                key: const Key('deda_admin_league_resume'),
                onPressed: paused ? () async {
                  final reason = await _dedaAdminReason(context,
                    'سبب إعادة تشغيل الدوري');
                  if (reason == null || !context.mounted) return;
                  try {
                    await service.setPaused(paused: false, reason: reason);
                  } catch (_) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text(
                          'تعذر تنفيذ الأمر. تأكد من صلاحيات المدير العام.')));
                    }
                  }
                } : null,
                icon: const Icon(Icons.play_arrow),
                label: const Text('استئناف الدوري'),
              ),
              OutlinedButton.icon(
                key: const Key('deda_admin_league_pause'),
                onPressed: !paused ? () async {
                  final reason = await _dedaAdminReason(context,
                    'سبب إيقاف تسجيل نقاط الدوري');
                  if (reason == null || !context.mounted) return;
                  try {
                    await service.setPaused(paused: true, reason: reason);
                  } catch (_) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text(
                          'تعذر تنفيذ الأمر. تأكد من صلاحيات المدير العام.')));
                    }
                  }
                } : null,
                icon: const Icon(Icons.pause_circle_outline),
                label: const Text('إيقاف الدوري مؤقتاً'),
              ),
            ]),
          ],
        );
      },
    );
  }
}

class DedaAdminLeagueFreezePanel extends StatefulWidget {
  const DedaAdminLeagueFreezePanel({super.key});
  @override
  State<DedaAdminLeagueFreezePanel> createState() =>
      _DedaAdminLeagueFreezePanelState();
}

class _DedaAdminLeagueFreezePanelState
    extends State<DedaAdminLeagueFreezePanel> {
  String? _selectedWeek;
  Stream<List<DedaAdminLeagueRow>>? _scores;

  List<String> _weekChoices(DateTime now) {
    final clock = DedaWeeklyLeagueClock.at(now);
    if (clock.phase == DedaWeeklyPhase.beforeFirstWeek) return const [];
    final ids = <String>[];
    for (var n = 0; n <= 12; n++) {
      final start = clock.weekStart.subtract(Duration(days: 7 * n));
      if (start.isBefore(DedaWeeklyLeagueClock.origin)) break;
      ids.add(DedaAdminLeagueLiveData.weekId(start));
    }
    return ids;
  }

  @override
  void initState() {
    super.initState();
    final weeks = _weekChoices(DateTime.now().toUtc());
    if (weeks.isNotEmpty) _choose(weeks.first);
  }

  void _choose(String weekId) {
    _selectedWeek = weekId;
    _scores = DedaAdminLeagueLiveData().scoresForWeek(weekId);
  }

  @override
  Widget build(BuildContext context) {
    final options = _weekChoices(DateTime.now().toUtc());
    if (options.isEmpty) {
      return const Text('لا يوجد مشاركون بعد؛ يبدأ الدوري الساعة 6 صباحاً.');
    }
    final weekId = options.contains(_selectedWeek)
        ? _selectedWeek! : options.first;
    if (_selectedWeek != weekId) _choose(weekId);
    final manager = DedaAdminLeagueControls();
    return Column(children: [
      Row(children: [
        const Text('الأسبوع للمراجعة'),
        const SizedBox(width: 12),
        Expanded(child: DropdownButton<String>(
          key: const Key('deda_gm_freeze_selected_week'),
          isExpanded: true,
          value: weekId,
          items: [
            for (final id in options)
              DropdownMenuItem(value: id, child: Text(id)),
          ],
          onChanged: (id) {
            if (id == null || id == _selectedWeek) return;
            setState(() => _choose(id));
          },
        )),
      ]),
      const SizedBox(height: 8),
      const Text('التجميد يمنع زيادة نقاط الدوري للمستخدم، '
          'ويؤجل جائزته. نقاط المستوى والماسات الأصلية لا تتغير.'),
      StreamBuilder<List<DedaAdminLeagueRow>>(
        stream: _scores,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Text('تعذر قراءة حسابات الدوري للمراجعة.');
          }
          if (!snapshot.hasData) return const LinearProgressIndicator();
          if (snapshot.data!.isEmpty) {
            return const Text('لا يوجد مشاركون لهذا الأسبوع.');
          }
          return Column(children: [
            for (final row in snapshot.data!)
              _DedaAdminFrozenPlayerRow(
                key: ValueKey('$weekId:${row.publicId}'),
                weekId: weekId, row: row, service: manager,
              ),
          ]);
        },
      ),
    ]);
  }
}

class _DedaAdminFrozenPlayerRow extends StatelessWidget {
  const _DedaAdminFrozenPlayerRow({
    super.key, required this.weekId, required this.row,
    required this.service,
  });
  final String weekId;
  final DedaAdminLeagueRow row;
  final DedaAdminLeagueControls service;

  @override
  Widget build(BuildContext context) {
    final ref = service.review(weekId, row.publicId);
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: ref.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return const Text('تعذر عرض حالة المراجعة');
        if (!snapshot.hasData) return const LinearProgressIndicator();
        final frozen = snapshot.data!.data()?['frozen'] == true;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(children: [
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${row.place}. ${row.name}',
                  maxLines: 1, overflow: TextOverflow.ellipsis),
                Text('${row.publicId} — ${row.xp} XP',
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(fontSize: 11)),
                if (frozen)
                  const Text('قيد المراجعة', style: TextStyle(
                    color: Colors.deepOrange, fontWeight: FontWeight.bold)),
              ],
            )),
            const SizedBox(width: 7),
            TextButton.icon(
              onPressed: () async {
                final reason = await _dedaAdminReason(context,
                  frozen ? 'سبب رفع تجميد نقاط المستخدم'
                         : 'سبب تجميد نقاط المستخدم');
                if (reason == null || !context.mounted) return;
                try {
                  await service.setFrozen(
                    weekId: weekId, publicId: row.publicId,
                    frozen: !frozen, reason: reason,
                  );
                } catch (_) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text(
                        'تعذر تنفيذ مراجعة نقاط الدوري.')));
                  }
                }
              },
              icon: Icon(frozen ? Icons.lock_open : Icons.lock_clock),
              label: Text(frozen ? 'رفع التجميد' : 'تجميد'),
            ),
          ]),
        );
      },
    );
  }
}
