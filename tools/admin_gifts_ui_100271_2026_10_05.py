from pathlib import Path

path = Path('lib/admin_pages.dart')
text = path.read_text(encoding='utf-8')
marker = '// DEDA_ADMIN_GIFTS_UI_100271'
if marker in text:
    print('100271 admin gifts UI already applied')
    raise SystemExit(0)

class_start = text.find('class _DedaAdminDiamondGiftPageState')
if class_start < 0:
    raise SystemExit('100270 admin diamond gift page not found')

controllers = '''  final _idController = TextEditingController();
  final _amountController = TextEditingController();
'''
controllers_new = '''  // DEDA_ADMIN_GIFTS_UI_100271
  final _idController = TextEditingController();
  final _amountController = TextEditingController();
  final _reasonController = TextEditingController();
  String _reasonChoice = 'مكافأة من إدارة DEDA';
  static const List<String> _reasonOptions = <String>[
    'لحسن سلوكك داخل DEDA',
    'لتصدرك المركز الأول',
    'لفوزك في مسابقة',
    'لمساهمتك المميزة',
    'مكافأة من إدارة DEDA',
    'سبب آخر',
  ];
'''
if text.count(controllers) != 1:
    raise SystemExit(f'admin gift controllers anchor count={text.count(controllers)}')
text = text.replace(controllers, controllers_new, 1)

dispose = '''    _idController.dispose();
    _amountController.dispose();
    super.dispose();
'''
dispose_new = '''    _idController.dispose();
    _amountController.dispose();
    _reasonController.dispose();
    super.dispose();
'''
if text.count(dispose) != 1:
    raise SystemExit(f'admin gift dispose anchor count={text.count(dispose)}')
text = text.replace(dispose, dispose_new, 1)

amount_block = '''    final amount = int.tryParse(_amountController.text.trim()) ?? 0;
    final balance = _adminBalance ?? 0;
    if (target == null || amount <= 0) return;
'''
amount_new = '''    final amount = int.tryParse(_amountController.text.trim()) ?? 0;
    final balance = _adminBalance ?? 0;
    final reason = _reasonChoice == 'سبب آخر'
        ? _reasonController.text.trim()
        : _reasonChoice;
    if (target == null || amount <= 0) return;
    if (reason.isEmpty) {
      setState(() => _error = t(
            'اكتب سبب الهدية أولًا.',
            'Enter the gift reason first.',
          ));
      return;
    }
'''
if text.count(amount_block) != 1:
    raise SystemExit(f'admin gift amount anchor count={text.count(amount_block)}')
text = text.replace(amount_block, amount_new, 1)

confirm_old = '''                'منح $amount جوهرة إلى ${target['displayName']}\\n${target['publicId']}؟',
                'Grant $amount diamonds to ${target['displayName']}\\n${target['publicId']}?',
'''
confirm_new = '''                'منح $amount جوهرة إلى ${target['displayName']}\\n${target['publicId']}؟\\n\\nالسبب: $reason',
                'Grant $amount diamonds to ${target['displayName']}\\n${target['publicId']}?\\n\\nReason: $reason',
'''
if text.count(confirm_old) != 1:
    raise SystemExit(f'admin confirmation text anchor count={text.count(confirm_old)}')
text = text.replace(confirm_old, confirm_new, 1)

backend_call = '''      final result = await DedaBackend.grantDiamondGift(
        targetPublicId: target['publicId'].toString(),
        amount: amount,
      );'''
backend_call_new = '''      final result = await DedaBackend.grantDiamondGift(
        targetPublicId: target['publicId'].toString(),
        amount: amount,
        reason: reason,
      );'''
if text.count(backend_call) != 1:
    raise SystemExit(f'admin backend gift call count={text.count(backend_call)}')
text = text.replace(backend_call, backend_call_new, 1)

success_old = '''              'تم منح $amount جوهرة بنجاح وحفظ العملية في السجل الإداري.',
              '$amount diamonds were granted and logged successfully.',
'''
success_new = '''              'تم إرسال هدية $amount 💎 وهي الآن بانتظار استلام المستخدم.',
              'The $amount 💎 gift was sent and is waiting for the user to receive it.',
'''
if text.count(success_old) != 1:
    raise SystemExit(f'admin success message anchor count={text.count(success_old)}')
text = text.replace(success_old, success_new, 1)

# Insert reason selector between amount and send button.
amount_field_tail = '''                  const SizedBox(height: 10),
                  SizedBox(
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: _sending ? null : _grant,
'''
reason_ui = '''                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: _reasonChoice,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: t('سبب المكافأة', 'Gift reason'),
                      prefixIcon: const Icon(Icons.notes_rounded),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    items: _reasonOptions
                        .map((value) => DropdownMenuItem<String>(
                              value: value,
                              child: Text(value,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                            ))
                        .toList(),
                    onChanged: _sending
                        ? null
                        : (value) {
                            if (value == null) return;
                            setState(() {
                              _reasonChoice = value;
                              _error = null;
                            });
                          },
                  ),
                  if (_reasonChoice == 'سبب آخر') ...<Widget>[
                    const SizedBox(height: 10),
                    TextField(
                      controller: _reasonController,
                      minLines: 1,
                      maxLines: 3,
                      maxLength: 220,
                      decoration: InputDecoration(
                        labelText: t('اكتب السبب', 'Write the reason'),
                        prefixIcon: const Icon(Icons.edit_note_rounded),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: _sending ? null : _grant,
'''
if text.count(amount_field_tail) != 1:
    raise SystemExit(f'admin send button anchor count={text.count(amount_field_tail)}')
text = text.replace(amount_field_tail, reason_ui, 1)

# Add a date formatter method before build.
build_anchor = '''  @override
  Widget build(BuildContext context) {
    final balance = _adminBalance ?? 0;
'''
formatter = '''  String _giftTime(dynamic raw) {
    DateTime? value;
    if (raw is Timestamp) value = raw.toDate().toLocal();
    if (value == null) return t('غير متاح', 'Unavailable');
    String two(int n) => n.toString().padLeft(2, '0');
    return '${value.year}/${two(value.month)}/${two(value.day)} '
        '${two(value.hour)}:${two(value.minute)}';
  }

'''
if text.count(build_anchor) != 1:
    raise SystemExit(f'admin build anchor count={text.count(build_anchor)}')
text = text.replace(build_anchor, formatter + build_anchor, 1)

# Insert permanent administrative gift ledger immediately before the ListView
# children close. Use class-local bounds so no unrelated list is touched.
class_end = text.find('\n}\n', class_start)
while class_end >= 0 and class_end < text.find("print('impossible')"):
    # This loop is intentionally bypassed; class end is located below by a
    # unique tail from the 100270 page.
    break

tail = '''                Text(
                  t(
                    'كل هدية تُخصم من الرصيد الإداري وتُحفظ في سجل غير قابل للتعديل.',
                    'Every gift is deducted from the administrative balance and stored in an immutable log.',
                  ),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF67716A),
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
'''
ledger = tail + r'''                const SizedBox(height: 18),
                Row(
                  children: <Widget>[
                    const Icon(Icons.history_rounded,
                        color: Color(0xFF56309D), size: 22),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        t('سجل هدايا الإدارة', 'Administration gift history'),
                        style: const TextStyle(
                          color: Color(0xFF30254A),
                          fontWeight: FontWeight.w900,
                          fontSize: 17,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                StreamBuilder<List<Map<String, dynamic>>>(
                  stream: DedaBackend.watchCurrentAdminDiamondGifts(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting &&
                        !snapshot.hasData) {
                      return const Padding(
                        padding: EdgeInsets.all(14),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    final gifts = snapshot.data ?? const <Map<String, dynamic>>[];
                    if (gifts.isEmpty) {
                      return Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFDDE4DF)),
                        ),
                        child: Text(
                          t('لا توجد هدايا مسجلة بعد.',
                              'No gifts have been recorded yet.'),
                          textAlign: TextAlign.center,
                        ),
                      );
                    }
                    return Column(
                      children: gifts.map((gift) {
                        final received =
                            (gift['status'] ?? '').toString() == 'received';
                        final amount =
                            ((gift['amount'] as num?)?.toInt() ?? 0);
                        final target =
                            (gift['targetName'] ?? 'DEDA').toString();
                        final targetId =
                            (gift['targetPublicId'] ?? '').toString();
                        final reason = (gift['reason'] ?? '').toString();
                        return Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(11),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: received
                                  ? const Color(0xFFCDE5D4)
                                  : const Color(0xFFE2D2F5),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              Row(
                                children: <Widget>[
                                  Expanded(
                                    child: Text(
                                      target,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                        color: Color(0xFF24384A),
                                      ),
                                    ),
                                  ),
                                  Text(
                                    '$amount 💎',
                                    textDirection: TextDirection.ltr,
                                    style: const TextStyle(
                                      color: Color(0xFF6D3CC7),
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ],
                              ),
                              Text(
                                targetId,
                                textDirection: TextDirection.ltr,
                                style: const TextStyle(
                                  color: Color(0xFF6C7A85),
                                  fontSize: 11.5,
                                ),
                              ),
                              if (reason.isNotEmpty) ...<Widget>[
                                const SizedBox(height: 5),
                                Text(reason,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700)),
                              ],
                              const SizedBox(height: 5),
                              Row(
                                children: <Widget>[
                                  Expanded(
                                    child: Text(
                                      _giftTime(gift['createdAt']),
                                      style: const TextStyle(
                                        color: Color(0xFF78857E),
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    received
                                        ? t('تم الاستلام', 'Received')
                                        : t('بانتظار الاستلام', 'Pending'),
                                    style: TextStyle(
                                      color: received
                                          ? const Color(0xFF16794A)
                                          : const Color(0xFF9A6700),
                                      fontWeight: FontWeight.w900,
                                      fontSize: 11.5,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),
'''
if text.count(tail) != 1:
    raise SystemExit(f'admin gift ledger tail anchor count={text.count(tail)}')
text = text.replace(tail, ledger, 1)

path.write_text(text, encoding='utf-8')
print('applied DEDA 100271 admin gift reasons + permanent ledger UI')
