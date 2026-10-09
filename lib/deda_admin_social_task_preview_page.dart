import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'deda_social_task_preview.dart';
import 'deda_social_task_live_service.dart';

/// Owner-only social editor with authenticated backend draft/schedule controls.
/// Config can be published by the server after midnight. Rewards stay blocked.
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
  String _platform = 'telegram';
  String _action = 'follow';
  String _unit = 'points';
  bool _doubleWithRewardedAd = false;
  DateTime? _day;
  final _live = const DedaLiveSocialTaskService();
  int _revision = 0;
  String _remoteStatus = 'new';
  String _serverMessage = '';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadRemote();
  }

  Future<void> _loadRemote() async {
    if (Firebase.apps.isEmpty) return;
    try {
      final data = await _live.load();
      if (!mounted) return;
      setState(() {
        _revision = (data['revision'] as num?)?.toInt() ?? 0;
        _remoteStatus = (data['status'] ?? 'new').toString();
        _serverMessage = t('اتصال Firestore آمن: المسودات للمدير فقط.', 'Secure Firestore access: manager-only drafts.');
        final day = (data['scheduledDay'] ?? '').toString();
        if (day.isNotEmpty) _day = DateTime.tryParse(day);
        if (data['exists'] == true) {
          _platform = (data['platform'] ?? 'facebook').toString();
          _action = (data['action'] ?? 'follow').toString();
          _unit = (data['rewardUnit'] ?? 'points').toString();
          _title.text = (data['title'] ?? '').toString();
          _url.text = (data['url'] ?? '').toString();
          _reward.text = (data['rewardAmount'] ?? 5).toString();
          _doubleWithRewardedAd = data['doubleWithRewardedAd'] == true;
          _otherPlatform.text = (data['otherPlatform'] ?? '').toString();
          _otherAction.text = (data['otherAction'] ?? '').toString();
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _serverMessage = t(
        'تعذر الاتصال بـFirestore أو لا توجد صلاحية للمدير العام. لا يوجد نشر.',
        'Firestore unavailable or general manager permission denied.'));
    }
  }

  Future<void> _perform(Future<Map<String, dynamic>> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result = await action();
      if (!mounted) return;
      setState(() {
        _revision = (result['revision'] as num?)?.toInt() ?? _revision;
        _remoteStatus = (result['status'] ?? '').toString();
        _serverMessage = t('تم حفظ العملية في Firestore، ولن تظهر قبل الموعد.', 'Saved on Firestore; invisible until due.');
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _serverMessage = t(
        'رفض Firestore العملية؛ لا يوجد نشر جديد.',
        'Firestore rejected the operation; nothing published.') +
        '\n' + error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveLive() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    final amount = int.tryParse(_reward.text.trim());
    if (amount == null) return;
    if (_platform != 'telegram' || _action != 'follow') {
      setState(() => _serverMessage = t(
        'التجربة الأولى تدعم متابعة قناة تليجرام فقط.',
        'First trial supports Telegram follow only.'));
      return;
    }
    await _perform(() => _live.save(
      expectedRevision: _revision,
      platform: _platform, action: _action,
      title: _title.text, url: _url.text,
      unit: _unit, amount: amount,
      doubleWithAd: _doubleWithRewardedAd,
      otherPlatform: _otherPlatform.text,
      otherAction: _otherAction.text,
    ));
  }

  Future<void> _scheduleLive() async {
    if (_day == null) {
      setState(() => _serverMessage = t(
        'حدد موعد الجدولة أولاً.', 'Select the schedule day first.'));
      return;
    }
    final day = '${_day!.year.toString().padLeft(4, '0')}-'
      '${_day!.month.toString().padLeft(2, '0')}-'
      '${_day!.day.toString().padLeft(2, '0')}';
    await _perform(() => _live.schedule(
      expectedRevision: _revision, iraqDay: day));
  }

  Future<void> _cancelLive() async => _perform(() =>
    _live.cancel(expectedRevision: _revision));

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
    final now = DateTime.now().toUtc().add(const Duration(hours: 3));
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final picked = await showDatePicker(
      context: context,
      initialDate: _day ?? tomorrow,
      firstDate: tomorrow,
      lastDate: DateTime(now.year, now.month, now.day + 31),
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
    final bonus = _doubleWithRewardedAd ? int.parse(_reward.text.trim()) : 0;
    final total = int.parse(_reward.text.trim()) + bonus;
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
           rewardText,
           if (_doubleWithRewardedAd)
             t('بعد الإعلان المكافئ: المجموع $total (إضافة $bonus من نفس نوع المكافأة)، محاكاة فقط.',
               'After rewarded ad: total $total (bonus $bonus), preview only.'),
           dateLabel,
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
              t('تجربة Firestore المباشرة: تليجرام فقط. يحفظ المدير المسودة ثم يجدولها، ولا تظهر للمستخدم إلا بعد منتصف الليل بتوقيت العراق حين يفتح صفحة المهام متصلاً بالإنترنت. لا تُصرف مكافآت.',
                'Direct Firestore trial: Telegram only. Save then schedule. The task appears after Iraq midnight when a user opens the page online. No payouts.'),
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
            const SizedBox(height: 8),
            SwitchListTile.adaptive(
              key: const Key('socialRewardedAdDoubleToggle'),
              contentPadding: const EdgeInsets.symmetric(horizontal: 2),
              title: Text(t('مضاعفة المكافأة بمشاهدة إعلان',
                'Double reward with rewarded ad')),
              subtitle: Text(t(
                'اختياري • يشمل النقاط والعملات والماسات • لا يُصرف شيء في هذه المعاينة',
                'Optional • points, coins and diamonds • no payout in preview')),
              value: _doubleWithRewardedAd,
              onChanged: (value) =>
                  setState(() => _doubleWithRewardedAd = value),
            ),
            const SizedBox(height: 6),
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
              t('يظهر الرابط فقط يوم الموعد بعد منتصف الليل وفتح الصفحة متصلاً بالإنترنت؛ لا توجد إشعارات نشر تلقائية ولا صرف للمكافآت. فتح الرابط لا يثبت الاشتراك.',
                'Publishing does not grant rewards. URL visits are not subscription proof; payouts remain blocked.'),
              style: const TextStyle(
                fontSize: 12, color: Color(0xFF73572B)),
            ),
            const SizedBox(height: 12),
            Text(t('حالة Firestore: $_remoteStatus — الإصدار $_revision',
              'Firestore status: $_remoteStatus — revision $_revision'),
              key: const Key('socialTrialServerStatus'),
              style: const TextStyle(fontWeight: FontWeight.bold)),
            if (_serverMessage.isNotEmpty)
              Text(_serverMessage, key: const Key('socialTrialResult')),
            const SizedBox(height: 10),
            FilledButton(
              key: const Key('socialSaveLiveDraft'),
              onPressed: _busy ? null : _saveLive,
              child: Text(t('حفظ المسودة في Firebase',
                'Save draft on Firebase')),
            ),
            const SizedBox(height: 8),
            FilledButton(
              key: const Key('socialScheduleLive'),
              onPressed: _busy || _remoteStatus != 'draft'
                ? null : _scheduleLive,
              child: Text(t('جدولة النشر لمنتصف الليل',
                'Schedule midnight publishing')),
            ),
            if (_remoteStatus == 'scheduled') ...[
              const SizedBox(height: 8),
              OutlinedButton(
                key: const Key('socialCancelLive'),
                onPressed: _busy ? null : _cancelLive,
                child: Text(t('إلغاء الجدولة', 'Cancel schedule')),
              ),
            ],
            const SizedBox(height: 8),
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
