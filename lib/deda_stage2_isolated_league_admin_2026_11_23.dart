import 'package:flutter/material.dart';

import 'deda_admin_league_live_data.dart';
import 'deda_stage2_isolated_admin_identity_2026_11_21.dart';
import 'deda_weekly_league_clock.dart';

/// The original weekly league tile under SECONDARY administrative Auth only.
/// Never uses public Firebase, pays a prize, or changes original level XP.
class DedaStage2IsolatedLeagueAdminPage extends StatefulWidget {
  const DedaStage2IsolatedLeagueAdminPage({
    super.key, required this.admin, required this.dedaPhone,
    required this.isArabic,
  });
  final DedaIsolatedAdminIdentity admin;
  final String dedaPhone;
  final bool isArabic;
  @override
  State<DedaStage2IsolatedLeagueAdminPage> createState() =>
      _DedaStage2IsolatedLeagueAdminPageState();
}

class _DedaStage2IsolatedLeagueAdminPageState
    extends State<DedaStage2IsolatedLeagueAdminPage>
    with WidgetsBindingObserver {
  late Future<Map<String, dynamic>> _data;
  late Future<List<Map<String, dynamic>>> _archive;
  late Future<Map<String, dynamic>> _register;
  late String _registerWeek;
  late String _month;
  String? _reviewWeek;
  bool _busy = false;
  String t(String ar,String en) => widget.isArabic ? ar : en;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final months = DedaAdminLeagueLiveData.archiveMonths(DateTime.now().toUtc());
    _month = months.isEmpty ? '' : months.first;
    final completed = _completedWeeks();
    _registerWeek = completed.isEmpty ? '' : completed.first;
    _reload();
  }
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) setState(_reload);
  }
  List<String> _completedWeeks() {
    final clock = DedaWeeklyLeagueClock.at(DateTime.now().toUtc());
    if (clock.phase == DedaWeeklyPhase.beforeFirstWeek) return const [];
    return [
      for (var i = 1; i <= 12; i++)
        if (!clock.weekStart.subtract(Duration(days: 7 * i))
            .isBefore(DedaWeeklyLeagueClock.origin))
          DedaAdminLeagueLiveData.weekId(
            clock.weekStart.subtract(Duration(days: 7 * i))),
    ];
  }
  void _reload() {
    _data = widget.admin.readScopedLeague(
      dedaPhone: widget.dedaPhone, weekForReview: _reviewWeek);
    _register = _registerWeek.isEmpty
        ? Future.value(<String,dynamic>{
            'week':'','rows':<Map<String,dynamic>>[]})
        : widget.admin.readScopedLeaguePrizeRegister(
            dedaPhone: widget.dedaPhone, weekId: _registerWeek);
    _archive = _month.isEmpty
        ? Future.value(const <Map<String, dynamic>>[])
        : widget.admin.readScopedLeagueArchive(
            dedaPhone: widget.dedaPhone, month: _month);
  }
  void _refresh() { if (!_busy) setState(_reload); }
  List<String> _weeks() {
    final clock = DedaWeeklyLeagueClock.at(DateTime.now().toUtc());
    if (clock.phase == DedaWeeklyPhase.beforeFirstWeek) return const [];
    return [
      for (var i = 0; i <= 12; i++)
        if (!clock.weekStart.subtract(Duration(days: 7 * i))
            .isBefore(DedaWeeklyLeagueClock.origin))
          DedaAdminLeagueLiveData.weekId(
            clock.weekStart.subtract(Duration(days: 7 * i))),
    ];
  }
  Future<String?> _askReason(String title) async {
    final input = TextEditingController();
    try {
      return await showDialog<String>(context: context,
          builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(controller: input, minLines: 2, maxLines: 4,
          maxLength: 200, decoration: InputDecoration(
            labelText: t('سبب القرار (8–200 حرف)', 'Reason (8–200 characters)'))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
              child: Text(t('إلغاء', 'Cancel'))),
          FilledButton(onPressed: () {
            final why = input.text.trim();
            if (why.length >= 8 && why.length <= 200 &&
                !why.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
              Navigator.pop(ctx, why);
            }
          }, child: Text(t('تأكيد', 'Confirm'))),
        ],
      ));
    } finally { input.dispose(); }
  }
  Future<void> _action(Future<void> Function() run) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await run();
      if (mounted) {
        setState(_reload);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t(
          'تم إرسال القرار. راجع الحالة الفعلية بعد التحديث.',
          'Decision submitted. Verify actual state after refresh.'))));
      }
    } catch (_) {
      if (mounted) {
        setState(_reload);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t(
          'تعذّر تأكيد القرار؛ راجع الصلاحيات وسجل الإدارة.',
          'Decision unconfirmed; check permissions and audit.'))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
  Future<void> _pause(bool paused) async {
    final why = await _askReason(paused
      ? t('سبب إيقاف الدوري', 'Reason to pause league')
      : t('سبب استئناف الدوري', 'Reason to resume league'));
    if (!mounted || why == null) return;
    await _action(() => widget.admin.setScopedLeaguePaused(
      dedaPhone: widget.dedaPhone, paused: paused, reason: why));
  }
  Future<void> _freeze(String week,String publicId,bool freeze) async {
    final why = await _askReason(freeze
      ? t('سبب تجميد نقاط الدوري', 'Reason to freeze league XP')
      : t('سبب رفع التجميد', 'Reason to release hold'));
    if (!mounted || why == null) return;
    await _action(() => widget.admin.setScopedLeagueFrozen(
      dedaPhone: widget.dedaPhone, weekId: week, publicId: publicId,
      frozen: freeze, reason: why));
  }
  Widget _panel(String title,Widget child) => Card(
    margin: const EdgeInsets.symmetric(vertical: 6),
    child: Padding(padding: const EdgeInsets.all(12), child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(title, style: const TextStyle(
          fontSize: 15, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8), child,
      ],
    )));
  Widget _rows(List<Map<String,dynamic>> rows,
      {bool editable = false,String week = ''}) {
    if (rows.isEmpty) return Text(t('لا توجد نتائج موثّقة.',
        'No verified league results.'));
    return Column(children: [
      for (final r in rows.take(editable ? 100 : 10))
        ListTile(dense: true, contentPadding: EdgeInsets.zero,
          leading: Text(r['place'].toString() + '.'),
          title: Text((r['name'] ?? '').toString(),
            maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text((r['id'] ?? '').toString() + ' • ' +
            (r['xp'] ?? '').toString() + ' XP'),
          trailing: editable ? TextButton.icon(
            onPressed: _busy ? null : () => _freeze(
              week, r['id'] as String, r['frozen'] != true),
            icon: Icon(r['frozen'] == true
              ? Icons.lock_open : Icons.lock_clock_outlined),
            label: Text(r['frozen'] == true
              ? t('رفع التجميد', 'Unfreeze') : t('تجميد', 'Freeze')),
          ) : null,
        ),
    ]);
  }
  @override
  Widget build(BuildContext context) {
    if (!dedaIsolatedAdminIdentityEnabled) {
      return const Center(child: Text('League stage disabled'));
    }
    final months = DedaAdminLeagueLiveData.archiveMonths(DateTime.now().toUtc());
    final weeks = _weeks();
    return FutureBuilder<Map<String,dynamic>>(future: _data,
      builder: (context,snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError || !snap.hasData) {
          return Center(child: TextButton(onPressed: _refresh, child: Text(t(
            'تعذر إثبات صلاحية إدارة الدوري؛ أعد المحاولة.',
            'League admin server permission unavailable; retry.'))));
        }
        final v = snap.data!;
        final current = v['currentRows'] as List<Map<String,dynamic>>;
        final review = v['reviewRows'] as List<Map<String,dynamic>>;
        final week = v['reviewWeek'] as String;
        final amounts = v['amounts'] as List<int>;
        final prizePlanVerified = v['prizePlanVerified'] == true &&
            amounts.length == 10;
        final receipts = v['receipts'] as Map<String,dynamic>;
        final paused = v['paused'] == true;
        return ListView(padding: const EdgeInsets.all(12), children: [
          Text(t('إدارة الدوري — جلسة مستقلة',
            'League administration — isolated session'),
            style: const TextStyle(fontSize: 17,
              fontWeight: FontWeight.w900)),
          Text(t('التحكم لا يغيّر نقاط المستوى أو رصيد الماسات.',
            'Controls do not change level XP or diamonds.')),
          _panel(t('التحكم بالدوري', 'League controls'), Column(
            crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(paused ? t('الدوري موقوف مؤقتاً', 'Paused')
                : v['weekFrozen'] == true
                ? t('تجميد نهاية الأسبوع حتى 6 صباحاً', 'Frozen until 06:00')
                : t('الدوري يعمل بالجدول الأسبوعي', 'Weekly schedule running')),
              Wrap(spacing: 8, children: [
                FilledButton.icon(
                  onPressed: _busy || !paused ? null : () => _pause(false),
                  icon: const Icon(Icons.play_arrow),
                  label: Text(t('استئناف', 'Resume'))),
                OutlinedButton.icon(
                  onPressed: _busy || paused ? null : () => _pause(true),
                  icon: const Icon(Icons.pause_circle_outline),
                  label: Text(t('إيقاف مؤقت', 'Pause'))),
              ]),
            ],
          )),
          _panel(t('المتصدرون العشرة', 'Top ten'), _rows(current)),
          _panel(t('المراكز الثلاثة الأولى', 'Top three'),
            _rows(current.take(3).toList(growable: false))),
          _panel(t('مراجعة نقاط الدوري', 'League XP review'),
            Column(children: [
              if (weeks.isNotEmpty) DropdownButton<String>(
                isExpanded: true,
                value: weeks.contains(week) ? week : weeks.first,
                items: [for (final w in weeks)
                  DropdownMenuItem(value: w, child: Text(w))],
                onChanged: _busy ? null : (w) {
                  if (w == null) return;
                  setState(() { _reviewWeek = w; _reload(); });
                },
              ),
              Text(t('التجميد لا يؤثر على نقاط المستوى.',
                'Freeze never affects level XP.')),
              _rows(review, editable: true, week: week),
            ]),
          ),
          _panel(t('جوائز الدوري وهداياي — قراءة فقط',
              'League prizes and Hadaya — read only'),
            Column(children: [
              if (!prizePlanVerified)
                Text(t('خطة الجوائز المخزونة غير متوافقة مع الحد المعتمد '
                    'للصرف. عُطّل عرض المبالغ وتعديلها حتى مراجعة '
                    'الخطة من الخادم؛ جدول الدوري ومراجعة النقاط مستمران.',
                    'Saved prize plan conflicts with the approved payout '
                    'minimum. Amount display and editing are blocked pending '
                    'server review; standings and score reviews still work.')),
              if (prizePlanVerified)
                for (var i = 0; i < amounts.length; i++)
                  ListTile(dense: true,
                    title: Text(t('المركز ', 'Place ') + (i+1).toString()),
                    trailing: Text(amounts[i].toString() + ' ' +
                      t('ماسة', 'diamonds'))),
              const Divider(),
              Text(receipts['verified'] == true
                ? t('هدايا مسجلة: ', 'Created gifts: ') +
                  receipts['count'].toString() +
                  t('، معلّقة: ', ', pending: ') +
                  receipts['pending'].toString() +
                  t('، مستلمة: ', ', received: ') +
                  receipts['received'].toString() +
                  (receipts['limited'] == true ? ' (100+)' : '')
                : t('تعذّر إثبات إيصالات هداياي.',
                    'Hadaya receipts cannot be verified.')),
              Text(t('الجوائز المخططة لا تثبت الصرف ولا تحوّل ماسات.',
                'Planned prizes never prove payout or transfer diamonds.')),
              if (prizePlanVerified)
                DedaStage2IsolatedLeaguePrizeEditor(
                  key: ValueKey('stage2-league-prizes-' +
                      v['currentWeek'].toString() + amounts.join('-')),
                  admin: widget.admin, dedaPhone: widget.dedaPhone,
                  isArabic: widget.isArabic,
                  weekId: v['currentWeek'] as String,
                  confirmed: amounts, paused: paused,
                  onSaved: _refresh,
                ),
            ]),
          ),
          _panel(t('سجل الفائزين وجوائز الأسابيع المكتملة',
              'Completed weekly winners and prize register'), Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_completedWeeks().isNotEmpty)
                  DropdownButton<String>(
                    isExpanded: true,
                    value: _completedWeeks().contains(_registerWeek)
                        ? _registerWeek : _completedWeeks().first,
                    items: [
                      for (final week in _completedWeeks())
                        DropdownMenuItem(value: week, child: Text(week)),
                    ],
                    onChanged: _busy ? null : (week) {
                      if (week == null) return;
                      setState(() { _registerWeek = week; _reload(); });
                    },
                  ),
                FutureBuilder<Map<String,dynamic>>(
                  future: _register,
                  builder: (context, report) {
                    if (report.hasError) return Text(t(
                      'تعذر التحقق من سجل الجوائز. لا تُفترض أي دفعة.',
                      'Cannot verify prize records. No payout is presumed.'));
                    if (!report.hasData) return const LinearProgressIndicator();
                    final rows = report.data!['rows']
                        as List<Map<String,dynamic>>;
                    if (rows.isEmpty) return Text(t(
                      'لا توجد أسابيع مكتملة أو فائزون موثّقون.',
                      'No verified completed winners yet.'));
                    return Column(children: [
                      for (final winner in rows)
                        ListTile(
                          dense: true,
                          leading: Text(winner['place'].toString() + '.'),
                          title: Text((winner['name'] ?? '').toString()),
                          subtitle: Text((winner['id'] ?? '').toString() +
                            ' • ' + (winner['status'] ?? '').toString()),
                          trailing: Text((winner['amount'] ?? 0).toString() +
                              ' ' + t('ماسة', 'diamonds')),
                        ),
                    ]);
                  },
                ),
              ],
            )),
          _panel(t('السجل الأسبوعي والأرشيف الشهري',
              'Weekly and monthly history'), Column(children: [
            if (months.isNotEmpty) DropdownButton<String>(
              isExpanded: true,
              value: months.contains(_month) ? _month : months.first,
              items: [for (final m in months)
                DropdownMenuItem(value: m, child: Text(m))],
              onChanged: _busy ? null : (m) {
                if (m != null) setState(() { _month = m; _reload(); });
              },
            ),
            FutureBuilder<List<Map<String,dynamic>>>(future: _archive,
              builder: (context,history) {
                if (history.hasError) return Text(t(
                  'تعذّر تأكيد الأرشيف.', 'Archive not verified.'));
                if (!history.hasData) return const LinearProgressIndicator();
                if (history.data!.isEmpty) return Text(t(
                  'لا توجد أسابيع مكتملة.', 'No completed weeks.'));
                return Column(children: [
                  for (final item in history.data!)
                    ExpansionTile(
                      title: Text(t('الأسبوع ', 'Week ') +
                        item['week'].toString()),
                      children: [
                        _rows(item['rows'] as List<Map<String,dynamic>>),
                      ]),
                ]);
              },
            ),
          ])),
          TextButton.icon(onPressed: _busy ? null : _refresh,
            icon: const Icon(Icons.refresh),
            label: Text(t('تحديث البيانات', 'Refresh'))),
        ]);
      },
    );
  }
}


/// The original manager-only increase editor, with only-server confirmed
/// amounts. Draft changes NEVER update a wallet or a payout record.
class DedaStage2IsolatedLeaguePrizeEditor extends StatefulWidget {
  const DedaStage2IsolatedLeaguePrizeEditor({
    super.key, required this.admin, required this.dedaPhone,
    required this.isArabic, required this.weekId,
    required this.confirmed, required this.paused, required this.onSaved,
  });
  final DedaIsolatedAdminIdentity admin;
  final String dedaPhone;
  final bool isArabic;
  final String weekId;
  final List<int> confirmed;
  final bool paused;
  final VoidCallback onSaved;
  @override
  State<DedaStage2IsolatedLeaguePrizeEditor> createState() =>
      _DedaStage2IsolatedLeaguePrizeEditorState();
}

class _DedaStage2IsolatedLeaguePrizeEditorState
    extends State<DedaStage2IsolatedLeaguePrizeEditor> {
  late final List<TextEditingController> _amounts;
  final _reason = TextEditingController();
  bool _saving = false;
  String? _error;
  String t(String ar,String en) => widget.isArabic ? ar : en;

  @override
  void initState() {
    super.initState();
    _amounts = [
      for (final n in widget.confirmed)
        TextEditingController(text: n.toString()),
    ];
  }
  @override
  void dispose() {
    for (final c in _amounts) { c.dispose(); }
    _reason.dispose();
    super.dispose();
  }
  Future<void> _save() async {
    if (_saving || !widget.paused) return;
    final amounts = [
      for (final controller in _amounts)
        int.tryParse(controller.text.trim()) ?? -1,
    ];
    final why = _reason.text.trim();
    if (amounts.length != 10 || why.length < 8 || why.length > 200 ||
        why.contains(RegExp(r'[\x00-\x1f\x7f]')) ||
        amounts.any((a) => a > 1000000 || a < 0)) {
      setState(() => _error = t('راجع المبالغ والسبب.',
        'Verify amounts and reason.'));
      return;
    }
    var raised = false;
    for (var i = 0; i < amounts.length; i++) {
      if (amounts[i] < widget.confirmed[i]) {
        setState(() => _error = t('لا يجوز تخفيض مبلغ معتمد.',
          'Previously approved prizes cannot decrease.'));
        return;
      }
      if (amounts[i] > widget.confirmed[i]) raised = true;
    }
    if (!raised) {
      setState(() => _error = t('ارفع قيمة مركز واحد على الأقل.',
        'Increase at least one place.'));
      return;
    }
    final accepted = await showDialog<bool>(context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('تأكيد زيادة جوائز الدوري',
            'Confirm league prize increase')),
        content: Text(t('هذا تعديل لخطة الجوائز فقط، ولا يصرف ماسات.',
            'Only updates the plan; no diamonds are paid.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
            child: Text(t('إلغاء', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true),
            child: Text(t('تأكيد', 'Confirm'))),
        ],
      ));
    if (!mounted || accepted != true) return;
    setState(() { _saving = true; _error = null; });
    try {
      await widget.admin.increaseScopedLeaguePrizePlan(
        dedaPhone: widget.dedaPhone,
        weekId: widget.weekId, amounts: amounts, reason: why);
      if (mounted) widget.onSaved();
    } catch (_) {
      if (mounted) setState(() => _error = t(
        'تعذر تأكيد الزيادة؛ اقرأ الخطة من الخادم قبل إعادة المحاولة.',
        'Increase unconfirmed; re-read server amounts before retry.'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
  @override
  Widget build(BuildContext context) {
    if (!widget.paused) return Text(t(
      'لتعديل الجوائز، أوقف الدوري مؤقتاً أولاً. لا يتغير رصيد أحد.',
      'Pause the league before changing prizes. No balance changes.'));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Divider(),
      Text(t('زيادة جوائز المراكز العشرة — بدون تخفيض',
        'Increase ten prizes — no reductions'),
        style: const TextStyle(fontWeight: FontWeight.bold)),
      for (var i = 0; i < _amounts.length; i++)
        Padding(padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            SizedBox(width: 78, child: Text(t('المركز ', 'Rank ') +
              (i + 1).toString())),
            Expanded(child: TextField(
              controller: _amounts[i], enabled: !_saving,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                isDense: true, border: const OutlineInputBorder(),
                suffixText: t('ماسة', 'diamonds')),
            )),
          ]),
        ),
      TextField(controller: _reason, enabled: !_saving, maxLength: 200,
        decoration: InputDecoration(labelText: t(
          'سبب التعديل (8 أحرف فأكثر)', 'Reason (at least 8 characters)'))),
      if (_error != null)
        Text(_error!, style: const TextStyle(color: Colors.red)),
      FilledButton.icon(
        onPressed: _saving ? null : _save,
        icon: const Icon(Icons.save_outlined),
        label: Text(_saving ? t('جارِ التحقق', 'Checking')
            : t('حفظ زيادة الجوائز', 'Save prize increase')),
      ),
    ]);
  }
}
