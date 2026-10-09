import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'deda_daily_login_offer_preview_policy.dart';

/// Stage 12 - manager-facing LOCAL preview. It has no Firebase imports,
/// remote save, scheduling, claim action, or wallet mutation.
///
/// The parent manager-only page already gates access. Do not route this
/// screen from public user pages until a verified backend exists.
class DedaDailyLoginOfferPreviewPage extends StatefulWidget {
  const DedaDailyLoginOfferPreviewPage({
    super.key,
    required this.isArabic,
    this.previewReferenceUtc,
  });

  final bool isArabic;

  /// Deterministic tests only. Never trust this date for actual reward claims.
  final DateTime? previewReferenceUtc;

  @override
  State<DedaDailyLoginOfferPreviewPage> createState() =>
      _DedaDailyLoginOfferPreviewPageState();
}

class _DedaDailyLoginOfferPreviewPageState
    extends State<DedaDailyLoginOfferPreviewPage> {
  final _formKey = GlobalKey<FormState>();
  final _baseAmount = TextEditingController(text: '10');
  final _offerAmount = TextEditingController(text: '50');
  DedaLoginPreviewUnit _baseUnit = DedaLoginPreviewUnit.points;
  DedaLoginPreviewUnit _offerUnit = DedaLoginPreviewUnit.coins;
  late final String _referenceIraqDay;
  late DateTimeRange _offerRange;
  DedaLoginPreviewPlan? _plan;

  String t(String arabic, String english) =>
      widget.isArabic ? arabic : english;

  @override
  void initState() {
    super.initState();
    _referenceIraqDay = DedaLoginPreviewPlan.todayIraqFrom(
      widget.previewReferenceUtc ?? DateTime.now().toUtc(),
    );
    final tomorrow = DedaLoginPreviewPlan.calendarDateFromDay(
      DedaLoginPreviewPlan.dayAfter(_referenceIraqDay),
    );
    _offerRange = DateTimeRange(
      start: tomorrow,
      end: tomorrow.add(const Duration(days: 1)),
    );
  }

  @override
  void dispose() {
    _baseAmount.dispose();
    _offerAmount.dispose();
    super.dispose();
  }

  Future<void> _chooseDays() async {
    final tomorrow = DedaLoginPreviewPlan.calendarDateFromDay(
      DedaLoginPreviewPlan.dayAfter(_referenceIraqDay),
    );
    final lastDate = tomorrow.add(const Duration(days: 365));
    final initial = _offerRange.end.isAfter(lastDate) ? null : _offerRange;
    final selected = await showDateRangePicker(
      context: context,
      firstDate: tomorrow,
      lastDate: lastDate,
      initialDateRange: initial,
      helpText: t('أيام العرض حسب بغداد', 'Offer days in Baghdad'),
      saveText: t('اعتماد للمعاينة', 'Use in preview'),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _offerRange = selected;
      _plan = null;
    });
  }

  String? _amountValidator(String? value) {
    final amount = int.tryParse(value?.trim() ?? '');
    if (amount == null || amount < 1 || amount > 5000) {
      return t('أدخل رقمًا من 1 إلى 5000', 'Enter a number from 1 to 5000');
    }
    return null;
  }

  Widget _amountField(TextEditingController controller, String label,
      Key key) {
    return TextFormField(
      key: key,
      controller: controller,
      decoration: InputDecoration(
        border: const OutlineInputBorder(),
        labelText: label,
      ),
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      validator: _amountValidator,
      onChanged: (_) {
        if (_plan != null) setState(() => _plan = null);
      },
    );
  }

  Widget _unitField({
    required DedaLoginPreviewUnit selected,
    required String label,
    required Key key,
    required ValueChanged<DedaLoginPreviewUnit> onChanged,
  }) {
    return DropdownButtonFormField<DedaLoginPreviewUnit>(
      key: key,
      initialValue: selected,
      isExpanded: true,
      decoration: InputDecoration(
        border: const OutlineInputBorder(),
        labelText: label,
      ),
      items: DedaLoginPreviewUnit.values.map((unit) =>
        DropdownMenuItem(
          value: unit,
          child: Text(widget.isArabic ? unit.titleAr : unit.titleEn),
        ),
      ).toList(),
      onChanged: (value) {
        if (value != null) {
          setState(() {
            onChanged(value);
            _plan = null;
          });
        }
      },
    );
  }

  String _rewardLabel(DedaLoginPreviewReward reward) {
    final unit = widget.isArabic ? reward.unit.titleAr : reward.unit.titleEn;
    return reward.amount.toString() + ' ' + unit;
  }

  void _simulate() {
    if (!_formKey.currentState!.validate()) return;
    final plan = DedaLoginPreviewPlan(
      base: DedaLoginPreviewReward(
        amount: int.parse(_baseAmount.text.trim()),
        unit: _baseUnit,
      ),
      offer: DedaLoginPreviewOffer(
        startDay: DedaLoginPreviewPlan.dayFromCalendarDate(_offerRange.start),
        endDay: DedaLoginPreviewPlan.dayFromCalendarDate(_offerRange.end),
        reward: DedaLoginPreviewReward(
          amount: int.parse(_offerAmount.text.trim()),
          unit: _offerUnit,
        ),
      ),
    );
    final error = plan.validate(currentIraqDay: _referenceIraqDay);
    if (error != null) {
      final explanation = error == 'invalid-offer-duration'
          ? t('مدة العرض من يوم إلى 31 يومًا فقط.',
              'The offer must last between 1 and 31 days.')
          : t('تأكد من تاريخ الغد أو بعده وصحة مبلغ المكافأة.',
              'Check the future dates and reward amount.');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(explanation)),
      );
      return;
    }
    setState(() => _plan = plan);
  }

  Widget _resultRow(DedaLoginPreviewPlan plan,
      String caption, String day) {
    final active = plan.isOfferDay(day);
    final reward = plan.rewardForDay(day);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(caption + ' (' + day + ')',
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          Expanded(
            flex: 2,
            child: Text(
              _rewardLabel(reward),
              textAlign: TextAlign.end,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: active
                    ? const Color(0xFF0B6B49)
                    : const Color(0xFF263D57),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _result(DedaLoginPreviewPlan plan) {
    final start = plan.offer.startDay;
    final end = plan.offer.endDay;
    final before = DedaLoginPreviewPlan.calendarDateFromDay(start)
        .subtract(const Duration(days: 1));
    final beforeDay = DedaLoginPreviewPlan.dayFromCalendarDate(before);
    final after = DedaLoginPreviewPlan.dayAfter(end);
    return Card(
      key: const Key('loginPreviewResults'),
      color: const Color(0xFFEDF6EE),
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              t('نتيجة المحاكاة فقط', 'Simulation results only'),
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w900,
                color: Color(0xFF175B3B),
              ),
            ),
            const SizedBox(height: 9),
            _resultRow(plan, t('قبل العرض', 'Before'), beforeDay),
            _resultRow(plan, t('بداية العرض', 'First day'), start),
            _resultRow(plan, t('آخر يوم', 'Last day'), end),
            _resultRow(plan, t('بعد نهاية العرض', 'After expiry'), after),
            const Divider(),
            Text(
              t(
                'الرجوع تلقائي للمكافأة العادية بعد انتهاء العرض. ما انحفظ أي موعد، وما انضافت نقاط أو عملات أو ماسات لأي حساب.',
                'After expiry the regular reward returns automatically. No schedule was saved and no points, coins or diamonds were issued.',
              ),
              style: const TextStyle(height: 1.5, fontSize: 12.5),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF2),
      appBar: AppBar(
        title: Text(t('معاينة مكافأة تسجيل الدخول',
            'Daily login reward preview')),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 650),
            child: ListView(
              padding: const EdgeInsets.all(13),
              children: [
                Card(
                  color: const Color(0xFF0B3156),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          t('تسجيل الدخول اليومي ثابت',
                              'Daily login task is fixed'),
                          style: const TextStyle(
                            color: Color(0xFFFFD76A),
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          t(
                            'نسخة المستخدم الحالية: 10 نقاط يوميًا. هذه شاشة معاينة للمدير العام فقط، لا تنشر عروضًا ولا تغيّر رصيد أحد.',
                            'Current user app: 10 points per day. This manager-only preview does not publish offers or change any balance.',
                          ),
                          style: const TextStyle(
                            color: Colors.white, height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(t('المكافأة العادية (افتراضية في المعاينة)',
                          'Regular reward (preview only)'),
                          style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 9),
                      _unitField(
                        key: const Key('regularUnit'),
                        selected: _baseUnit,
                        label: t('نوع المكافأة', 'Reward unit'),
                        onChanged: (value) => _baseUnit = value,
                      ),
                      const SizedBox(height: 10),
                      _amountField(_baseAmount,
                          t('قيمة المكافأة العادية', 'Regular amount'),
                          const Key('regularAmount')),
                      const SizedBox(height: 17),
                      Text(t('عرض المناسبات المؤقت', 'Temporary holiday offer'),
                          style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 8),
                      _unitField(
                        key: const Key('offerUnit'),
                        selected: _offerUnit,
                        label: t('نوع مكافأة العرض', 'Offer reward unit'),
                        onChanged: (value) => _offerUnit = value,
                      ),
                      const SizedBox(height: 10),
                      _amountField(_offerAmount,
                          t('قيمة مكافأة العرض', 'Offer reward amount'),
                          const Key('offerAmount')),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        key: const Key('chooseOfferDays'),
                        onPressed: _chooseDays,
                        icon: const Icon(Icons.date_range_outlined),
                        label: Text(
                          t('اختيار أيام العرض', 'Choose offer dates') +
                          ': ' +
                          DedaLoginPreviewPlan.dayFromCalendarDate(
                            _offerRange.start) +
                          ' — ' +
                          DedaLoginPreviewPlan.dayFromCalendarDate(
                            _offerRange.end),
                        ),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        key: const Key('simulateLoginOffer'),
                        onPressed: _simulate,
                        icon: const Icon(Icons.visibility_outlined),
                        label: Text(t('عرض نتيجة المحاكاة', 'Preview results')),
                      ),
                      if (_plan != null) ...[
                        const SizedBox(height: 13),
                        _result(_plan!),
                        const SizedBox(height: 7),
                        TextButton.icon(
                          onPressed: () => setState(() => _plan = null),
                          icon: const Icon(Icons.clear),
                          label: Text(t('مسح نتيجة المحاكاة',
                              'Clear preview results')),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  t(
                    'تنبيه: التواريخ المعروضة اعتمادًا على يوم الجهاز للمعاينة فقط. التفعيل الحقيقي يحتاج ساعة خادم موثوقة، تحقق المدير العام، حماية App Check، ودفتر مكافآت مستقل.',
                    'Warning: the device date is used for preview only. Live activation requires a trusted server clock, manager authorization, App Check and a separate reward ledger.',
                  ),
                  style: const TextStyle(
                    color: Color(0xFF755A29), height: 1.45,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
