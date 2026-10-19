import 'package:flutter/material.dart';

// DEDA_STAGE31_OWNER_SANDBOX_NO_ACCOUNT_WRITE_2026_10_19
// PRIVATE visual test ONLY. In-memory fake diamonds, IDs, and grants;
// no real wallet, Firestore, account data, private admin catalog or storage.
enum DedaQaStyle { gold, diamond, royal, pink }

extension DedaQaStyleVisual on DedaQaStyle {
  String get label {
    switch (this) {
      case DedaQaStyle.gold: return 'ذهبي';
      case DedaQaStyle.diamond: return 'ماسي';
      case DedaQaStyle.royal: return 'ملكي';
      case DedaQaStyle.pink: return 'وردي';
    }
  }
  Color get color {
    switch (this) {
      case DedaQaStyle.gold: return const Color(0xFFAD8100);
      case DedaQaStyle.diamond: return const Color(0xFF287BA3);
      case DedaQaStyle.royal: return const Color(0xFF7342B2);
      case DedaQaStyle.pink: return const Color(0xFFB93F85);
    }
  }
}

class DedaQaLedger {
  static const int initial = 25000;
  int balance = initial;
  final Set<DedaQaStyle> cards = <DedaQaStyle>{};
  DedaQaStyle? activeStyle;
  bool demoIdOwned = false;
  bool demoIdActive = false;
  final Map<String,DedaQaStyle> grants = <String,DedaQaStyle>{};
  bool buyCard(DedaQaStyle s) {
    if (cards.contains(s) || balance < 5000) return false;
    balance -= 5000;
    cards.add(s);
    return true;
  }
  bool useCard(DedaQaStyle s) {
    if (!cards.contains(s)) return false;
    activeStyle = s;
    return true;
  }
  bool buyId() {
    if (demoIdOwned || balance < 10000) return false;
    balance -= 10000;
    demoIdOwned = true;
    return true;
  }
  bool useId() {
    if (!demoIdOwned) return false;
    demoIdActive = true;
    return true;
  }
  bool grant(String recipient, DedaQaStyle s) {
    final normalized = recipient.trim().toUpperCase();
    if (!RegExp(r'^@DEDA-[A-Z2-9]{6}$').hasMatch(normalized)) return false;
    grants[normalized] = s;
    return true;
  }
}

class DedaOwnerQaSandboxPage extends StatefulWidget {
  const DedaOwnerQaSandboxPage({super.key});
  @override
  State<DedaOwnerQaSandboxPage> createState() =>
      _DedaOwnerQaSandboxPageState();
}

class _DedaOwnerQaSandboxPageState extends State<DedaOwnerQaSandboxPage> {
  final DedaQaLedger ledger = DedaQaLedger();
  final TextEditingController recipient = TextEditingController();
  DedaQaStyle grantStyle = DedaQaStyle.gold;
  String status = '';
  @override
  void dispose() { recipient.dispose(); super.dispose(); }

  void action(bool Function() run, String success) {
    setState(() {
      status = run() ? success + ' (تجريبي فقط)' :
          'التجربة غير ممكنة: تأكد من الرصيد أو الملكية';
    });
  }
  Widget section(String label, Widget body) => Card(
    color: Colors.white,
    child: Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(label,style: const TextStyle(fontSize: 16,
              fontWeight: FontWeight.w900)),
          const SizedBox(height: 7),
          body,
        ],
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final visual = (ledger.activeStyle ?? DedaQaStyle.gold).color;
    return Scaffold(
      key: const Key('deda_stage31_qa_screen'),
      appBar: AppBar(title: const Text('DEDA | مختبر الشراء الخاص')),
      backgroundColor: const Color(0xFFF8FAF2),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: <Widget>[
            const Text(
              'تجربة خاصة فقط — لا شراء حقيقي ولا خصم من ماسات حسابك '
              'ولا إرسال معرّفات لأي شخص. تغلق الصفحة فتلغى التجربة.',
              key: Key('deda_stage31_qa_warning'),
              style: TextStyle(color: Color(0xFFA03B26),
                fontSize: 14,fontWeight: FontWeight.w900),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text('ماسات الاختبار: ' + ledger.balance.toString(),
              key: const Key('deda_stage31_qa_balance'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 19,
                color: Color(0xFF0A477E),fontWeight: FontWeight.bold)),
            section('بطاقة ملف تجريبية',Container(
              key: const Key('deda_stage31_qa_preview'),
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                border: Border.all(color: visual,width: 2),
                borderRadius: BorderRadius.circular(12),
                color: const Color(0xFFFFFBF0)),
              child: Column(children: <Widget>[
                const CircleAvatar(radius: 27,
                  child: Icon(Icons.person_outline)),
                const Text('حساب فحص وهمي — غير مرتبط بالمستخدم'),
                Text(ledger.demoIdActive
                    ? '@DEDA-QA1001 (تجربة)' : '@DEDA-DEMO01 (مثال)'),
                Text('لون البطاقة: ' +
                  (ledger.activeStyle?.label ?? 'بدون تفعيل'),
                  key: const Key('deda_stage31_qa_active_card')),
              ]),
            )),
            section('بطاقات التصميم — 5,000 ماسة تجريبية للواحدة',
              Column(children: <Widget>[
                for (final s in DedaQaStyle.values)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(children: <Widget>[
                      Container(width: 28,height: 26,color: s.color),
                      const SizedBox(width: 8),
                      Expanded(child: Text(s.label)),
                      FilledButton(
                        key: Key('deda_stage31_card_' + s.name),
                        onPressed: () => action(
                          () => ledger.cards.contains(s) ?
                            ledger.useCard(s) : ledger.buyCard(s),
                          ledger.cards.contains(s)
                            ? 'تم استخدام البطاقة'
                            : 'تم شراء البطاقة'),
                        child: Text(ledger.cards.contains(s)
                          ? 'استخدام' : 'شراء 5,000'),
                      ),
                    ]),
                  ),
              ])),
            section('معرّف مرشح وهمي — 10,000 ماسة تجريبية',
              Column(children: <Widget>[
                const Text('@DEDA-QA1001 | مثال غير معروض للبيع الحقيقي'),
                FilledButton(
                  key: const Key('deda_stage31_id_action'),
                  onPressed: () => action(
                    ledger.demoIdOwned ? ledger.useId : ledger.buyId,
                    ledger.demoIdOwned ? 'تم تفعيل المعرّف'
                      : 'تم شراء المعرّف'),
                  child: Text(ledger.demoIdOwned
                      ? 'استخدام المعرّف' : 'شراء 10,000'),
                ),
                if (ledger.demoIdOwned)
                  const Text('مملوك في الاختبار فقط',
                    key: Key('deda_stage31_owned_id')),
              ])),
            section('محاكاة منحة المدير العام — لا إرسال حقيقي',
              Column(children: <Widget>[
                const Text('قائمة الـ100 المحجوزة غير مضمنة في APK. '
                  'هذا اختبار شكل المنح واختيار اللون فقط.'),
                TextField(
                  key: const Key('deda_stage31_recipient'),
                  controller: recipient,
                  decoration: const InputDecoration(
                    labelText: 'المستلم التجريبي @DEDA-ABC234',
                    border: OutlineInputBorder()),
                ),
                DropdownButton<DedaQaStyle>(
                  key: const Key('deda_stage31_grant_color'),
                  value: grantStyle,isExpanded: true,
                  onChanged: (v) => setState(
                    () => grantStyle = v ?? DedaQaStyle.gold),
                  items: <DropdownMenuItem<DedaQaStyle>>[
                    for (final s in DedaQaStyle.values)
                      DropdownMenuItem(value:s,child:Text(s.label)),
                  ],
                ),
                FilledButton(
                  key: const Key('deda_stage31_grant_action'),
                  onPressed: () => action(
                    () => ledger.grant(recipient.text,grantStyle),
                    'تمت محاكاة المنحة بدون إرسال'),
                  child: const Text('محاكاة المنح'),
                ),
                for (final e in ledger.grants.entries)
                  Text(e.key + ' — ' + e.value.label + ' (وهمي)',
                    key: Key('deda_stage31_grant_' + e.key)),
              ])),
            if (status.isNotEmpty)
              Text(status,key: const Key('deda_stage31_status'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF165B4A),
                  fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }
}
