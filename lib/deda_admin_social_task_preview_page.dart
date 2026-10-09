import 'package:flutter/material.dart';
import 'deda_social_task_preview.dart';

/// General-manager design preview, reached only through the existing protected
/// admin task editor. No Firestore, URL launch, publishing or reward claims.
class DedaAdminSocialTaskPreviewPage extends StatefulWidget {
  const DedaAdminSocialTaskPreviewPage({
    super.key, required this.isArabic,
  });
  final bool isArabic;

  @override
  State<DedaAdminSocialTaskPreviewPage> createState() =>
      _DedaAdminSocialTaskPreviewPageState();
}

class _DedaAdminSocialTaskPreviewPageState
    extends State<DedaAdminSocialTaskPreviewPage> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _url = TextEditingController();
  final _otherPlatform = TextEditingController();
  final _otherAction = TextEditingController();
  final _reward = TextEditingController(text: '5');
  String _platform = 'facebook';
  String _action = 'follow';
  String _unit = 'points';
  DateTime? _day;

  String t(String ar, String en) => widget.isArabic ? ar : en;

  @override
  void dispose() {
    _title.dispose();
    _url.dispose();
    _otherPlatform.dispose();
    _otherAction.dispose();
    _reward.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final picked = await showDatePicker(
      context: context,
      initialDate: _day ?? tomorrow,
      firstDate: tomorrow,
      lastDate: DateTime(now.year + 2, now.month, now.day),
    );
    if (picked != null && mounted) setState(() => _day = picked);
  }

  void _preview() {
    if (!(_form.currentState?.validate() ?? false)) return;
    if (_day == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(t('حدد تاريخ العرض.', 'Choose a scheduled date.')),
      ));
      return;
    }
    final label = _platform == 'other'
        ? _otherPlatform.text.trim()
        : DedaSocialTaskCatalog.platformLabel(_platform, widget.isArabic);
    final action = _action == 'other'
        ? _otherAction.text.trim()
        : DedaSocialTaskCatalog.actionLabel(_action, widget.isArabic);
    final scheduled = _day!;
    final dateLabel = scheduled.day.toString() + '/' +
        scheduled.month.toString() + '/' + scheduled.year.toString();
    final rewardText = _reward.text.trim() + ' ' +
        (_unit == 'points' ? t('نقاط', 'points') :
         _unit == 'coins' ? t('عملات', 'coins') : t('ماسات', 'diamonds'));
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t('معاينة غير منشورة', 'Unpublished preview')),
        content: Text(
          [label, action, _title.text.trim(), _url.text.trim(),
           rewardText, dateLabel,
           t('هذه معاينة محلية فقط. لا حفظ، لا جدولة حقيقية، لا نشر ولا مكافآت.',
             'Local preview only. No saving, scheduling, publishing or rewards.')].join('\n'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t('إغلاق', 'Close')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    InputDecoration decoration(String label) =>
        InputDecoration(labelText: label, border: const OutlineInputBorder());

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF2),
      appBar: AppBar(
        title: Text(t('مهام التواصل الاجتماعي', 'Social task management')),
        backgroundColor: const Color(0xFF0B3156),
        foregroundColor: Colors.white,
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(14),
          children: [
            Text(
              t('نموذج تجريبي للمدير العام فقط، ولا يغير مهمة من المهام الثمانية.',
                'General manager mock form; the eight existing tasks stay unchanged.'),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: const Key('socialPlatformDropdown'),
              initialValue: _platform,
              isExpanded: true,
              decoration: decoration(t('المنصة', 'Platform')),
              items: [
                for (final id in DedaSocialTaskCatalog.platforms)
                  DropdownMenuItem<String>(
                    value: id,
                    child: Text(DedaSocialTaskCatalog.platformLabel(
                      id, widget.isArabic)),
                  ),
              ],
              onChanged: (v) => setState(() => _platform = v ?? _platform),
            ),
            if (_platform == 'other') ...[
              const SizedBox(height: 10),
              TextFormField(
                controller: _otherPlatform,
                decoration: decoration(t('اسم المنصة', 'Other platform name')),
                validator: (v) => (v?.trim().length ?? 0) < 3
                    ? t('حدد اسم المنصة', 'Enter platform name') : null,
              ),
            ],
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              key: const Key('socialActionDropdown'),
              initialValue: _action,
              isExpanded: true,
              decoration: decoration(t('نوع التفاعل', 'Interaction type')),
              items: [
                for (final id in DedaSocialTaskCatalog.actions)
                  DropdownMenuItem<String>(
                    value: id,
                    child: Text(DedaSocialTaskCatalog.actionLabel(
                      id, widget.isArabic)),
                  ),
              ],
              onChanged: (v) => setState(() => _action = v ?? _action),
            ),
            if (_action == 'other') ...[
              const SizedBox(height: 10),
              TextFormField(
                controller: _otherAction,
                decoration: decoration(t('وصف التفاعل', 'Other interaction')),
                validator: (v) => (v?.trim().length ?? 0) < 3
                    ? t('حدد نوع التفاعل', 'Enter interaction') : null,
              ),
            ],
            const SizedBox(height: 10),
            TextFormField(
              controller: _title,
              maxLength: 80,
              decoration: decoration(t('عنوان المهمة', 'Task title')),
              validator: (v) => (v?.trim().length ?? 0) < 3
                  ? t('اكتب عنوان المهمة', 'Enter task title') : null,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _url,
              keyboardType: TextInputType.url,
              decoration: decoration(
                t('رابط الصفحة أو المنشور أو الفيديو', 'Page, post or video URL')),
              validator: (v) {
                final uri = Uri.tryParse(v?.trim() ?? '');
                return uri == null || uri.scheme != 'https' ||
                        uri.host.isEmpty || uri.userInfo.isNotEmpty
                    ? t('اكتب رابط HTTPS صحيح', 'Enter a valid HTTPS URL')
                    : null;
              },
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _unit,
              decoration: decoration(t('نوع المكافأة (تجريبي)', 'Reward (preview)')),
              items: [
                DropdownMenuItem(value: 'points', child: Text(t('نقاط', 'Points'))),
                DropdownMenuItem(value: 'coins', child: Text(t('عملات', 'Coins'))),
                DropdownMenuItem(value: 'diamonds', child: Text(t('ماسات', 'Diamonds'))),
              ],
              onChanged: (v) => setState(() => _unit = v ?? _unit),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _reward,
              keyboardType: TextInputType.number,
              decoration: decoration(t('قيمة المكافأة (تجريبي)', 'Reward amount')),
              validator: (v) {
                final amount = int.tryParse(v?.trim() ?? '');
                return amount == null || amount < 1 || amount > 5000
                    ? t('القيمة من 1 إلى 5000', 'Enter 1 to 5000') : null;
              },
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.calendar_month_rounded),
              label: Text(_day == null
                  ? t('حدد يوم الجدولة (منتصف الليل في العراق)',
                      'Select a day (Iraq midnight)')
                  : _day!.day.toString() + '/' +
                      _day!.month.toString() + '/' +
                      _day!.year.toString()),
            ),
            const SizedBox(height: 10),
            Text(
              t('مجرد فتح رابط أو الضغط على إعجاب لا يثبت المتابعة الفعلية. سنضيف التحقق الآمن قبل تفعيل أي مكافأة.',
                'Opening links or tapping Like is not verified completion. Secure verification is required before rewards.'),
              style: const TextStyle(
                fontSize: 12, color: Color(0xFF73572B)),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const Key('socialAdminPreviewOnly'),
              onPressed: _preview,
              icon: const Icon(Icons.visibility_outlined),
              label: Text(t('عرض المعاينة فقط', 'Preview only')),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF0B3156)),
            ),
          ],
        ),
      ),
    );
  }
}
