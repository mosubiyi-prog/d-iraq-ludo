import 'package:flutter/material.dart';

import 'deda_admin_task_drafts.dart';
import 'deda_backend.dart';
import 'deda_admin_surveys_page.dart';

/// Phase 1: manager-only draft editor, NEVER publishes to current task engine.
class DedaAdminTaskManagementPage extends StatefulWidget {
  const DedaAdminTaskManagementPage({super.key, required this.isArabic});
  final bool isArabic;

  @override
  State<DedaAdminTaskManagementPage> createState() =>
      _DedaAdminTaskManagementPageState();
}

class _DedaAdminTaskManagementPageState
    extends State<DedaAdminTaskManagementPage> {
  final _service = const DedaAdminTaskDraftService();
  String _cycle = 'daily';
  bool _checking = true;
  bool _allowed = false;

  String t(String ar, String en) => widget.isArabic ? ar : en;

  @override
  void initState() {
    super.initState();
    _checkAccess();
  }

  Future<void> _checkAccess() async {
    var allowed = false;
    try {
      final profile = await DedaBackend.currentAdminProfile(
        forceRefresh: true,
      );
      allowed = DedaBackend.normalizeAdminRole(profile['role']) ==
          'general_manager';
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _allowed = allowed;
      _checking = false;
    });
  }

  Future<void> _edit([DedaAdminTaskDraft? previous]) async {
    final draft = await showDialog<DedaAdminTaskDraft>(
      context: context,
      builder: (_) => _DedaTaskDraftDialog(
        isArabic: widget.isArabic,
        cycle: _cycle,
        previous: previous,
      ),
    );
    if (draft == null || !mounted) return;
    try {
      await _service.save(draft: draft);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(t(
          'حُفظت المسودة في Firebase وسجل الإدارة، لكنها غير منشورة للمستخدمين.',
          'Draft saved in Firebase and the admin audit; not published to users.',
        )),
      ));
    } catch (error) {
      if (!mounted) return;
      final message = error.toString();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          message.contains('task-draft-changed-remotely')
              ? t('البيانات تغيرت من مدير آخر. أعد فتح المهمة.',
                  'Another manager changed this draft; reopen it.')
              : message.contains('permission-denied')
                  ? t('قواعد Firebase للقسم لم تُنشر بعد؛ لم يُحفظ التعديل.',
                      'Firebase rules are not yet deployed; nothing was saved.')
                  : t('تعذر حفظ المسودة. لم تتغير مكافآت المستخدمين.',
                      'Could not save draft; user rewards are unchanged.'),
        ),
      ));
    }
  }

  Widget _cycleTile(String cycle, Color color, IconData icon) {
    final active = cycle == _cycle;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => setState(() => _cycle = cycle),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: active ? color.withOpacity(.16) : Colors.white,
            border: Border.all(
              color: active ? color : const Color(0xFFD6E0D4),
              width: active ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(icon, size: 32, color: color),
              const SizedBox(height: 9),
              Text(
                cycle == 'daily'
                    ? t('المهام اليومية', 'Daily tasks')
                    : t('المهام الأسبوعية', 'Weekly tasks'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                t('إدارة وتحديد', 'Manage and define'),
                style: const TextStyle(fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _taskRow(DedaAdminTaskDraft draft) {
    final rewardLabel = draft.rewardUnit == 'diamonds'
        ? '💎'
        : t('نقطة', 'points');
    return Card(
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: ListTile(
        title: Text(
          widget.isArabic ? draft.titleAr : draft.titleEn,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          DedaAdminTaskDraft.actionTitle(draft.action, widget.isArabic) +
              ' • ' + draft.targetCount.toString() +
              ' × • ' + draft.rewardAmount.toString() +
              ' ' + rewardLabel + '\n' +
              t('مسودة غير منشورة', 'Unpublished draft'),
        ),
        isThreeLine: true,
        trailing: const Icon(Icons.edit_outlined),
        onTap: () => _edit(draft),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF2),
      appBar: AppBar(
        title: Text(t('إدارة المهام والمكافآت', 'Tasks & rewards management')),
      ),
      body: _checking
          ? const Center(child: CircularProgressIndicator())
          : !_allowed
              ? Center(
                  child: Text(t(
                    'هذا القسم مخصص للمدير العام المصرح فقط.',
                    'Authorized general manager only.',
                  )),
                )
              : Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          _cycleTile(
                            'daily', const Color(0xFF2886B6),
                            Icons.calendar_today_outlined,
                          ),
                          const SizedBox(width: 10),
                          _cycleTile(
                            'weekly', const Color(0xFF388A59),
                            Icons.date_range_outlined,
                          ),
                        ],
                      ),
                      const SizedBox(height: 11),
                      Card(
                        color: const Color(0xFFE9E6F6),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                          side: const BorderSide(color: Color(0xFFBDB1DC)),
                        ),
                        child: ListTile(
                          leading: const CircleAvatar(
                            backgroundColor: Color(0xFFD7C9EF),
                            child: Icon(Icons.rate_review_outlined,
                                color: Color(0xFF654B90)),
                          ),
                          title: Text(
                            t('آراء المستخدمين واستطلاعات DEDA',
                                'DEDA user opinions and surveys'),
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF43345E),
                            ),
                          ),
                          subtitle: Text(
                            t('افتح حقول تقييم وأسئلة ومقترحات جديدة',
                                'Add rating, questions and feedback fields'),
                          ),
                          trailing: const Icon(Icons.chevron_left_rounded),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => DedaAdminSurveysPage(
                                isArabic: widget.isArabic,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(13),
                          color: const Color(0xFFFFF2D8),
                        ),
                        child: Text(
                          t(
                            'مرحلة التجهيز: التغييرات هنا مسودات فقط. لا تتغير المهام أو المكافآت عند المستخدم قبل ربط نظام الصرف الآمن.',
                            'Preparation stage: drafts only. User tasks and rewards remain unchanged until secure payout integration.',
                          ),
                          style: const TextStyle(
                            color: Color(0xFF73541B), height: 1.4,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _cycle == 'daily'
                                  ? t('المهام اليومية', 'Daily tasks')
                                  : t('المهام الأسبوعية', 'Weekly tasks'),
                              style: const TextStyle(
                                fontWeight: FontWeight.w900, fontSize: 17,
                              ),
                            ),
                          ),
                          FilledButton.icon(
                            onPressed: () => _edit(),
                            icon: const Icon(Icons.add),
                            label: Text(t('إضافة', 'Add')),
                          ),
                        ],
                      ),
                      Expanded(
                        child: StreamBuilder<List<DedaAdminTaskDraft>>(
                          stream: _service.watchDrafts(),
                          builder: (context, snap) {
                            if (snap.hasError) {
                              return Center(
                                child: Text(t(
                                  'لا يمكن قراءة مسودات Firebase. يجب تفعيل قواعد القسم المعتمدة أولًا.',
                                  'Cannot read Firebase drafts until task-draft rules are deployed.',
                                )),
                              );
                            }
                            if (!snap.hasData) {
                              return const Center(
                                child: CircularProgressIndicator(),
                              );
                            }
                            final rows = snap.data!
                                .where((item) => item.cycle == _cycle)
                                .toList(growable: false);
                            if (rows.isEmpty) {
                              return Center(
                                child: Text(t(
                                  'ماكو مسودات بعد. أضف أول مهمة.',
                                  'No drafts yet. Add the first task.',
                                )),
                              );
                            }
                            return ListView.builder(
                              itemCount: rows.length,
                              itemBuilder: (context, index) =>
                                  _taskRow(rows[index]),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}

class _DedaTaskDraftDialog extends StatefulWidget {
  const _DedaTaskDraftDialog({
    required this.isArabic,
    required this.cycle,
    this.previous,
  });

  final bool isArabic;
  final String cycle;
  final DedaAdminTaskDraft? previous;

  @override
  State<_DedaTaskDraftDialog> createState() => _DedaTaskDraftDialogState();
}

class _DedaTaskDraftDialogState extends State<_DedaTaskDraftDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController titleAr;
  late final TextEditingController titleEn;
  late final TextEditingController target;
  late final TextEditingController amount;
  late final TextEditingController url;
  late String action;
  late String unit;

  String t(String ar, String en) => widget.isArabic ? ar : en;

  @override
  void initState() {
    super.initState();
    final old = widget.previous;
    action = old?.action ?? 'open_map';
    unit = old?.rewardUnit ?? 'points';
    titleAr = TextEditingController(text: old?.titleAr ?? '');
    titleEn = TextEditingController(text: old?.titleEn ?? '');
    target = TextEditingController(text: (old?.targetCount ?? 1).toString());
    amount = TextEditingController(text: (old?.rewardAmount ?? 5).toString());
    url = TextEditingController(text: old?.url ?? '');
  }

  @override
  void dispose() {
    titleAr.dispose();
    titleEn.dispose();
    target.dispose();
    amount.dispose();
    url.dispose();
    super.dispose();
  }

  InputDecoration decoration(String label) =>
      InputDecoration(labelText: label, border: const OutlineInputBorder());

  Widget numberField(TextEditingController controller, String label, int max) {
    return TextFormField(
      controller: controller,
      decoration: decoration(label),
      keyboardType: TextInputType.number,
      validator: (value) {
        final n = int.tryParse(value?.trim() ?? '');
        return n == null || n < 1 || n > max
            ? t('العدد غير صحيح', 'Invalid number')
            : null;
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(t('إعدادات المهمة', 'Task draft settings')),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: action,
                  isExpanded: true,
                  decoration: decoration(t('نوع المهمة', 'Task type')),
                  items: DedaAdminTaskDraft.actions.map((key) =>
                    DropdownMenuItem(
                      value: key,
                      child: Text(DedaAdminTaskDraft.actionTitle(
                        key, widget.isArabic)),
                    ),
                  ).toList(),
                  onChanged: (value) =>
                    setState(() => action = value ?? action),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: titleAr,
                  decoration: decoration(t('عنوان المهمة بالعربية', 'Arabic title')),
                  maxLength: 80,
                  validator: (value) => (value?.trim().length ?? 0) < 3
                      ? t('اكتب عنوانًا صحيحًا', 'Enter a title')
                      : null,
                ),
                TextFormField(
                  controller: titleEn,
                  decoration: decoration(t('عنوان المهمة بالإنجليزية', 'English title')),
                  maxLength: 80,
                  validator: (value) => (value?.trim().length ?? 0) < 3
                      ? t('اكتب عنوانًا صحيحًا', 'Enter a title')
                      : null,
                ),
                numberField(target, t('عدد المرات', 'Required count'), 100),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: unit,
                  decoration: decoration(t('نوع المكافأة', 'Reward type')),
                  items: [
                    DropdownMenuItem(
                      value: 'points',
                      child: Text(t('نقاط', 'Points')),
                    ),
                    DropdownMenuItem(
                      value: 'diamonds',
                      child: Text(t('ألماس 💎', 'Diamonds')),
                    ),
                  ],
                  onChanged: (value) =>
                    setState(() => unit = value ?? unit),
                ),
                const SizedBox(height: 10),
                numberField(amount, t('قيمة المكافأة', 'Reward amount'), 5000),
                if (action == 'visit_telegram') ...[
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: url,
                    decoration: decoration(t('رابط تليجرام', 'Telegram link')),
                    keyboardType: TextInputType.url,
                  ),
                  Text(t(
                    'فتح الرابط مو دليل على الاشتراك الفعلي.',
                    'Opening a link does not prove subscription.',
                  ), style: const TextStyle(fontSize: 11)),
                ],
                const SizedBox(height: 10),
                Text(t(
                  'الحفظ كمسودة فقط؛ لا تفعيل ولا صرف نقاط أو ألماس.',
                  'Draft only; no activation or rewards.',
                )),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t('إلغاء', 'Cancel')),
        ),
        FilledButton(
          onPressed: () {
            if (!(_form.currentState?.validate() ?? false)) return;
            final old = widget.previous;
            final draft = DedaAdminTaskDraft(
              id: old?.id ?? '',
              revision: old?.revision ?? 0,
              cycle: old?.cycle ?? widget.cycle,
              action: action,
              titleAr: titleAr.text,
              titleEn: titleEn.text,
              targetCount: int.parse(target.text.trim()),
              rewardUnit: unit,
              rewardAmount: int.parse(amount.text.trim()),
              url: action == 'visit_telegram' ? url.text.trim() : '',
            );
            try {
              draft.validate();
              Navigator.pop(context, draft);
            } catch (_) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(t(
                  'راجع الرابط أو بيانات المهمة.',
                  'Please check task data or URL.',
                )),
              ));
            }
          },
          child: Text(t('حفظ المسودة', 'Save draft')),
        ),
      ],
    );
  }
}
