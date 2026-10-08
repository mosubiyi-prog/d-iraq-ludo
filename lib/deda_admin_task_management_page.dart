import 'package:flutter/material.dart';

import 'deda_admin_task_drafts.dart';
import 'deda_backend.dart';
import 'deda_daily_task_slots.dart';
import 'deda_daily_schedule_preview_service.dart';

/// Manager-only editor for the EXISTING eight daily task card slots.
/// This stage saves isolated private drafts. It never publishes a task,
/// changes a user's progress or awards points/diamonds.
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
  final _previewService = const DedaDailySchedulePreviewService();
  late final Stream<List<DedaDailySchedulePreview>> _previewStream;
  final Set<String> _busySlots = <String>{};
  bool _checking = true;
  bool _allowed = false;

  String t(String ar, String en) => widget.isArabic ? ar : en;

  @override
  void initState() {
    super.initState();
    _previewStream = _previewService.watchPreviews();
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

  Future<void> _edit(
    DedaDailyTaskSlot slot,
    DedaAdminTaskDraft? current,
  ) async {
    // Do not modify current user tasks; start from the original card's
    // immutable type/title if no administrative draft exists for this slot.
    final seed = current ?? DedaAdminTaskDraft(
      cycle: 'daily',
      action: slot.action,
      titleAr: slot.titleAr,
      titleEn: slot.titleAr,
      targetCount: 1,
      rewardUnit: 'points',
      rewardAmount: 5,
    );
    final draft = await showDialog<DedaAdminTaskDraft>(
      context: context,
      builder: (_) => _DedaTaskDraftDialog(
        isArabic: widget.isArabic,
        slot: slot,
        previous: seed,
      ),
    );
    if (draft == null || !mounted) return;
    try {
      await _service.save(draft: draft, dailySlotId: slot.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(t(
          'انحفظ تعديل البطاقة كمسودة خاصة بالإدارة فقط؛ المستخدم ما يتأثر.',
          'Card changes saved as private admin draft only; user tasks unchanged.',
        )),
      ));
    } catch (error) {
      if (!mounted) return;
      final message = error.toString();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          message.contains('task-draft-changed-remotely')
              ? t('المدير عدّل المسودة بجهاز آخر؛ افتح البطاقة من جديد.',
                  'Draft changed elsewhere. Reopen the card.')
              : message.contains('permission-denied')
                  ? t('Firebase رفض حفظ المسودة. ماكو أي تغيير عند المستخدم.',
                      'Firebase denied the draft. Users are unaffected.')
                  : t('تعذر حفظ تعديل البطاقة. النظام الحالي ما تغير.',
                      'Could not save draft. Live tasks remain unchanged.'),
        ),
      ));
    }
  }

  Future<void> _preparePreview(
    DedaDailyTaskSlot slot,
    DedaAdminTaskDraft draft,
  ) async {
    if (_busySlots.contains(slot.id)) return;
    setState(() => _busySlots.add(slot.id));
    try {
      await _previewService.prepare(slot: slot, draft: draft);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(t(
          'تحدد موعد تجريبي لتعديل البطاقة. هذا ما ينشر شي للمستخدمين حاليًا.',
          'Preview scheduled privately; nothing is published to users yet.',
        )),
      ));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(t(
          'تعذر تجهيز الموعد التجريبي. تأكد من صلاحيات Firebase.',
          'Could not prepare private preview. Check Firebase permissions.',
        )),
      ));
    } finally {
      if (mounted) setState(() => _busySlots.remove(slot.id));
    }
  }

  Future<void> _cancelPreview(DedaDailyTaskSlot slot) async {
    if (_busySlots.contains(slot.id)) return;
    setState(() => _busySlots.add(slot.id));
    try {
      await _previewService.cancel(slot.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(t(
          'انلغى الموعد التجريبي. المهمة الأصلية ما تغيرت.',
          'Private preview cancelled; the original task is unchanged.',
        )),
      ));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(t(
          'تعذر الإلغاء. يمكن يكون موعد الجدولة انتهى؛ حدّث الصفحة.',
          'Cancellation denied or deadline passed; reload the page.',
        )),
      ));
    } finally {
      if (mounted) setState(() => _busySlots.remove(slot.id));
    }
  }

  Widget _taskCard(
    DedaDailyTaskSlot slot,
    DedaAdminTaskDraft? draft,
    DedaDailySchedulePreview? preview, {
    required bool previewAvailable,
  }) {
    final staged = draft != null;
    final isPending = preview?.status == 'pending';
    final busy = _busySlots.contains(slot.id);
    final cancelled = preview?.status == 'cancelled';
    final status = !previewAvailable
        ? t('الجدولة التجريبية غير مفعلة على Firebase الحالي',
            'Private scheduling is not enabled in this Firebase environment')
        : isPending
            ? t('موعد تجريبي محفوظ — غير منشور للمستخدمين',
                'Private scheduled preview — not published')
            : cancelled
                ? t('تم إلغاء الموعد التجريبي',
                    'Private preview cancelled')
                : staged
                    ? t('تعديل محفوظ كمسودة — غير منشور',
                        'Saved draft — not published')
                    : t('المهمة الحالية محفوظة كما هي',
                        'Existing task unchanged');
    return Card(
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 9),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(17),
        side: BorderSide(
          color: staged ? const Color(0xFFAEC6B3)
              : const Color(0xFFE0E4DC),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 13, vertical: 9,
            ),
            leading: const Icon(Icons.edit_note_rounded,
                color: Color(0xFF1B6A44), size: 28),
            title: Text(
              staged ? draft.titleAr : slot.titleAr,
              style: const TextStyle(
                fontWeight: FontWeight.w900, fontSize: 15.5,
              ),
            ),
            subtitle: Text(
              (staged ? DedaAdminTaskDraft.actionTitle(
                  draft.action, widget.isArabic)
                  : slot.subtitleAr) +
                  '\n' + status +
                  (isPending
                      ? '\n' + t('منتصف الليل القادم (العراق) — موعد تجريبي',
                          'Next Iraq midnight — private preview')
                      : ''),
              style: const TextStyle(height: 1.4),
            ),
            trailing: const Icon(Icons.edit_outlined),
            onTap: busy ? null : () => _edit(slot, draft),
          ),
          if (previewAvailable && (staged || isPending))
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(12, 0, 12, 10),
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  if (staged)
                    OutlinedButton.icon(
                      onPressed: busy ? null : () => _preparePreview(slot, draft),
                      icon: const Icon(Icons.schedule_rounded, size: 17),
                      label: Text(t('جدولة تجريبية', 'Preview schedule')),
                    ),
                  if (isPending)
                    TextButton.icon(
                      onPressed: busy ? null : () => _cancelPreview(slot),
                      icon: const Icon(Icons.undo_rounded, size: 17),
                      label: Text(t('إلغاء الموعد', 'Cancel preview')),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF2),
      appBar: AppBar(
        title: Text(t('إدارة المهام اليومية', 'Daily tasks management')),
      ),
      body: _checking
          ? const Center(child: CircularProgressIndicator())
          : !_allowed
              ? Center(child: Text(t(
                  'هذا القسم للمدير العام فقط.',
                  'General manager only.',
                )))
              : StreamBuilder<List<DedaAdminTaskDraft>>(
                  stream: _service.watchDrafts(),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Center(child: Text(t(
                        'تعذر قراءة مسودات المهام من Firebase.',
                        'Cannot load admin task drafts from Firebase.',
                      )));
                    }
                    if (!snapshot.hasData) {
                      return const Center(
                        child: CircularProgressIndicator(),
                      );
                    }
                    final drafts = snapshot.data!;
                    final byId = <String, DedaAdminTaskDraft>{
                      for (final draft in drafts) draft.id: draft,
                    };
                    final legacyCount = drafts.where((draft) =>
                      !DedaDailyTaskSlot.slots.any(
                        (slot) => slot.draftId == draft.id,
                      )).length;

                    return StreamBuilder<List<DedaDailySchedulePreview>>(
                      stream: _previewStream,
                      builder: (context, previewsSnapshot) {
                        final previewAvailable = !previewsSnapshot.hasError;
                        final bySlot = <String, DedaDailySchedulePreview>{
                          for (final p in previewsSnapshot.data ??
                              const <DedaDailySchedulePreview>[])
                            p.slotId: p,
                        };
                        return ListView(
                      padding: const EdgeInsets.all(12),
                      children: [
                        Container(
                          padding: const EdgeInsets.all(13),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE8F0E7),
                            borderRadius: BorderRadius.circular(15),
                          ),
                          child: Text(t(
                            'نفس بطاقات مهام المستخدم الثمانية. عدّل أي بطاقة وحدها؛ البقية تبقى مثل ما هي.',
                            'The same eight user task cards. Edit one card without affecting the others.',
                          ), style: const TextStyle(
                            fontWeight: FontWeight.w700, height: 1.5,
                          )),
                        ),
                        const SizedBox(height: 10),
                        Card(
                          color: const Color(0xFF0B3156),
                          child: ListTile(
                            leading: const Icon(
                              Icons.calendar_month_rounded,
                              color: Color(0xFFFFD76A),
                            ),
                            title: const Text(
                              DedaDailyTaskSlot.loginTitleAr,
                              style: TextStyle(
                                color: Colors.white, fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Text(t(
                              'ثابتة — 10 نقاط حاليًا. جدولة مكافأة المناسبات تحتاج ربط صرف آمن قبل تفعيلها.',
                              'Fixed — 10 points today. Holiday reward scheduling awaits verified payout integration.',
                            ), style: const TextStyle(
                              color: Color(0xFFE2EAF4),
                            )),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(t('المهام اليومية', 'Daily tasks'),
                          style: const TextStyle(
                            fontWeight: FontWeight.w900, fontSize: 19,
                          )),
                        const SizedBox(height: 10),
                        for (final slot in DedaDailyTaskSlot.slots)
                          _taskCard(
                            slot, byId[slot.draftId], bySlot[slot.id],
                            previewAvailable: previewAvailable,
                          ),
                        if (legacyCount > 0)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: Text(t(
                              'المسودات التجريبية القديمة محفوظة في Firebase ولم تُحذف أو تُنشر.',
                              'Older test drafts remain saved in Firebase; nothing was deleted or published.',
                            ), style: const TextStyle(
                              fontSize: 12, color: Color(0xFF646A63),
                            )),
                          ),
                        const SizedBox(height: 8),
                        Text(t(
                          'هاي المعاينات الإدارية تجريبية فقط وما تظهر للمستخدمين. نشر منتصف الليل وصرف المكافآت يحتاجان تفعيل خادم آمن واختبار منفصل.',
                          'Admin previews are private and do not reach users. Midnight publication and payouts await separately verified server integration.',
                        ), style: const TextStyle(
                          fontSize: 12, height: 1.5,
                          color: Color(0xFF6A542D),
                        )),
                      ],
                    );
                      },
                    );
                  },
                ),
    );
  }
}

class _DedaTaskDraftDialog extends StatefulWidget {
  const _DedaTaskDraftDialog({
    required this.isArabic,
    required this.slot,
    this.previous,
  });

  final bool isArabic;
  final DedaDailyTaskSlot slot;
  final DedaAdminTaskDraft? previous;

  @override
  State<_DedaTaskDraftDialog> createState() => _DedaTaskDraftDialogState();
}

class _DedaTaskDraftDialogState extends State<_DedaTaskDraftDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController titleAr;
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
    target = TextEditingController(text: (old?.targetCount ?? 1).toString());
    amount = TextEditingController(text: (old?.rewardAmount ?? 5).toString());
    url = TextEditingController(text: old?.url ?? '');
  }

  @override
  void dispose() {
    titleAr.dispose();
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
      title: Text(t('تعديل المهمة', 'Edit task')),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: action,
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
                numberField(target, t('عدد المرات', 'Required count'), 100),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: unit,
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
                  'التعديل مسودة إدارية فقط؛ لا نشر أو صرف نقاط وألماس حاليًا.',
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
              cycle: 'daily',
              action: action,
              titleAr: titleAr.text,
              titleEn: titleAr.text.trim(),
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
