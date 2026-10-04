from pathlib import Path

path = Path('lib/main.dart')
text = path.read_text(encoding='utf-8')
marker = '// DEDA_GIFTS_MAIN_UI_100271'
if marker in text:
    print('100271 gifts main UI already applied')
    raise SystemExit(0)

# Timestamp is used only for human-readable gift dates in the inbox.
firestore_import = "import 'package:cloud_firestore/cloud_firestore.dart';\n"
if firestore_import not in text:
    firebase_anchor = "import 'package:firebase_core/firebase_core.dart';\n"
    if text.count(firebase_anchor) != 1:
        raise SystemExit('firebase_core import anchor missing')
    text = text.replace(firebase_anchor, firebase_anchor + firestore_import, 1)

# ---------------------------------------------------------------------------
# 1) General-manager PERSONAL test wallet. This remains separate from both
#    local rewarded-ad diamonds and server gift diamonds.
# ---------------------------------------------------------------------------
wallet_state = '''  static int _localBalance = 0;
  static int _giftedBalance = 0;

  static int get giftedBalance => _giftedBalance;
  static int get effectiveBalance => _localBalance + _giftedBalance;
'''
wallet_state_new = '''  static int _localBalance = 0;
  static int _giftedBalance = 0;
  static int _generalManagerPersonalBalance = 0;
  static bool _hasGeneralManagerPersonalWallet = false;
  static final ValueNotifier<int> generalManagerPersonalNotifier =
      ValueNotifier<int>(0);

  static int get giftedBalance => _giftedBalance;
  static int get effectiveBalance => _localBalance + _giftedBalance;
  static bool get hasGeneralManagerPersonalWallet =>
      _hasGeneralManagerPersonalWallet;
  static int get generalManagerPersonalBalance =>
      _generalManagerPersonalBalance;
  static int get purchasableBalance => _hasGeneralManagerPersonalWallet
      ? _generalManagerPersonalBalance
      : effectiveBalance;
'''
if text.count(wallet_state) != 1:
    raise SystemExit(f'100270 wallet state anchor count={text.count(wallet_state)}')
text = text.replace(wallet_state, wallet_state_new, 1)

load_balance_anchor = '''    balanceNotifier.value = effectiveBalance;
    return DedaDiamondsState(
'''
load_balance_new = '''    // A protected personal one-million test wallet is available only to an
    // authorized general-manager DEDA gateway account. Permission denied for
    // ordinary users is interpreted as "not a manager personal account".
    try {
      final gmPersonal =
          await DedaBackend.ensureGeneralManagerPersonalDiamondWallet(
        phone: DedaPreferences.phone,
      );
      _hasGeneralManagerPersonalWallet = gmPersonal != null;
      _generalManagerPersonalBalance = gmPersonal ?? 0;
    } catch (_) {
      _hasGeneralManagerPersonalWallet = false;
      _generalManagerPersonalBalance = 0;
    }
    generalManagerPersonalNotifier.value = _generalManagerPersonalBalance;
    balanceNotifier.value = effectiveBalance;
    return DedaDiamondsState(
'''
if text.count(load_balance_anchor) != 1:
    raise SystemExit(f'wallet load balance anchor count={text.count(load_balance_anchor)}')
text = text.replace(load_balance_anchor, load_balance_new, 1)

spend_anchor = '''    final prefs = await SharedPreferences.getInstance();
    final current = await load();
    final available = current.balance + _giftedBalance;
    if (available < amount) return false;
'''
spend_new = '''    final prefs = await SharedPreferences.getInstance();
    final current = await load();

    // On the general manager's personal DEDA account, style purchases spend
    // only the separate personal testing million. The administrative gift pool
    // is never consulted here.
    if (_hasGeneralManagerPersonalWallet) {
      if (_generalManagerPersonalBalance < amount) return false;
      try {
        _generalManagerPersonalBalance =
            await DedaBackend.spendGeneralManagerPersonalDiamonds(
          phone: DedaPreferences.phone,
          amount: amount,
        );
        generalManagerPersonalNotifier.value =
            _generalManagerPersonalBalance;
        return true;
      } catch (_) {
        return false;
      }
    }

    final available = current.balance + _giftedBalance;
    if (available < amount) return false;
'''
if text.count(spend_anchor) != 1:
    raise SystemExit(f'100270 spend anchor count={text.count(spend_anchor)}')
text = text.replace(spend_anchor, spend_new, 1)

style_balance = '      _diamonds = DedaDiamondsWallet.balanceNotifier.value;\n'
if text.count(style_balance) != 1:
    raise SystemExit(f'style balance anchor count={text.count(style_balance)}')
text = text.replace(
    style_balance,
    '      _diamonds = DedaDiamondsWallet.purchasableBalance;\n',
    1,
)

profile_hero = '  Widget _profileHero(DedaAccountType type) {\n'
if text.count(profile_hero) != 1:
    raise SystemExit(f'profile hero anchor count={text.count(profile_hero)}')
gm_card = r'''  Widget _generalManagerPersonalDiamondsCard(int diamonds) {
    if (diamonds <= 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        constraints: const BoxConstraints(minHeight: 76),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: <Color>[Color(0xFF172B55), Color(0xFF36245D)],
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE0BD57), width: 1.2),
        ),
        child: Row(
          children: <Widget>[
            const CircleAvatar(
              radius: 23,
              backgroundColor: Color(0xFFFFE9A8),
              child: Icon(Icons.workspace_premium_rounded,
                  color: Color(0xFF8D6200), size: 25),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    dedaText('رصيد المدير العام الشخصي',
                        'General manager personal balance'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 14.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    dedaText('للتجربة وفتح الإطارات والشارات',
                        'For testing frames and badges'),
                    style: const TextStyle(
                      color: Color(0xFFE6DDF1),
                      fontWeight: FontWeight.w600,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Directionality(
              textDirection: TextDirection.ltr,
              child: Text(
                '$diamonds 💎',
                style: const TextStyle(
                  color: Color(0xFFFFD86A),
                  fontWeight: FontWeight.w900,
                  fontSize: 17,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

'''
text = text.replace(profile_hero, gm_card + profile_hero, 1)

favorites_anchor = '''            _sectionCard(
              icon: Icons.favorite_rounded,
'''
if text.count(favorites_anchor) != 1:
    raise SystemExit(f'favorites section anchor count={text.count(favorites_anchor)}')
gm_profile_builder = '''            ValueListenableBuilder<int>(
              valueListenable:
                  DedaDiamondsWallet.generalManagerPersonalNotifier,
              builder: (context, diamonds, _) =>
                  _generalManagerPersonalDiamondsCard(diamonds),
            ),
'''
text = text.replace(favorites_anchor, gm_profile_builder + favorites_anchor, 1)

# ---------------------------------------------------------------------------
# 2) Friend overflow menu: never remove directly from the three dots.
# ---------------------------------------------------------------------------
friend_more = '''              IconButton(
                tooltip: dedaText('إزالة الصديق', 'Remove friend'),
                onPressed: onRemove,
                icon: const Icon(Icons.more_vert_rounded, color: Color(0xFF607487)),
              ),'''
friend_menu = '''              PopupMenuButton<String>(
                tooltip: dedaText('خيارات الصديق', 'Friend options'),
                icon: const Icon(
                  Icons.more_vert_rounded,
                  color: Color(0xFF607487),
                ),
                onSelected: (value) {
                  if (value == 'remove') onRemove();
                },
                itemBuilder: (context) => <PopupMenuEntry<String>>[
                  PopupMenuItem<String>(
                    value: 'remove',
                    child: Row(
                      children: <Widget>[
                        const Icon(Icons.person_remove_alt_1_rounded,
                            color: Color(0xFFB42318), size: 20),
                        const SizedBox(width: 9),
                        Text(dedaText('إزالة الصديق', 'Remove friend')),
                      ],
                    ),
                  ),
                  PopupMenuItem<String>(
                    value: 'gift_future',
                    enabled: false,
                    child: Row(
                      children: <Widget>[
                        const Icon(Icons.card_giftcard_rounded,
                            color: Color(0xFF8B6A17), size: 20),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text(dedaText(
                              'إرسال هدية • قريبًا', 'Send gift • Coming soon')),
                        ),
                      ],
                    ),
                  ),
                ],
              ),'''
if text.count(friend_more) != 1:
    raise SystemExit(f'friend direct-remove button count={text.count(friend_more)}')
text = text.replace(friend_more, friend_menu, 1)

# ---------------------------------------------------------------------------
# 3) The MAIN app "طلباتي" entry becomes "هداياي". Friendship requests in
#    the social hub are intentionally untouched.
# ---------------------------------------------------------------------------
old_bottom = '''              premiumBottomItem(
                index: 3,
                icon: Icons.assignment_outlined,
                selectedIcon: Icons.assignment,
                label: dedaText('طلباتي', 'Requests'),
                selected: false,
              ),'''
new_bottom = '''              DedaGiftNavBadge(
                child: premiumBottomItem(
                  index: 3,
                  icon: Icons.card_giftcard_outlined,
                  selectedIcon: Icons.card_giftcard_rounded,
                  label: dedaText('هداياي', 'My gifts'),
                  selected: false,
                ),
              ),'''
if text.count(old_bottom) != 1:
    raise SystemExit(f'main Requests bottom item count={text.count(old_bottom)}')
text = text.replace(old_bottom, new_bottom, 1)

old_route = '            MaterialPageRoute(builder: (_) => const DedaMyRequestsPage()),\n'
if text.count(old_route) != 1:
    raise SystemExit(f'main request route count={text.count(old_route)}')
text = text.replace(
    old_route,
    '            MaterialPageRoute(builder: (_) => const DedaMyGiftsPage()),\n',
    1,
)

# ---------------------------------------------------------------------------
# 4) Gift notification state, red pending badge, permanent inbox/history.
# ---------------------------------------------------------------------------
addition = r'''

// DEDA_GIFTS_MAIN_UI_100271
class DedaGiftInbox {
  static final ValueNotifier<int> pendingNotifier = ValueNotifier<int>(0);
  static StreamSubscription<List<Map<String, dynamic>>>? _subscription;
  static String _publicId = '';

  static Future<void> start() async {
    final publicId =
        DedaBackend.personalShareIdForPhone(DedaPreferences.phone).trim();
    if (publicId.isEmpty) {
      await _subscription?.cancel();
      _subscription = null;
      _publicId = '';
      pendingNotifier.value = 0;
      return;
    }
    if (_subscription != null && _publicId == publicId) return;
    await _subscription?.cancel();
    _subscription = null;
    _publicId = publicId;
    pendingNotifier.value = 0;
    _subscription = DedaBackend.watchPersonalDiamondGifts(publicId).listen(
      (gifts) {
        pendingNotifier.value = gifts
            .where((gift) => (gift['status'] ?? '').toString() == 'pending')
            .length;
      },
      onError: (_) {
        // Preserve the last known count on temporary connection failures.
      },
    );
  }
}

class DedaGiftNavBadge extends StatefulWidget {
  final Widget child;
  const DedaGiftNavBadge({super.key, required this.child});

  @override
  State<DedaGiftNavBadge> createState() => _DedaGiftNavBadgeState();
}

class _DedaGiftNavBadgeState extends State<DedaGiftNavBadge> {
  @override
  void initState() {
    super.initState();
    unawaited(DedaGiftInbox.start());
  }

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: ValueListenableBuilder<int>(
        valueListenable: DedaGiftInbox.pendingNotifier,
        builder: (context, pending, _) => Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            SizedBox.expand(child: widget.child),
            if (pending > 0)
              PositionedDirectional(
                top: 1,
                end: 5,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 19, minHeight: 19),
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD92D20),
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  child: Text(
                    pending > 99 ? '99+' : '$pending',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      height: 1,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class DedaMyGiftsPage extends StatefulWidget {
  const DedaMyGiftsPage({super.key});

  @override
  State<DedaMyGiftsPage> createState() => _DedaMyGiftsPageState();
}

class _DedaMyGiftsPageState extends State<DedaMyGiftsPage> {
  final Set<String> _claiming = <String>{};
  late final String _publicId;

  @override
  void initState() {
    super.initState();
    _publicId =
        DedaBackend.personalShareIdForPhone(DedaPreferences.phone).trim();
    unawaited(DedaGiftInbox.start());
  }

  String _giftTime(dynamic raw) {
    DateTime? value;
    if (raw is Timestamp) value = raw.toDate().toLocal();
    if (value == null) return dedaText('الوقت غير متاح', 'Time unavailable');
    String two(int n) => n.toString().padLeft(2, '0');
    return '${value.year}/${two(value.month)}/${two(value.day)} '
        '${two(value.hour)}:${two(value.minute)}';
  }

  Future<void> _claim(Map<String, dynamic> gift) async {
    final giftId = (gift['giftId'] ?? '').toString().trim();
    if (giftId.isEmpty || _claiming.contains(giftId)) return;
    setState(() => _claiming.add(giftId));
    try {
      final result = await DedaBackend.claimDiamondGift(
        giftId: giftId,
        targetPublicId: _publicId,
      );
      await DedaDiamondsWallet.load();
      if (!mounted) return;
      final amount = ((result['amount'] as num?)?.toInt() ?? 0);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            dedaText('تم استلام $amount 💎 وإضافتها إلى رصيدك.',
                '$amount 💎 received and added to your balance.'),
            textAlign: TextAlign.center,
          ),
        ),
      );
    } on StateError catch (error) {
      if (!mounted) return;
      final already = error.message == 'diamond-gift-already-claimed';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            already
                ? dedaText('هذه الهدية مستلمة مسبقًا.',
                    'This gift was already received.')
                : dedaText('تعذر استلام الهدية الآن.',
                    'Could not receive the gift right now.'),
            textAlign: TextAlign.center,
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            dedaText('تعذر استلام الهدية. تحقق من الإنترنت وحاول مجددًا.',
                'Could not receive the gift. Check your connection and retry.'),
            textAlign: TextAlign.center,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _claiming.remove(giftId));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF2),
      appBar: AppBar(
        centerTitle: true,
        title: Text(
          dedaText('هداياي', 'My gifts'),
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: _publicId.isEmpty
          ? Center(
              child: Text(dedaText('تعذر تجهيز معرف حسابك الآن.',
                  'Could not prepare your account ID right now.')),
            )
          : StreamBuilder<List<Map<String, dynamic>>>(
              stream: DedaBackend.watchPersonalDiamondGifts(_publicId),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError && !snapshot.hasData) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        dedaText('تعذر تحميل الهدايا الآن.',
                            'Could not load gifts right now.'),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                final gifts = snapshot.data ?? const <Map<String, dynamic>>[];
                if (gifts.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Container(
                        width: double.infinity,
                        constraints: const BoxConstraints(maxWidth: 520),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 22, vertical: 30),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: const Color(0xFFDCE5DD)),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            const Icon(Icons.card_giftcard_rounded,
                                color: Color(0xFF7B4BC4), size: 52),
                            const SizedBox(height: 12),
                            Text(
                              dedaText('ما عندك هدايا حاليًا',
                                  'You do not have gifts yet'),
                              style: const TextStyle(
                                color: Color(0xFF183B56),
                                fontWeight: FontWeight.w900,
                                fontSize: 19,
                              ),
                            ),
                            const SizedBox(height: 7),
                            Text(
                              dedaText(
                                  'هدايا إدارة DEDA ستظهر هنا، وهدايا الأصدقاء تستخدم نفس الصفحة مستقبلًا.',
                                  'DEDA administration gifts will appear here. Friend gifts will use this same page later.'),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Color(0xFF667A6D),
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }
                return ListView(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 22),
                  children: <Widget>[
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 13, vertical: 11),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: <Color>[
                            Color(0xFFEFE7FF),
                            Color(0xFFFFF9E8),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFFD8C6F1)),
                      ),
                      child: Row(
                        children: <Widget>[
                          const Icon(Icons.redeem_rounded,
                              color: Color(0xFF6D3CC7), size: 30),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              dedaText(
                                  'الهدايا غير المستلمة تبقى بانتظارك، وبعد الاستلام تبقى هنا كسجل دائم.',
                                  'Unreceived gifts stay pending. Received gifts remain here as permanent history.'),
                              style: const TextStyle(
                                color: Color(0xFF4A3766),
                                fontWeight: FontWeight.w700,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    ...gifts.map(_giftCard),
                  ],
                );
              },
            ),
    );
  }

  Widget _giftCard(Map<String, dynamic> gift) {
    final giftId = (gift['giftId'] ?? '').toString();
    final pending = (gift['status'] ?? '').toString() == 'pending';
    final amount = ((gift['amount'] as num?)?.toInt() ?? 0);
    final sender = (gift['senderLabel'] ?? 'إدارة DEDA').toString();
    final reason = (gift['reason'] ?? '').toString().trim();
    final busy = _claiming.contains(giftId);
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: pending ? const Color(0xFFD6C1F1) : const Color(0xFFCFE5D5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              CircleAvatar(
                radius: 23,
                backgroundColor:
                    pending ? const Color(0xFFF0E8FF) : const Color(0xFFE7F6EC),
                child: Icon(
                  pending ? Icons.card_giftcard_rounded : Icons.check_rounded,
                  color: pending
                      ? const Color(0xFF6D3CC7)
                      : const Color(0xFF16794A),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Text(
                      sender,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF173A55),
                        fontWeight: FontWeight.w900,
                        fontSize: 15.5,
                      ),
                    ),
                    Text(
                      _giftTime(gift['createdAt']),
                      style: const TextStyle(
                        color: Color(0xFF75838D),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Directionality(
                textDirection: TextDirection.ltr,
                child: Text(
                  '$amount 💎',
                  style: const TextStyle(
                    color: Color(0xFF6D3CC7),
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          if (reason.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF7F8F5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                reason,
                style: const TextStyle(
                  color: Color(0xFF4F6156),
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                ),
              ),
            ),
          const SizedBox(height: 9),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  pending
                      ? dedaText('الحالة: بانتظار الاستلام',
                          'Status: waiting to receive')
                      : dedaText('الحالة: تم الاستلام', 'Status: received'),
                  style: TextStyle(
                    color: pending
                        ? const Color(0xFF8A5B00)
                        : const Color(0xFF16794A),
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5,
                  ),
                ),
              ),
              if (pending)
                FilledButton.icon(
                  onPressed: busy ? null : () => _claim(gift),
                  icon: busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.download_done_rounded, size: 19),
                  label: Text(dedaText('استلام', 'Receive')),
                ),
            ],
          ),
          if (!pending && gift['claimedAt'] != null) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              dedaText('تم الاستلام: ${_giftTime(gift['claimedAt'])}',
                  'Received: ${_giftTime(gift['claimedAt'])}'),
              style: const TextStyle(
                color: Color(0xFF7B8780),
                fontSize: 11,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
'''

text = text.rstrip() + addition + '\n'
path.write_text(text, encoding='utf-8')
print('applied DEDA 100271 gifts inbox + friend menu + GM personal wallet UI')
