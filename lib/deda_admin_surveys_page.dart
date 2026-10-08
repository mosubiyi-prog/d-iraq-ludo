import 'package:flutter/material.dart';

import 'deda_admin_survey_drafts.dart';
import 'deda_backend.dart';

/// Manager-only opinion survey draft editor. No public surveys/rewards yet.
class DedaAdminSurveysPage extends StatefulWidget {
  const DedaAdminSurveysPage({super.key, required this.isArabic});
  final bool isArabic;

  @override
  State<DedaAdminSurveysPage> createState() => _DedaAdminSurveysPageState();
}

class _DedaAdminSurveysPageState extends State<DedaAdminSurveysPage> {
  final _service = const DedaAdminSurveyDraftService();
  bool _checking = true;
  bool _allowed = false;
  String t(String ar, String en) => widget.isArabic ? ar : en;

  @override
  void initState() {
    super.initState();
    _verifyManager();
  }

  Future<void> _verifyManager() async {
    var allowed = false;
    try {
      final profile = await DedaBackend.currentAdminProfile(forceRefresh: true);
      allowed = DedaBackend.normalizeAdminRole(profile['role']) ==
          'general_manager';
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _checking = false;
      _allowed = allowed;
    });
  }

  Future<void> _edit([DedaAdminSurveyDraft? old]) async {
    final draft = await showDialog<DedaAdminSurveyDraft>(
      context: context,
      builder: (_) => _SurveyDraftEditor(
        isArabic: widget.isArabic,
        original: old,
      ),
    );
    if (draft == null || !mounted) return;
    try {
      await _service.save(draft);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(t(
          'تم حفظ استطلاع رأي كمسودة خاصة بالإدارة؛ لم يظهر للمستخدمين.',
          'Survey saved as a private draft; users cannot see it yet.',
        )),
      ));
    } catch (e) {
      if (!mounted) return;
      final raw = e.toString();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(raw.contains('survey-draft-conflict')
            ? t('مدير آخر عدّل الاستطلاع، افتحه من جديد.',
                'Another manager changed this survey; reopen it.')
            : raw.contains('permission-denied')
                ? t('قواعد أمان Firebase الجديدة لم تُفعل بعد.',
                    'New Firebase draft rules have not been deployed yet.')
                : t('تعذر حفظ المسودة؛ ماكو أي تغيير عند المستخدمين.',
                    'Draft save failed; users remain unaffected.')),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF2),
      appBar: AppBar(
        title: Text(t('آراء المستخدمين واستطلاعات DEDA',
            'DEDA user opinions and surveys')),
      ),
      body: _checking
          ? const Center(child: CircularProgressIndicator())
          : !_allowed
              ? Center(
                  child: Text(t('هذا القسم للمدير العام فقط.',
                      'General manager only.')),
                )
              : Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Card(
                        color: const Color(0xFFE2EDF8),
                        child: Padding(
                          padding: const EdgeInsets.all(13),
                          child: Text(t(
                            'اسأل المستخدم عن الخارطة والمهام والأسئلة المرورية أو أي ميزة أخرى. تقدر تضيف حتى 6 أسئلة للاستطلاع، بتقييم أو خيارات أو اقتراح مكتوب.',
                            'Ask about maps, tasks, traffic quizzes or any feature. Add up to six rating, multiple-choice or free-text questions.',
                          ), style: const TextStyle(height: 1.5)),
                        ),
                      ),
                      Card(
                        color: const Color(0xFFFFF1D6),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(t(
                            'مرحلة تجهيز فقط: الاستطلاعات مسودات غير منشورة، والمكافآت لا تُصرف حتى يكتمل التحقق الآمن. كل الآراء تُحسب بالتساوي.',
                            'Draft-only preparation: surveys are not published and no reward is paid until verified submission is implemented. All opinions count equally.',
                          ), style: const TextStyle(height: 1.4)),
                        ),
                      ),
                      const SizedBox(height: 7),
                      Row(
                        children: [
                          Expanded(
                            child: Text(t('الاستطلاعات', 'Surveys'),
                                style: const TextStyle(
                                    fontSize: 18, fontWeight: FontWeight.w900)),
                          ),
                          FilledButton.icon(
                            onPressed: () => _edit(),
                            icon: const Icon(Icons.add),
                            label: Text(t('إضافة استطلاع', 'Add survey')),
                          ),
                        ],
                      ),
                      const SizedBox(height: 9),
                      Expanded(
                        child: StreamBuilder<List<DedaAdminSurveyDraft>>(
                          stream: _service.watchDrafts(),
                          builder: (context, snap) {
                            if (snap.hasError) {
                              return Center(
                                child: Text(t(
                                  'الاستطلاعات غير متاحة حتى يتم تفعيل قواعد الأمان الجديدة.',
                                  'Surveys are unavailable until the new security rules are deployed.',
                                )),
                              );
                            }
                            if (!snap.hasData) {
                              return const Center(
                                  child: CircularProgressIndicator());
                            }
                            final drafts = snap.data!;
                            if (drafts.isEmpty) {
                              return Center(
                                child: Text(t(
                                  'ماكو استطلاعات محفوظة بعد.',
                                  'No saved survey drafts yet.',
                                )),
                              );
                            }
                            return ListView.builder(
                              itemCount: drafts.length,
                              itemBuilder: (context, index) {
                                final survey = drafts[index];
                                final title = widget.isArabic
                                    ? survey.titleAr : survey.titleEn;
                                return Card(
                                  color: Colors.white,
                                  margin: const EdgeInsets.only(bottom: 9),
                                  child: ListTile(
                                    leading: const CircleAvatar(
                                      child: Icon(Icons.rate_review_outlined),
                                    ),
                                    title: Text(title,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold)),
                                    subtitle: Text(
                                      t('عدد الأسئلة: ', 'Questions: ') +
                                          survey.questions.length.toString() +
                                          '\n' +
                                          t('مسودة — غير منشورة', 'Draft — unpublished'),
                                    ),
                                    isThreeLine: true,
                                    trailing: const Icon(Icons.edit_outlined),
                                    onTap: () => _edit(survey),
                                  ),
                                );
                              },
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

// Arabic-first editor. Legacy English schema fields are mirrored from Arabic
// until a separate translation workflow is introduced; no hidden stale text.
class _SurveyQuestionFields {
  _SurveyQuestionFields([DedaSurveyQuestion? q])
      : type = q?.type ?? 'rating_5',
        required = q?.required ?? true,
        ar = TextEditingController(text: q?.promptAr ?? ''),
        optionsAr = TextEditingController(
            text: q?.optionsAr.join('\n') ?? '');

  String type;
  bool required;
  final TextEditingController ar;
  final TextEditingController optionsAr;

  DedaSurveyQuestion toQuestion() {
    final options = type == 'choice'
        ? optionsAr.text
            .split('\n')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList(growable: false)
        : const <String>[];
    return DedaSurveyQuestion(
      type: type,
      promptAr: ar.text,
      promptEn: ar.text.trim(), // Compatibility fallback, not a translation.
      required: required,
      optionsAr: options,
      optionsEn: options,
    );
  }

  void dispose() {
    ar.dispose();
    optionsAr.dispose();
  }
}

class _SurveyDraftEditor extends StatefulWidget {
  const _SurveyDraftEditor({required this.isArabic, this.original});
  final bool isArabic;
  final DedaAdminSurveyDraft? original;

  @override
  State<_SurveyDraftEditor> createState() => _SurveyDraftEditorState();
}

class _SurveyDraftEditorState extends State<_SurveyDraftEditor> {
  late final TextEditingController titleAr;
  late final TextEditingController reward;
  late final TextEditingController days;
  late final List<_SurveyQuestionFields> questions;
  late String rewardUnit;
  String t(String ar, String en) => widget.isArabic ? ar : en;

  @override
  void initState() {
    super.initState();
    final original = widget.original;
    titleAr = TextEditingController(
        text: original?.titleAr ?? 'آراء المستخدمين عن DEDA');
    rewardUnit = original?.rewardUnit ?? 'none';
    reward = TextEditingController(
        text: (original?.rewardAmount ?? 0).toString());
    days = TextEditingController(
        text: (original?.durationDays ?? 14).toString());
    questions = (original?.questions ?? const <DedaSurveyQuestion>[
      DedaSurveyQuestion(
        type: 'rating_5',
        promptAr: 'ما رأيك باستخدام خارطة DEDA؟',
        promptEn: 'How is your experience using the DEDA map?',
      ),
      DedaSurveyQuestion(
        type: 'rating_5',
        promptAr: 'ما رأيك بالمهام اليومية؟',
        promptEn: 'What do you think about daily tasks?',
      ),
      DedaSurveyQuestion(
        type: 'rating_5',
        promptAr: 'ما رأيك بالأسئلة المرورية؟',
        promptEn: 'How do you rate the traffic quizzes?',
      ),
    ]).map((q) => _SurveyQuestionFields(q)).toList();
  }

  @override
  void dispose() {
    titleAr.dispose();
    reward.dispose();
    days.dispose();
    for (final q in questions) {
      q.dispose();
    }
    super.dispose();
  }

  InputDecoration _decoration(String label) =>
      InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
      );

  Widget _questionCard(int i) {
    final q = questions[i];
    return Card(
      color: const Color(0xFFF7F9F8),
      margin: const EdgeInsets.only(bottom: 9),
      child: Padding(
        padding: const EdgeInsets.all(11),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    t('السؤال ', 'Question ') + (i + 1).toString(),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  onPressed: questions.length <= 1
                      ? null
                      : () => setState(() {
                            questions.removeAt(i).dispose();
                          }),
                  icon: const Icon(Icons.remove_circle_outline),
                  tooltip: t('حذف السؤال', 'Remove question'),
                ),
              ],
            ),
            DropdownButtonFormField<String>(
              value: q.type,
              isExpanded: true,
              decoration: _decoration(t('نوع الإجابة', 'Answer type')),
              items: [
                DropdownMenuItem(
                  value: 'rating_5',
                  child: Text(t('تقييم 1 إلى 5 نجوم', '1–5 stars')),
                ),
                DropdownMenuItem(
                  value: 'choice',
                  child: Text(t('اختيار من خيارات', 'Multiple choice')),
                ),
                DropdownMenuItem(
                  value: 'text',
                  child: Text(t('اقتراح مكتوب', 'Written feedback')),
                ),
              ],
              onChanged: (value) => setState(() => q.type = value ?? q.type),
            ),
            const SizedBox(height: 9),
            TextFormField(
              controller: q.ar,
              decoration: _decoration(t('نص السؤال', 'Question')),
              maxLength: 160,
            ),
            if (q.type == 'choice') ...[
              TextFormField(
                controller: q.optionsAr,
                maxLines: 3,
                decoration: _decoration(
                  t('الخيارات، كل خيار بسطر',
                      'Options, one per line'),
                ),
              ),
            ],
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(t('سؤال إجباري', 'Required question')),
              value: q.required,
              onChanged: (next) => setState(() => q.required = next),
            ),
          ],
        ),
      ),
    );
  }

  void _save() {
    final original = widget.original;
    final draft = DedaAdminSurveyDraft(
      id: original?.id ?? '',
      revision: original?.revision ?? 0,
      titleAr: titleAr.text,
      titleEn: titleAr.text.trim(), // Legacy schema fallback; Arabic-first.
      questions: questions.map((q) => q.toQuestion()).toList(),
      rewardUnit: rewardUnit,
      rewardAmount: int.tryParse(reward.text.trim()) ?? -1,
      durationDays: int.tryParse(days.text.trim()) ?? -1,
    );
    try {
      draft.validate();
      Navigator.of(context).pop(draft);
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(t(
          'راجع أسماء الأسئلة وخيارات الإجابة والمكافأة والمدة.',
          'Check question text, answer choices, reward and duration.',
        )),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(t('إعداد استطلاع آراء', 'Edit opinion survey')),
      content: SizedBox(
        width: 530,
        height: MediaQuery.sizeOf(context).height * .67,
        child: ListView(
          children: [
            TextFormField(
              controller: titleAr,
              maxLength: 80,
              decoration: _decoration(t('عنوان الاستطلاع',
                  'Survey title')),
            ),
            const SizedBox(height: 8),
            for (var i = 0; i < questions.length; i++) _questionCard(i),
            OutlinedButton.icon(
              onPressed: questions.length >= 6
                  ? null
                  : () => setState(() {
                        questions.add(_SurveyQuestionFields());
                      }),
              icon: const Icon(Icons.add_circle_outline),
              label: Text(t('إضافة سؤال جديد', 'Add another question')),
            ),
            const SizedBox(height: 12),
            Text(t('مكافأة واحدة بعد إكمال الاستطلاع', 'One reward for completing the survey'),
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: rewardUnit,
              decoration: _decoration(t('نوع المكافأة', 'Reward type')),
              items: [
                DropdownMenuItem(
                    value: 'none',
                    child: Text(t('بدون مكافأة', 'No reward'))),
                DropdownMenuItem(
                    value: 'coins',
                    child: Text(t('عملات 🪙', 'Coins 🪙'))),
                if (rewardUnit == 'points')
                  DropdownMenuItem(
                      value: 'points',
                      child: Text(t('نقاط (مسودة قديمة)', 'Points (legacy draft)'))),
                DropdownMenuItem(
                    value: 'diamonds',
                    child: Text(t('ألماس 💎', 'Diamonds'))),
              ],
              onChanged: (value) {
                setState(() {
                  rewardUnit = value ?? rewardUnit;
                  if (rewardUnit == 'none') {
                    reward.text = '0';
                  } else if (reward.text.trim() == '0') {
                    reward.text = '10';
                  }
                });
              },
            ),
            if (rewardUnit != 'none') ...[
              const SizedBox(height: 10),
              TextFormField(
                controller: reward,
                keyboardType: TextInputType.number,
                decoration: _decoration(t('عدد العملات أو الماسات (1–1000000)',
                    'Coins or diamonds amount (1–1000000)')),
              ),
            ],
            const SizedBox(height: 8),
            Text(t(
              'المكافأة للاستطلاع كاملًا، مرة واحدة للحساب بعد إكمال الإجابات والتحقق منها، وليس لكل سؤال. المسودة لا تصرف أي مكافأة.',
              'One reward per verified completed survey per account, not per question. Drafts cannot pay rewards.',
            ), style: const TextStyle(fontSize: 12, height: 1.4)),
            const SizedBox(height: 10),
            TextFormField(
              controller: days,
              keyboardType: TextInputType.number,
              decoration: _decoration(t('مدة الاستطلاع بالأيام 1–90',
                  'Survey duration in days 1–90')),
            ),
            const SizedBox(height: 7),
            Text(t(
              'المشاركة اختيارية. لا تجمع أرقام الهواتف في الإجابات ولا تربط المكافأة برأي إيجابي. المسودة غير منشورة.',
              'Participation is optional. Never ask for phone numbers or condition rewards on positive feedback. Draft only.',
            ), style: const TextStyle(fontSize: 11, height: 1.5)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t('إلغاء', 'Cancel')),
        ),
        FilledButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.save_outlined),
          label: Text(t('حفظ مسودة', 'Save draft')),
        ),
      ],
    );
  }
}
