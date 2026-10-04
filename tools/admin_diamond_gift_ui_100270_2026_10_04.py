from pathlib import Path

path = Path('lib/admin_pages.dart')
text = path.read_text(encoding='utf-8')
marker = '// DEDA_ADMIN_DIAMOND_GIFT_UI_100270'
if marker in text:
    print('100270 admin diamond gift UI already applied')
    raise SystemExit(0)

anchor = '''                          onTap: () => _open(
                            DedaAdminEntryPhonesPage(isArabic: ar),
                          ),
                        ),
                      if (DedaBackend.adminHasPermission(
                        profile,
                        'viewPlaceRequests',
                      ))'''
replacement = '''                          onTap: () => _open(
                            DedaAdminEntryPhonesPage(isArabic: ar),
                          ),
                        ),
                      if (DedaBackend.normalizeAdminRole(profile['role']) ==
                          'general_manager')
                        _dashboardCard(
                          icon: Icons.diamond_outlined,
                          accentColor: const Color(0xFF6D3CC7),
                          backgroundColor: const Color(0xD9F2ECFF),
                          title: t('هدايا الجواهر', 'Diamond gifts'),
                          subtitle: t(
                            'محفظة المدير العام ومنح المستخدمين',
                            'Manager pool and user gifts',
                          ),
                          onTap: () => _open(
                            DedaAdminDiamondGiftPage(isArabic: ar),
                          ),
                        ),
                      if (DedaBackend.adminHasPermission(
                        profile,
                        'viewPlaceRequests',
                      ))'''
if text.count(anchor) != 1:
    raise SystemExit(f'admin dashboard phones-card anchor count={text.count(anchor)}')
text = text.replace(anchor, replacement, 1)

page = r'''

// DEDA_ADMIN_DIAMOND_GIFT_UI_100270
class DedaAdminDiamondGiftPage extends StatefulWidget {
  final bool isArabic;
  const DedaAdminDiamondGiftPage({super.key, required this.isArabic});

  @override
  State<DedaAdminDiamondGiftPage> createState() =>
      _DedaAdminDiamondGiftPageState();
}

class _DedaAdminDiamondGiftPageState
    extends State<DedaAdminDiamondGiftPage> {
  final _idController = TextEditingController();
  final _amountController = TextEditingController();
  int? _adminBalance;
  Map<String, dynamic>? _target;
  bool _loading = true;
  bool _finding = false;
  bool _sending = false;
  String? _error;

  String t(String ar, String en) => widget.isArabic ? ar : en;

  @override
  void initState() {
    super.initState();
    _loadWallet();
  }

  @override
  void dispose() {
    _idController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _loadWallet() async {
    try {
      final balance = await DedaBackend.ensureGeneralManagerDiamondGiftWallet();
      if (!mounted) return;
      setState(() {
        _adminBalance = balance;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = t(
          'تعذر تجهيز محفظة جواهر المدير العام.',
          'Could not prepare the general-manager diamond wallet.',
        );
      });
    }
  }

  Future<void> _findTarget() async {
    if (_finding) return;
    final raw = _idController.text.trim();
    if (raw.isEmpty) return;
    setState(() {
      _finding = true;
      _target = null;
      _error = null;
    });
    try {
      final target = await DedaBackend.adminDiamondGiftTarget(raw);
      if (!mounted) return;
      setState(() {
        _target = target;
        if (target == null) {
          _error = t(
            'لم يتم العثور على حساب شخصي بهذا المعرف.',
            'No personal account was found with this ID.',
          );
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = t(
            'تعذر التحقق من المعرف الآن.',
            'Could not verify this ID right now.',
          ));
    } finally {
      if (mounted) setState(() => _finding = false);
    }
  }

  Future<void> _grant() async {
    final target = _target;
    final amount = int.tryParse(_amountController.text.trim()) ?? 0;
    final balance = _adminBalance ?? 0;
    if (target == null || amount <= 0) return;
    if (amount > balance) {
      setState(() => _error = t(
            'عدد الجواهر أكبر من الرصيد الإداري المتاح.',
            'The gift is larger than the available administrative balance.',
          ));
      return;
    }

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(t('تأكيد هدية الجواهر', 'Confirm diamond gift')),
            content: Text(
              t(
                'منح $amount جوهرة إلى ${target['displayName']}\n${target['publicId']}؟',
                'Grant $amount diamonds to ${target['displayName']}\n${target['publicId']}?',
              ),
              textAlign: TextAlign.center,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(t('إلغاء', 'Cancel')),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.pop(dialogContext, true),
                icon: const Icon(Icons.card_giftcard_rounded),
                label: Text(t('منح الهدية', 'Grant gift')),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;

    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final result = await DedaBackend.grantDiamondGift(
        targetPublicId: target['publicId'].toString(),
        amount: amount,
      );
      if (!mounted) return;
      setState(() {
        _adminBalance = (result['adminBalance'] as num?)?.toInt() ?? 0;
        _amountController.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            t(
              'تم منح $amount جوهرة بنجاح وحفظ العملية في السجل الإداري.',
              '$amount diamonds were granted and logged successfully.',
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      final raw = error.toString();
      setState(() => _error = raw.contains('insufficient')
          ? t('الرصيد الإداري غير كافٍ.', 'Administrative balance is insufficient.')
          : t('تعذر منح الجواهر الآن.', 'Could not grant diamonds right now.'));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final balance = _adminBalance ?? 0;
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF2),
      appBar: AppBar(
        title: Text(t('هدايا الجواهر', 'Diamond gifts')),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  constraints: const BoxConstraints(minHeight: 82),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF2ECFF),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFCFB9F4)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.diamond_rounded,
                          color: Color(0xFF6D3CC7), size: 34),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              t('رصيد المدير العام للهدايا',
                                  'General-manager gift balance'),
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '$balance 💎',
                              textDirection: TextDirection.ltr,
                              style: const TextStyle(
                                color: Color(0xFF56309D),
                                fontWeight: FontWeight.w900,
                                fontSize: 24,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  height: 56,
                  child: TextField(
                    controller: _idController,
                    textDirection: TextDirection.ltr,
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(
                      labelText: t('معرف DEDA للمستخدم', 'User DEDA ID'),
                      hintText: '@DEDA-XXXXXX',
                      prefixIcon: const Icon(Icons.alternate_email_rounded),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onChanged: (_) {
                      if (_target != null) setState(() => _target = null);
                    },
                    onSubmitted: (_) => _findTarget(),
                  ),
                ),
                const SizedBox(height: 9),
                SizedBox(
                  height: 50,
                  child: FilledButton.icon(
                    onPressed: _finding ? null : _findTarget,
                    icon: _finding
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.search_rounded),
                    label: Text(t('تحقق من المستخدم', 'Verify user')),
                  ),
                ),
                if (_target != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFDDE4DF)),
                    ),
                    child: Row(
                      children: [
                        const CircleAvatar(
                          radius: 22,
                          backgroundColor: Color(0xFFE6F3E8),
                          child: Icon(Icons.person_rounded,
                              color: Color(0xFF17652F)),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                (_target!['displayName'] ?? 'DEDA').toString(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 15,
                                ),
                              ),
                              Text(
                                (_target!['publicId'] ?? '').toString(),
                                textDirection: TextDirection.ltr,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 56,
                    child: TextField(
                      controller: _amountController,
                      keyboardType: TextInputType.number,
                      textDirection: TextDirection.ltr,
                      decoration: InputDecoration(
                        labelText: t('عدد الجواهر', 'Diamond amount'),
                        prefixIcon: const Icon(Icons.diamond_outlined),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: _sending ? null : _grant,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF6D3CC7),
                      ),
                      icon: _sending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.card_giftcard_rounded),
                      label: Text(t('منح الجواهر', 'Grant diamonds')),
                    ),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF9A3412),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Text(
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
              ],
            ),
    );
  }
}
'''

text = text.rstrip() + page + '\n'
path.write_text(text, encoding='utf-8')
print('applied compact 100270 general-manager diamond gift UI')
