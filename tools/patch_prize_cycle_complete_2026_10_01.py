from pathlib import Path

MAIN = Path('lib/main.dart')
BACKEND = Path('lib/deda_backend.dart')
PRIZE = Path('lib/prize_winner_pages.dart')
RULES = Path('firestore.rules')
BUILD = Path('.github/workflows/build.yml')
DEPLOY = Path('.github/workflows/deploy-prize-winners-firestore.yml')
VALIDATOR = Path('tools/validate_prize_cycle_complete_2026_10_01.py')


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected exactly 1 match, found {count}')
    return text.replace(old, new, 1)


def replace_between(text: str, start: str, end: str, replacement: str, label: str) -> str:
    i = text.find(start)
    if i < 0:
        raise SystemExit(f'{label}: start marker not found')
    j = text.find(end, i)
    if j < 0:
        raise SystemExit(f'{label}: end marker not found')
    return text[:i] + replacement + text[j:]


# ---------------------------------------------------------------------------
# main.dart — keep the prize card live until delivery confirmation, then close
# the cycle visibly and direct the winner to the next event.
# ---------------------------------------------------------------------------
s = MAIN.read_text(encoding='utf-8')
final_method = r'''  Widget _finalPrizeBackFace({
    required int threshold,
    required int totalPoints,
  }) {
    const gold = Color(0xFFFFD76A);
    const deep = Color(0xFF080705);
    final thresholdLabel = _formatPointTier(threshold);
    final rewardCode = _rewardCode16();

    return StreamBuilder<Map<String, dynamic>?>(
      stream: DedaBackend.prizeWinnerRequestForUser(DedaPreferences.phone),
      builder: (context, snapshot) {
        final request = snapshot.data;
        final status = (request?['status'] ?? '').toString();
        final delivered = status == 'delivered';
        final hasRequest = request != null;

        return Column(
          key: ValueKey<String>('reward-final-$threshold-$status'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'DEDA',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 2.1,
              ),
            ),
            const SizedBox(height: 5),
            const Icon(Icons.emoji_events_rounded, color: gold, size: 38),
            const SizedBox(height: 4),
            Text(
              delivered
                  ? dedaText(
                      '🏆 تم استلام جائزتك بنجاح',
                      '🏆 Prize received successfully',
                    )
                  : dedaText(
                      '🎉 مبروك! أكملت جميع المراحل',
                      '🎉 Congratulations! All stages completed',
                    ),
              textAlign: TextAlign.center,
              maxLines: 2,
              style: const TextStyle(
                color: gold,
                fontSize: 12.5,
                fontWeight: FontWeight.w900,
                height: 1.15,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              dedaText('رمز الجائزة الكامل', 'Complete prize code'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xCC020914),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: gold, width: 1.4),
              ),
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: SelectableText(
                    rewardCode,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.7,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 5),
            Text(
              delivered
                  ? dedaText(
                      'شكرًا لمشاركتك مع DEDA 🌟',
                      'Thank you for joining DEDA 🌟',
                    )
                  : dedaText(
                      'لقد حصلت على الجائزة النهائية 👏',
                      'You earned the final prize 👏',
                    ),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: gold,
                fontSize: 10.5,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              delivered
                  ? dedaText(
                      'انتظر الحدث القادم وشارك من جديد يا عزيزي.',
                      'Wait for the next event and join again.',
                    )
                  : dedaText(
                      '$thresholdLabel نقطة خُصمت لإكمال المرحلة النهائية ولا تعاد إلى الرصيد.',
                      '$thresholdLabel points were spent on the final stage and are not returned.',
                    ),
              textAlign: TextAlign.center,
              maxLines: 2,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 8.6,
                fontWeight: FontWeight.w700,
                height: 1.15,
              ),
            ),
            const SizedBox(height: 6),
            if (!delivered)
              SizedBox(
                height: 38,
                child: Material(
                  color: deep,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      Navigator.push<void>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => DedaPrizeWinnerRequestPage(
                            isArabic: DedaLanguageState.isArabic,
                            name: DedaPreferences.userName,
                            phone: DedaPreferences.phone,
                            dedaId: _personalDedaId,
                            rewardCode: rewardCode,
                            pointsAtCompletion: totalPoints,
                          ),
                        ),
                      );
                    },
                    child: Container(
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: gold, width: 1.2),
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          hasRequest
                              ? dedaText(
                                  'متابعة طلب الجائزة مع الإدارة',
                                  'Follow prize request with administration',
                                )
                              : dedaText(
                                  'مراسلة الإدارة للمطالبة بالجائزة',
                                  'Contact administration to claim prize',
                                ),
                          maxLines: 1,
                          style: const TextStyle(
                            color: gold,
                            fontSize: 10.3,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                decoration: BoxDecoration(
                  color: const Color(0xFF18351F),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: gold.withOpacity(0.75)),
                ),
                child: Text(
                  dedaText(
                    '✅ تم تأكيد الاستلام وإغلاق دورة الجوائز الحالية',
                    '✅ Receipt confirmed and this prize cycle is closed',
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: const TextStyle(
                    color: gold,
                    fontSize: 9.8,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.lock_rounded, color: gold, size: 14),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    delivered
                        ? dedaText(
                            'اكتملت الدورة • البطاقات مغلقة • انتظر الحدث القادم',
                            'Cycle completed • cards locked • wait for the next event',
                          )
                        : dedaText(
                            'البطاقات مكتملة • طلب الجائزة قيد المتابعة',
                            'Cards completed • prize request in progress',
                          ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: gold,
                      fontSize: 9.2,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

'''
s = replace_between(
    s,
    '  Widget _finalPrizeBackFace({',
    '  Widget _rewardTierBackFace({',
    final_method,
    'replace final prize card face',
)
MAIN.write_text(s, encoding='utf-8')


# ---------------------------------------------------------------------------
# deda_backend.dart — user receipt confirmation is authoritative. Admin sends
# the prize; only the winner can finish the cycle. Also retain an explicit v1
# cycle id so a later event can use a new id without touching old winners.
# ---------------------------------------------------------------------------
b = BACKEND.read_text(encoding='utf-8')
if 'static const String prizeWinnerCycleId' not in b:
    b = replace_once(
        b,
        '  static String _prizeWinnerRequestIdForPhone(String phone) {\n',
        "  static const String prizeWinnerCycleId = 'prize_v1';\n\n"
        '  static String _prizeWinnerRequestIdForPhone(String phone) {\n',
        'insert prize cycle id',
    )
b = b.replace("return 'prize_v1_$accountKey';", "return '${prizeWinnerCycleId}_$accountKey';")
b = b.replace(".doc('prize_v1_$accountKey')", ".doc('${prizeWinnerCycleId}_$accountKey')")
if "'cycleId': prizeWinnerCycleId," not in b:
    b = replace_once(
        b,
        "      'ownerUid': user.uid,\n",
        "      'ownerUid': user.uid,\n      'cycleId': prizeWinnerCycleId,\n",
        'persist prize cycle id',
    )

confirm_anchor = '''  static Stream<QuerySnapshot<Map<String, dynamic>>>
      prizeWinnerRequestsForAdmin() {
'''
confirm_method = r'''  static Future<void> confirmPrizeReceivedByUser({
    required String phone,
  }) async {
    final accountKey = accountKeyForPhone(phone);
    if (accountKey.isEmpty) throw ArgumentError('prize-account-required');
    await _ensureOwnerSessionForAccountKey(accountKey);
    final ref = FirebaseFirestore.instance
        .collection('prize_winner_requests')
        .doc(_prizeWinnerRequestIdForPhone(phone));
    final snapshot = await ref.get();
    final data = snapshot.data();
    if (!snapshot.exists || data == null) {
      throw StateError('prize-request-not-found');
    }
    if ((data['accountKey'] ?? '').toString() != accountKey) {
      throw StateError('prize-request-owner-mismatch');
    }
    if ((data['status'] ?? '').toString() != 'prize_sent') {
      throw StateError('prize-not-awaiting-confirmation');
    }
    await ref.update(<String, dynamic>{
      'status': 'delivered',
      'winnerConfirmedAt': FieldValue.serverTimestamp(),
      'deliveredAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

'''
if 'confirmPrizeReceivedByUser' not in b:
    b = replace_once(b, confirm_anchor, confirm_method + confirm_anchor,
                     'insert winner receipt confirmation')

b = b.replace('.limit(200)\n        .snapshots();', '.limit(500)\n        .snapshots();')
old_allowed = '''    const allowed = <String>{
      'new',
      'reviewing',
      'needs_info',
      'approved',
      'prize_sent',
      'delivered',
      'rejected',
    };
'''
new_allowed = '''    const allowed = <String>{
      'new',
      'reviewing',
      'needs_info',
      'approved',
      'prize_sent',
      'rejected',
    };
'''
b = replace_once(b, old_allowed, new_allowed, 'remove admin delivered authority')
old_before = '''    final before = snapshot.data()!;
    final update = <String, dynamic>{
'''
new_before = '''    final before = snapshot.data()!;
    final beforeStatus = (before['status'] ?? 'new').toString();
    const transitions = <String, Set<String>>{
      'new': <String>{'new', 'reviewing', 'needs_info', 'approved', 'rejected'},
      'reviewing': <String>{'reviewing', 'needs_info', 'approved', 'rejected'},
      'needs_info': <String>{'needs_info', 'reviewing', 'approved', 'rejected'},
      'approved': <String>{'approved', 'prize_sent', 'rejected'},
      'prize_sent': <String>{'prize_sent'},
      'delivered': <String>{},
      'rejected': <String>{'rejected', 'reviewing'},
    };
    if (!(transitions[beforeStatus] ?? const <String>{}).contains(status)) {
      throw StateError('invalid-prize-status-transition');
    }
    if (status == 'prize_sent' && prizeDetails.trim().isEmpty) {
      throw ArgumentError('prize-details-required');
    }
    final update = <String, dynamic>{
'''
b = replace_once(b, old_before, new_before, 'guard admin prize transitions')
b = b.replace(
    "      if (status == 'prize_sent') 'prizeSentAt': FieldValue.serverTimestamp(),\n      if (status == 'delivered') 'deliveredAt': FieldValue.serverTimestamp(),\n",
    "      if (status == 'prize_sent' && beforeStatus != 'prize_sent')\n        'prizeSentAt': FieldValue.serverTimestamp(),\n",
)
BACKEND.write_text(b, encoding='utf-8')


# ---------------------------------------------------------------------------
# prize_winner_pages.dart — winner confirmation, fixed LTR DEDA id, searchable
# admin list with stable serial numbers, protected status sequence, and single-
# line full reward code in winner details.
# ---------------------------------------------------------------------------
p = PRIZE.read_text(encoding='utf-8')
p = p.replace(
    "        'prize_sent' => t('تم إرسال الجائزة', 'Prize sent'),",
    "        'prize_sent' => t('بانتظار تأكيد استلامك', 'Waiting for your confirmation'),",
    1,
)
p = p.replace(
    "        'delivered' => t('تم تسليم الجائزة', 'Prize delivered'),",
    "        'delivered' => t('تم تأكيد استلام الجائزة', 'Prize receipt confirmed'),",
    1,
)

confirm_ui_anchor = '  Widget _infoTile(IconData icon, String title, String value) {'
confirm_ui = r'''  Future<void> _confirmPrizeReceived() async {
    if (_submitting) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(t('تأكيد استلام الجائزة', 'Confirm prize receipt')),
        content: Text(
          t(
            'هل تؤكد أنك استلمت جائزتك؟ بعد التأكيد ستُغلق دورة الجوائز الحالية ولن يمكن إعادة تأكيدها.',
            'Do you confirm that you received your prize? This will close the current prize cycle and cannot be repeated.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(t('إلغاء', 'Cancel')),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.verified_rounded),
            label: Text(t('نعم، تم الاستلام', 'Yes, I received it')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _submitting = true);
    try {
      await DedaBackend.confirmPrizeReceivedByUser(phone: widget.phone);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            t(
              'تم تأكيد استلام الجائزة وإغلاق دورة الجوائز الحالية.',
              'Prize receipt confirmed and the current prize cycle is closed.',
            ),
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            t(
              'تعذر تأكيد الاستلام الآن. تحقق من الإنترنت وحاول مرة أخرى.',
              'Could not confirm receipt. Check your connection and try again.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

'''
if '_confirmPrizeReceived()' not in p:
    p = replace_once(p, confirm_ui_anchor, confirm_ui + confirm_ui_anchor,
                     'insert winner receipt UI')

info_start = '  Widget _infoTile(IconData icon, String title, String value) {'
info_end = '  @override\n  Widget build(BuildContext context) {'
new_info = r'''  Widget _infoTile(
    IconData icon,
    String title,
    String value, {
    bool ltr = false,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5DEC5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF9A7415), size: 21),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF6B6658),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Directionality(
                  textDirection: ltr ? TextDirection.ltr : TextDirection.rtl,
                  child: SelectableText(
                    value.isEmpty ? '—' : value,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

'''
p = replace_between(p, info_start, info_end, new_info, 'replace info tile')
p = p.replace(
    "                  widget.dedaId,\n                ),",
    "                  widget.dedaId,\n                  ltr: true,\n                ),",
    1,
)

old_actions = r'''                if (status == 'needs_info') ...[
                  const SizedBox(height: 4),
                  FilledButton.icon(
                    onPressed: _replyToAdmin,
                    icon: const Icon(Icons.reply_rounded),
                    label: Text(t('الرد على الإدارة', 'Reply to administration')),
                  ),
                ],
                if (status == 'delivered') ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAF7EC),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFB7DDBD)),
                    ),
                    child: Text(
                      t(
                        '✅ تم تسليم الجائزة. تهانينا من فريق DEDA.',
                        '✅ Prize delivered. Congratulations from the DEDA team.',
                      ),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF17652F),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
'''
new_actions = r'''                if (status == 'needs_info') ...[
                  const SizedBox(height: 4),
                  FilledButton.icon(
                    onPressed: _replyToAdmin,
                    icon: const Icon(Icons.reply_rounded),
                    label: Text(t('الرد على الإدارة', 'Reply to administration')),
                  ),
                ],
                if (status == 'prize_sent') ...[
                  const SizedBox(height: 5),
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 9),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF7DB),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE2C865)),
                    ),
                    child: Text(
                      t(
                        'تحقق من تفاصيل جائزتك أعلاه. إذا استلمتها فعليًا اضغط الزر أدناه ثم أكد الاستلام.',
                        'Check your prize details above. If you actually received it, press the button below and confirm receipt.',
                      ),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _submitting ? null : _confirmPrizeReceived,
                    icon: _submitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.task_alt_rounded),
                    label: Text(t('✅ تم استلام الجائزة', '✅ I received the prize')),
                  ),
                ],
                if (status == 'delivered') ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAF7EC),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFB7DDBD)),
                    ),
                    child: Column(
                      children: [
                        const Icon(Icons.emoji_events_rounded,
                            color: Color(0xFF9A7415), size: 34),
                        const SizedBox(height: 7),
                        Text(
                          t(
                            '✅ تم تأكيد استلام جائزتك بنجاح',
                            '✅ Your prize receipt was confirmed',
                          ),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xFF17652F),
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          t(
                            'شكرًا لمشاركتك مع DEDA. انتظر الحدث القادم وشارك من جديد يا عزيزي 🌟',
                            'Thank you for joining DEDA. Wait for the next event and join again 🌟',
                          ),
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ),
                ],
'''
p = replace_once(p, old_actions, new_actions, 'replace winner status actions')

admin_list_start = 'class DedaAdminPrizeWinnersPage extends StatelessWidget {'
admin_list_end = 'class DedaAdminPrizeWinnerDetailPage extends StatefulWidget {'
new_admin_list = r'''class DedaAdminPrizeWinnersPage extends StatefulWidget {
  final bool isArabic;

  const DedaAdminPrizeWinnersPage({super.key, required this.isArabic});

  @override
  State<DedaAdminPrizeWinnersPage> createState() =>
      _DedaAdminPrizeWinnersPageState();
}

class _DedaAdminPrizeWinnersPageState extends State<DedaAdminPrizeWinnersPage> {
  final TextEditingController _search = TextEditingController();
  String _query = '';

  String t(String ar, String en) => widget.isArabic ? ar : en;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String _statusLabel(String status) => switch (status) {
        'new' => t('جديد', 'New'),
        'reviewing' => t('قيد التدقيق', 'Under review'),
        'needs_info' => t('نحتاج معلومات', 'Needs info'),
        'approved' => t('تم اعتماد الفوز', 'Approved'),
        'prize_sent' => t('بانتظار تأكيد الفائز', 'Awaiting winner confirmation'),
        'delivered' => t('تم التسليم بتأكيد الفائز', 'Confirmed delivered'),
        'rejected' => t('مرفوض', 'Rejected'),
        _ => status,
      };

  String _displayDedaId(String value) {
    final clean = value.trim().replaceAll('@', '');
    return clean.isEmpty ? '—' : '@$clean';
  }

  int _createdMillis(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final value = doc.data()['createdAt'];
    return value is Timestamp ? value.millisecondsSinceEpoch : 0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF2),
      appBar: AppBar(
        title: Text(t('🏆 الرابحون معنا', '🏆 Prize winners')),
        centerTitle: true,
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: DedaBackend.prizeWinnerRequestsForAdmin(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text(t('تعذر تحميل طلبات الفوز.', 'Could not load prize requests.')),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final allDocs = snapshot.data!.docs.toList();
          final byCreated = allDocs.toList()
            ..sort((a, b) => _createdMillis(a).compareTo(_createdMillis(b)));
          final serialById = <String, int>{
            for (var i = 0; i < byCreated.length; i++) byCreated[i].id: i + 1,
          };
          final q = _query.trim().toLowerCase();
          final docs = allDocs.where((doc) {
            if (q.isEmpty) return true;
            final d = doc.data();
            final serial = serialById[doc.id] ?? 0;
            final haystack = <String>[
              (d['name'] ?? '').toString(),
              (d['dedaId'] ?? '').toString(),
              (d['phone'] ?? '').toString(),
              (d['rewardCode'] ?? '').toString(),
              doc.id,
              _statusLabel((d['status'] ?? '').toString()),
              serial.toString(),
              '#${serial.toString().padLeft(3, '0')}',
            ].join(' ').toLowerCase();
            return haystack.contains(q);
          }).toList();

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
                child: TextField(
                  controller: _search,
                  onChanged: (value) => setState(() => _query = value),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: t('مسح البحث', 'Clear search'),
                            onPressed: () {
                              _search.clear();
                              setState(() => _query = '');
                            },
                            icon: const Icon(Icons.close_rounded),
                          ),
                    hintText: t(
                      'ابحث بالاسم أو المعرف أو الهاتف أو رقم الفائز',
                      'Search name, ID, phone, or winner number',
                    ),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: allDocs.isEmpty
                    ? Center(
                        child: Text(t('لا توجد طلبات فوز حاليًا.', 'No prize requests yet.')),
                      )
                    : docs.isEmpty
                        ? Center(
                            child: Text(t('لا توجد نتائج مطابقة.', 'No matching winners.')),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(14, 8, 14, 28),
                            itemCount: docs.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final doc = docs[index];
                              final data = doc.data();
                              final serial = serialById[doc.id] ?? 0;
                              final serialText =
                                  '#${serial.toString().padLeft(3, '0')}';
                              final name = (data['name'] ?? '—').toString();
                              final dedaId =
                                  _displayDedaId((data['dedaId'] ?? '').toString());
                              final code = (data['rewardCode'] ?? '—').toString();
                              final status = (data['status'] ?? 'new').toString();
                              return Material(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(19),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(19),
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => DedaAdminPrizeWinnerDetailPage(
                                        isArabic: widget.isArabic,
                                        requestId: doc.id,
                                        initialData: data,
                                        serialNumber: serial,
                                      ),
                                    ),
                                  ),
                                  child: Container(
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(19),
                                      border: Border.all(
                                        color: const Color(0xFFE5D5A5),
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                      children: [
                                        Row(
                                          children: [
                                            Container(
                                              width: 48,
                                              height: 48,
                                              decoration: const BoxDecoration(
                                                shape: BoxShape.circle,
                                                color: Color(0xFFFFF3C8),
                                              ),
                                              child: const Icon(
                                                Icons.emoji_events_rounded,
                                                color: Color(0xFF9A7415),
                                              ),
                                            ),
                                            const SizedBox(width: 11),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    name,
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      fontWeight: FontWeight.w900,
                                                      fontSize: 16,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 3),
                                                  Directionality(
                                                    textDirection: TextDirection.ltr,
                                                    child: Text(
                                                      dedaId,
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 3),
                                                  Directionality(
                                                    textDirection: TextDirection.ltr,
                                                    child: Text(
                                                      code,
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: const TextStyle(
                                                        color: Color(0xFF7A5A10),
                                                        fontWeight: FontWeight.w800,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Container(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 8,
                                                vertical: 6,
                                              ),
                                              decoration: BoxDecoration(
                                                color: status == 'new'
                                                    ? const Color(0xFFFFE5E2)
                                                    : const Color(0xFFEAF4EC),
                                                borderRadius: BorderRadius.circular(14),
                                              ),
                                              child: Text(
                                                _statusLabel(status),
                                                textAlign: TextAlign.center,
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w900,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 9),
                                        Align(
                                          alignment: AlignmentDirectional.centerEnd,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 9,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFF5F0E1),
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                            child: Directionality(
                                              textDirection: TextDirection.ltr,
                                              child: Text(
                                                '${t('رقم الفائز', 'Winner')} $serialText',
                                                style: const TextStyle(
                                                  color: Color(0xFF6F5715),
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w900,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
              ),
            ],
          );
        },
      ),
    );
  }
}

'''
p = replace_between(p, admin_list_start, admin_list_end, new_admin_list,
                    'replace admin winner list')

p = replace_once(
    p,
    '''  final String requestId;
  final Map<String, dynamic> initialData;
''',
    '''  final String requestId;
  final Map<String, dynamic> initialData;
  final int serialNumber;
''',
    'add winner serial field',
)
p = replace_once(
    p,
    '''    required this.requestId,
    required this.initialData,
  });
''',
    '''    required this.requestId,
    required this.initialData,
    required this.serialNumber,
  });
''',
    'add winner serial constructor',
)
p = replace_once(
    p,
    '''  late String _status;
  late final TextEditingController _message;
''',
    '''  late String _status;
  late String _savedStatus;
  late final TextEditingController _message;
''',
    'add saved admin status',
)
p = replace_once(
    p,
    "    _status = (widget.initialData['status'] ?? 'new').toString();\n",
    "    _status = (widget.initialData['status'] ?? 'new').toString();\n    _savedStatus = _status;\n",
    'initialize saved admin status',
)
p = p.replace(
    "        'prize_sent' => t('إرسال الجائزة', 'Prize sent'),",
    "        'prize_sent' => t('إرسال الجائزة / انتظار تأكيد الفائز', 'Send prize / await winner'),",
    1,
)
p = p.replace(
    "        'delivered' => t('تم تسليم الجائزة', 'Delivered'),",
    "        'delivered' => t('تم التسليم بتأكيد الفائز', 'Confirmed delivered'),",
    1,
)
p = replace_once(
    p,
    '''    if ((_status == 'prize_sent' || _status == 'delivered') &&
        _prize.text.trim().isEmpty) {
''',
    '''    if (_status == 'prize_sent' && _prize.text.trim().isEmpty) {
''',
    'admin prize details requirement',
)
p = replace_once(
    p,
    '''      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t('تم حفظ تحديث الفائز.', 'Winner updated.'))),
      );
''',
    '''      if (!mounted) return;
      setState(() => _savedStatus = _status);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t('تم حفظ تحديث الفائز.', 'Winner updated.'))),
      );
''',
    'persist local saved admin status',
)

data_start = '  Widget _dataRow(String label, dynamic value, {bool ltr = false}) {'
data_end = '  @override\n  Widget build(BuildContext context) {'
new_data_helpers = r'''  List<String> _statusChoices() {
    switch (_savedStatus) {
      case 'new':
        return const <String>['new', 'reviewing', 'needs_info', 'approved', 'rejected'];
      case 'reviewing':
        return const <String>['reviewing', 'needs_info', 'approved', 'rejected'];
      case 'needs_info':
        return const <String>['needs_info', 'reviewing', 'approved', 'rejected'];
      case 'approved':
        return const <String>['approved', 'prize_sent', 'rejected'];
      case 'prize_sent':
        return const <String>['prize_sent'];
      case 'delivered':
        return const <String>['delivered'];
      case 'rejected':
        return const <String>['rejected', 'reviewing'];
      default:
        return <String>[_status];
    }
  }

  String _timestampText(dynamic value) {
    if (value is! Timestamp) return '';
    final d = value.toDate().toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }

  Widget _dataRow(
    String label,
    dynamic value, {
    bool ltr = false,
    bool singleLine = false,
  }) {
    final text = (value ?? '').toString().trim();
    final shown = text.isEmpty ? '—' : text;
    final valueWidget = SelectableText(
      shown,
      maxLines: singleLine ? 1 : null,
      style: const TextStyle(fontWeight: FontWeight.w900),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 118,
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF6D746D),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Directionality(
              textDirection: ltr ? TextDirection.ltr : TextDirection.rtl,
              child: singleLine
                  ? FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: ltr
                          ? Alignment.centerLeft
                          : Alignment.centerRight,
                      child: valueWidget,
                    )
                  : valueWidget,
            ),
          ),
        ],
      ),
    );
  }

'''
p = replace_between(p, data_start, data_end, new_data_helpers,
                    'replace admin detail helpers')

p = replace_once(
    p,
    "                _dataRow(t('الاسم', 'Name'), d['name']),\n",
    "                _dataRow(t('الاسم', 'Name'), d['name']),\n"
    "                _dataRow(t('رقم الفائز', 'Winner number'),\n"
    "                    '#${widget.serialNumber.toString().padLeft(3, '0')}', ltr: true),\n",
    'show serial in winner details',
)
p = replace_once(
    p,
    "                _dataRow(t('الرمز الكامل', 'Full code'), d['rewardCode'], ltr: true),\n",
    "                _dataRow(t('الرمز الكامل', 'Full code'), d['rewardCode'],\n"
    "                    ltr: true, singleLine: true),\n",
    'keep reward code on one line',
)
p = replace_once(
    p,
    "                _dataRow(t('رد الفائز', 'Winner reply'), d['userReply']),\n",
    "                _dataRow(t('رد الفائز', 'Winner reply'), d['userReply']),\n"
    "                if (d['createdAt'] != null)\n"
    "                  _dataRow(t('تاريخ الفوز', 'Won at'),\n"
    "                      _timestampText(d['createdAt']), ltr: true),\n"
    "                if (d['prizeSentAt'] != null)\n"
    "                  _dataRow(t('إرسال الجائزة', 'Prize sent at'),\n"
    "                      _timestampText(d['prizeSentAt']), ltr: true),\n"
    "                if (d['winnerConfirmedAt'] != null)\n"
    "                  _dataRow(t('تأكيد الفائز', 'Winner confirmed at'),\n"
    "                      _timestampText(d['winnerConfirmedAt']), ltr: true),\n",
    'show prize timeline',
)

drop_start = '          DropdownButtonFormField<String>(\n'
drop_end = '          const SizedBox(height: 12),\n'
new_dropdown = r'''          DropdownButtonFormField<String>(
            value: _status,
            decoration: InputDecoration(
              labelText: t('حالة الطلب', 'Request status'),
              border: const OutlineInputBorder(),
            ),
            items: _statusChoices()
                .map(
                  (value) => DropdownMenuItem<String>(
                    value: value,
                    child: Text(_label(value)),
                  ),
                )
                .toList(),
            onChanged: _savedStatus == 'delivered' || _savedStatus == 'prize_sent'
                ? null
                : (value) {
                    if (value != null) setState(() => _status = value);
                  },
          ),
          if (_savedStatus == 'prize_sent') ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7DB),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE2C865)),
              ),
              child: Text(
                t(
                  'تم إرسال الجائزة. الحالة الآن بانتظار أن يضغط الفائز «تم استلام الجائزة» ويؤكد الاستلام بنفسه.',
                  'Prize sent. Waiting for the winner to confirm receipt.',
                ),
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
          if (_savedStatus == 'delivered') ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFEAF7EC),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFB7DDBD)),
              ),
              child: Text(
                t(
                  '✅ الفائز أكد استلام الجائزة. أُغلقت دورة الجوائز لهذا الطلب.',
                  '✅ The winner confirmed receipt. This prize cycle is closed.',
                ),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF17652F),
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
'''
p = replace_between(p, drop_start, drop_end, new_dropdown,
                    'replace admin status dropdown')
p = p.replace(
    '            onPressed: _saving ? null : _save,',
    "            onPressed: _saving || _savedStatus == 'delivered' ? null : _save,",
    1,
)
PRIZE.write_text(p, encoding='utf-8')


# ---------------------------------------------------------------------------
# firestore.rules — admin may send but cannot self-declare delivery; winner is
# allowed to move prize_sent -> delivered exactly once with server timestamps.
# ---------------------------------------------------------------------------
r = RULES.read_text(encoding='utf-8')
rs = r.find('    match /prize_winner_requests/{requestId} {')
re = r.find('    match /support_requests/{requestId} {', rs)
if rs < 0 or re < 0:
    raise SystemExit('prize rules block not found')
block = r[rs:re]
if "request.resource.data.cycleId == 'prize_v1'" not in block:
    block = block.replace(
        "        && request.resource.data.accountKey is string\n",
        "        && request.resource.data.accountKey is string\n"
        "        && request.resource.data.cycleId == 'prize_v1'\n",
        1,
    )
    block = block.replace(
        "          'ownerUid', 'accountKey', 'name', 'phone', 'dedaId',\n",
        "          'ownerUid', 'cycleId', 'accountKey', 'name', 'phone', 'dedaId',\n",
        1,
    )
block = block.replace(
    "            'new', 'reviewing', 'needs_info', 'approved',\n            'prize_sent', 'delivered', 'rejected'\n",
    "            'new', 'reviewing', 'needs_info', 'approved',\n            'prize_sent', 'rejected'\n",
    1,
)
block = block.replace(
    "            'adminUpdatedAt', 'updatedAt', 'prizeSentAt', 'deliveredAt'\n",
    "            'adminUpdatedAt', 'updatedAt', 'prizeSentAt'\n",
    1,
)
if "request.resource.data.status != 'prize_sent'" not in block:
    block = block.replace(
        "          && request.resource.data.adminByUid == request.auth.uid\n",
        "          && (\n"
        "            request.resource.data.status != 'prize_sent'\n"
        "            || (\n"
        "              request.resource.data.prizeDetails is string\n"
        "              && request.resource.data.prizeDetails.size() > 0\n"
        "            )\n"
        "          )\n"
        "          && request.resource.data.adminByUid == request.auth.uid\n",
        1,
    )
confirm_rule = r'''        )
        || (
          signedIn()
          && resource.data.status == 'prize_sent'
          && (
            resource.data.ownerUid == request.auth.uid
            || sameAccount(resource.data.accountKey)
          )
          && request.resource.data.status == 'delivered'
          && request.resource.data.winnerConfirmedAt == request.time
          && request.resource.data.deliveredAt == request.time
          && request.resource.data.updatedAt == request.time
          && request.resource.data.diff(resource.data).affectedKeys().hasOnly([
            'status', 'winnerConfirmedAt', 'deliveredAt', 'updatedAt'
          ])
        );
'''
if 'winnerConfirmedAt' not in block:
    old_end = r'''        );

      allow delete: if false;
'''
    new_end = confirm_rule + r'''
      allow delete: if false;
'''
    if block.count(old_end) != 1:
        raise SystemExit('prize rules update tail not uniquely found')
    block = block.replace(old_end, new_end, 1)
r = r[:rs] + block + r[re:]
RULES.write_text(r, encoding='utf-8')


# ---------------------------------------------------------------------------
# CI — this single work branch builds once after the patch commit; Firestore
# deploys from the same branch. The additional validator protects every agreed
# behavior before APK/AAB generation.
# ---------------------------------------------------------------------------
y = BUILD.read_text(encoding='utf-8')
if '      - prize-cycle-complete-2026-10-01\n' not in y:
    y = replace_once(
        y,
        '      - prize-winners-flow-2026-10-01\n',
        '      - prize-winners-flow-2026-10-01\n'
        '      - prize-cycle-complete-2026-10-01\n',
        'add complete cycle build branch',
    )
if 'validate_prize_cycle_complete_2026_10_01.py' not in y:
    y = replace_once(
        y,
        '      - name: Build permanently signed APK and AAB\n',
        '      - name: Validate complete DEDA prize cycle\n'
        '        run: python3 tools/validate_prize_cycle_complete_2026_10_01.py\n\n'
        '      - name: Build permanently signed APK and AAB\n',
        'add complete cycle validator step',
    )
BUILD.write_text(y, encoding='utf-8')

d = DEPLOY.read_text(encoding='utf-8')
if '      - prize-cycle-complete-2026-10-01\n' not in d:
    d = replace_once(
        d,
        '      - prize-winners-flow-2026-10-01\n',
        '      - prize-winners-flow-2026-10-01\n'
        '      - prize-cycle-complete-2026-10-01\n',
        'add complete cycle deploy branch',
    )
d = d.replace(
    '          ref: prize-winners-flow-2026-10-01\n',
    '          ref: ${{ github.ref_name }}\n',
)
DEPLOY.write_text(d, encoding='utf-8')


VALIDATOR.write_text(r'''from pathlib import Path

main = Path('lib/main.dart').read_text(encoding='utf-8')
backend = Path('lib/deda_backend.dart').read_text(encoding='utf-8')
prize = Path('lib/prize_winner_pages.dart').read_text(encoding='utf-8')
rules = Path('firestore.rules').read_text(encoding='utf-8')
build = Path('.github/workflows/build.yml').read_text(encoding='utf-8')
deploy = Path('.github/workflows/deploy-prize-winners-firestore.yml').read_text(encoding='utf-8')

# Final points card remains terminal and now reacts to winner-confirmed delivery.
assert "status == 'delivered'" in main
assert 'انتظر الحدث القادم وشارك من جديد يا عزيزي' in main
assert 'اكتملت الدورة • البطاقات مغلقة • انتظر الحدث القادم' in main
assert 'متابعة طلب الجائزة مع الإدارة' in main
assert "if (threshold == _pointTierThresholds.last) return;" in main

# Backend: explicit cycle, admin sends, winner confirms.
assert "prizeWinnerCycleId = 'prize_v1'" in backend
assert 'confirmPrizeReceivedByUser' in backend
assert "'winnerConfirmedAt': FieldValue.serverTimestamp()" in backend
assert "'deliveredAt': FieldValue.serverTimestamp()" in backend
assert "'delivered',\n      'rejected'" not in backend
assert 'invalid-prize-status-transition' in backend
assert "'prize_sent': <String>{'prize_sent'}" in backend

# User UI: two-step receipt confirmation and closing message.
assert '✅ تم استلام الجائزة' in prize
assert 'هل تؤكد أنك استلمت جائزتك؟' in prize
assert 'نعم، تم الاستلام' in prize
assert 'تم تأكيد استلام جائزتك بنجاح' in prize
assert 'انتظر الحدث القادم وشارك من جديد يا عزيزي' in prize

# Admin UI: search + stable serials + same request history.
assert 'class _DedaAdminPrizeWinnersPageState' in prize
assert 'ابحث بالاسم أو المعرف أو الهاتف أو رقم الفائز' in prize
assert "padLeft(3, '0')" in prize
assert "t('رقم الفائز', 'Winner number')" in prize
assert '_savedStatus' in prize
assert 'بانتظار تأكيد الفائز' in prize
assert 'singleLine: true' in prize
assert 'winnerConfirmedAt' in prize

# Security: only winner/account can mark a sent prize delivered; no deletes.
assert "request.resource.data.cycleId == 'prize_v1'" in rules
assert "resource.data.status == 'prize_sent'" in rules
assert "request.resource.data.status == 'delivered'" in rules
assert 'request.resource.data.winnerConfirmedAt == request.time' in rules
assert "'status', 'winnerConfirmedAt', 'deliveredAt', 'updatedAt'" in rules
assert 'allow delete: if false;' in rules

# One test branch runs both protected validation and deployment.
assert '      - prize-cycle-complete-2026-10-01' in build
assert 'validate_prize_cycle_complete_2026_10_01.py' in build
assert '      - prize-cycle-complete-2026-10-01' in deploy
assert 'ref: ${{ github.ref_name }}' in deploy

print('complete prize cycle invariants validated')
''', encoding='utf-8')

print('complete prize cycle patch applied')
