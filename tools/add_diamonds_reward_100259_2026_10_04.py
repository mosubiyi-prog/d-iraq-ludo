from pathlib import Path

path = Path('lib/main.dart')
text = path.read_text(encoding='utf-8')

wallet_marker = "class DedaAccountHubPage extends StatefulWidget {\n"
if text.count(wallet_marker) != 1:
    raise SystemExit('Expected exactly one DedaAccountHubPage marker')

wallet_code = r'''class DedaDiamondsState {
  final int balance;
  final int viewsToday;
  final String dayKey;

  const DedaDiamondsState({
    required this.balance,
    required this.viewsToday,
    required this.dayKey,
  });
}

class DedaDiamondsClaimResult {
  final bool awarded;
  final int balance;
  final int viewsToday;

  const DedaDiamondsClaimResult({
    required this.awarded,
    required this.balance,
    required this.viewsToday,
  });
}

class DedaDiamondsWallet {
  static const int rewardPerAd = 3;
  static const int maxAdsPerDay = 5;
  static final ValueNotifier<int> balanceNotifier = ValueNotifier<int>(0);

  static String _accountScope() {
    final accountKey =
        DedaBackend.accountKeyForPhone(DedaPreferences.phone).trim();
    if (accountKey.isNotEmpty) return accountKey;
    final phone = DedaPreferences.phone.trim();
    return phone.isEmpty ? 'unknown' : phone;
  }

  static String _prefsKey() => 'deda_diamonds_wallet_v1_${_accountScope()}';

  static String _todayKey() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  static Future<DedaDiamondsState> load() async {
    final prefs = await SharedPreferences.getInstance();
    final today = _todayKey();
    final raw = prefs.getString(_prefsKey());

    var balance = 0;
    var viewsToday = 0;
    var storedDay = today;

    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          balance =
              ((decoded['balance'] as num?)?.toInt() ?? 0).clamp(0, 1 << 30);
          storedDay = (decoded['day'] ?? today).toString();
          viewsToday = ((decoded['viewsToday'] as num?)?.toInt() ?? 0)
              .clamp(0, maxAdsPerDay);
        }
      } catch (_) {
        balance = 0;
        viewsToday = 0;
        storedDay = today;
      }
    }

    if (storedDay != today) {
      viewsToday = 0;
      storedDay = today;
      await _write(
        prefs,
        balance: balance,
        viewsToday: viewsToday,
        dayKey: storedDay,
      );
    }

    balanceNotifier.value = balance;
    return DedaDiamondsState(
      balance: balance,
      viewsToday: viewsToday,
      dayKey: storedDay,
    );
  }

  static Future<DedaDiamondsClaimResult> claimReward() async {
    final prefs = await SharedPreferences.getInstance();
    final current = await load();
    if (current.viewsToday >= maxAdsPerDay) {
      return DedaDiamondsClaimResult(
        awarded: false,
        balance: current.balance,
        viewsToday: current.viewsToday,
      );
    }

    final newBalance = current.balance + rewardPerAd;
    final newViews = current.viewsToday + 1;
    await _write(
      prefs,
      balance: newBalance,
      viewsToday: newViews,
      dayKey: _todayKey(),
    );
    balanceNotifier.value = newBalance;
    return DedaDiamondsClaimResult(
      awarded: true,
      balance: newBalance,
      viewsToday: newViews,
    );
  }

  static Future<void> _write(
    SharedPreferences prefs, {
    required int balance,
    required int viewsToday,
    required String dayKey,
  }) async {
    await prefs.setString(
      _prefsKey(),
      jsonEncode(<String, dynamic>{
        'balance': balance,
        'viewsToday': viewsToday,
        'day': dayKey,
      }),
    );
  }
}

'''
text = text.replace(wallet_marker, wallet_code + wallet_marker, 1)

profile_init_marker = '''  @override
  void initState() {
    super.initState();
    _loadOpenedPointTiers();
  }
'''
profile_init_replacement = '''  @override
  void initState() {
    super.initState();
    _loadOpenedPointTiers();
    unawaited(DedaDiamondsWallet.load());
  }
'''
if text.count(profile_init_marker) != 1:
    raise SystemExit('Expected exactly one profile init marker')
text = text.replace(profile_init_marker, profile_init_replacement, 1)

profile_hero_marker = "  Widget _profileHero(DedaAccountType type) {\n"
if text.count(profile_hero_marker) != 1:
    raise SystemExit('Expected exactly one profile hero marker')

profile_card_code = r'''  Widget _diamondsBalanceCard(int diamonds) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        constraints: const BoxConstraints(minHeight: 88),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [
              Color(0xFF6F3FA3),
              Color(0xFF4D2778),
              Color(0xFF3A1B62),
            ],
            begin: AlignmentDirectional.topStart,
            end: AlignmentDirectional.bottomEnd,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: const Color(0xFFC7A5E8),
            width: 1.2,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x334C2475),
              blurRadius: 13,
              offset: Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [
                    Color(0xFFE5D3F8),
                    Color(0xFFB98CE4),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(15),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x448E56C5),
                    blurRadius: 9,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
              child: const Stack(
                clipBehavior: Clip.none,
                children: [
                  Center(
                    child: Icon(
                      Icons.diamond_rounded,
                      color: Color(0xFF7141A5),
                      size: 29,
                    ),
                  ),
                  Positioned(
                    top: 5,
                    right: 6,
                    child: Icon(
                      Icons.auto_awesome_rounded,
                      color: Colors.white,
                      size: 11,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    dedaText('الماسات', 'Diamonds'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    dedaText('الرصيد الحالي', 'Current balance'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFE4D6F2),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              constraints: const BoxConstraints(maxWidth: 118),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFFE8D6F8),
                borderRadius: BorderRadius.circular(17),
                border: Border.all(
                  color: const Color(0xFFF2E7FC),
                ),
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  dedaText('💎 $diamonds ماسة', '💎 $diamonds diamonds'),
                  maxLines: 1,
                  style: const TextStyle(
                    color: Color(0xFF55277F),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 5),
            const Icon(
              Icons.chevron_left_rounded,
              color: Color(0xFFDCC5F0),
              size: 24,
            ),
          ],
        ),
      ),
    );
  }

'''
text = text.replace(profile_hero_marker, profile_card_code + profile_hero_marker, 1)

favorites_marker = '''            _sectionCard(
              icon: Icons.favorite_rounded,
'''
if text.count(favorites_marker) != 1:
    raise SystemExit('Expected exactly one favorites card marker')
profile_diamonds_insert = '''            ValueListenableBuilder<int>(
              valueListenable: DedaDiamondsWallet.balanceNotifier,
              builder: (context, diamonds, _) =>
                  _diamondsBalanceCard(diamonds),
            ),
'''
text = text.replace(favorites_marker, profile_diamonds_insert + favorites_marker, 1)

rewarded_state_marker = "  DateTime? _rewardedAdNextAutomaticAttemptAt;\n"
if text.count(rewarded_state_marker) != 1:
    raise SystemExit(
        '100258 rewarded-ad state not found; diamonds patch must run after it')
diamonds_state = '''  int _diamondsBalance = 0;
  int _diamondAdsToday = 0;
  bool _diamondsLoading = true;
  bool _watchingDiamondAd = false;
'''
text = text.replace(
    rewarded_state_marker,
    rewarded_state_marker + diamonds_state,
    1,
)

daily_init_marker = '''  @override
  void initState() {
    super.initState();
    _loadRewardState();
  }
'''
daily_init_replacement = '''  @override
  void initState() {
    super.initState();
    _loadRewardState();
    unawaited(_loadDiamondsState());
  }
'''
if text.count(daily_init_marker) != 1:
    raise SystemExit('Expected exactly one daily-tasks init marker')
text = text.replace(daily_init_marker, daily_init_replacement, 1)

open_task_marker = "  Future<void> _openTask(int index) async {\n"
if text.count(open_task_marker) != 1:
    raise SystemExit('Expected exactly one daily task opener marker')

diamonds_methods = r'''  Future<void> _loadDiamondsState() async {
    final state = await DedaDiamondsWallet.load();
    if (!mounted) return;
    setState(() {
      _diamondsBalance = state.balance;
      _diamondAdsToday = state.viewsToday;
      _diamondsLoading = false;
    });
    if (_diamondAdsToday < DedaDiamondsWallet.maxAdsPerDay) {
      _queueRewardedAdPreload();
    }
  }

  Future<void> _watchDiamondsRewardedAd() async {
    if (_watchingDiamondAd || _diamondsLoading) return;

    if (_diamondAdsToday >= DedaDiamondsWallet.maxAdsPerDay) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            dedaText(
              'اكتملت مشاهدات اليوم. تتجدد غدًا.',
              'Today\'s rewarded views are complete. They reset tomorrow.',
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
      return;
    }

    setState(() => _watchingDiamondAd = true);

    var ad = _preparedRewardedAd;
    if (ad == null) {
      final loaded = await _loadRewardedAdOnce();
      if (!mounted) return;
      if (!loaded) {
        setState(() => _watchingDiamondAd = false);
        _showRewardedAdUnavailableMessage();
        _rewardedAdNextAutomaticAttemptAt = null;
        _preloadRewardedAdWithRetry(force: true);
        return;
      }
      ad = _preparedRewardedAd;
    }

    if (ad == null) {
      if (mounted) setState(() => _watchingDiamondAd = false);
      _showRewardedAdUnavailableMessage();
      return;
    }

    _preparedRewardedAd = null;
    var rewardEarned = false;
    Future<DedaDiamondsClaimResult>? claimFuture;

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (closedAd) async {
        closedAd.dispose();
        if (!mounted) return;

        if (!rewardEarned || claimFuture == null) {
          setState(() => _watchingDiamondAd = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                dedaText(
                  'لم تكتمل مشاهدة الإعلان، لذلك لم تتم إضافة الماسات.',
                  'The ad was not completed, so no diamonds were added.',
                ),
                textAlign: TextAlign.center,
              ),
            ),
          );
          _rewardedAdNextAutomaticAttemptAt = null;
          _queueRewardedAdPreload();
          return;
        }

        final result = await claimFuture!;
        if (!mounted) return;
        setState(() {
          _watchingDiamondAd = false;
          _diamondsBalance = result.balance;
          _diamondAdsToday = result.viewsToday;
        });

        if (!result.awarded) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                dedaText(
                  'اكتملت مشاهدات اليوم. تتجدد غدًا.',
                  'Today\'s rewarded views are complete. They reset tomorrow.',
                ),
                textAlign: TextAlign.center,
              ),
            ),
          );
          return;
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              dedaText(
                'تم منحك 3 ماسات بنجاح 💎',
                'You received 3 diamonds successfully 💎',
              ),
              textAlign: TextAlign.center,
            ),
          ),
        );

        _rewardedAdNextAutomaticAttemptAt = null;
        if (_diamondAdsToday < DedaDiamondsWallet.maxAdsPerDay) {
          _queueRewardedAdPreload();
        }

        await Future<void>.delayed(const Duration(milliseconds: 650));
        if (!mounted) return;
        await Navigator.push<void>(
          context,
          MaterialPageRoute(builder: (_) => const DedaAccountHubPage()),
        );
        if (mounted) {
          unawaited(_loadDiamondsState());
        }
      },
      onAdFailedToShowFullScreenContent: (failedAd, error) {
        failedAd.dispose();
        debugPrint(
          'DEDA diamonds rewarded ad show failed: '
          'code=${error.code}, domain=${error.domain}, message=${error.message}',
        );
        if (!mounted) return;
        setState(() => _watchingDiamondAd = false);
        _showRewardedAdUnavailableMessage();
        _rewardedAdNextAutomaticAttemptAt = null;
        _queueRewardedAdPreload();
      },
    );

    ad.show(
      onUserEarnedReward: (shownAd, reward) {
        rewardEarned = true;
        claimFuture = DedaDiamondsWallet.claimReward();
      },
    );
  }

  Widget _diamondsRewardCard() {
    final remaining =
        (DedaDiamondsWallet.maxAdsPerDay - _diamondAdsToday).clamp(
      0,
      DedaDiamondsWallet.maxAdsPerDay,
    );
    final completed = remaining == 0;
    final disabled = _diamondsLoading || _watchingDiamondAd || completed;

    return Container(
      constraints: const BoxConstraints(minHeight: 96),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFFFFFCF6),
            Color(0xFFF8F2FB),
          ],
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFFD7C0E8),
          width: 1.2,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x184E2674),
            blurRadius: 9,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          SizedBox(
            width: 54,
            height: 54,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [
                        Color(0xFFE4D0F7),
                        Color(0xFFB98BE3),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x338E56C5),
                        blurRadius: 8,
                        offset: Offset(0, 3),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.diamond_rounded,
                    color: Color(0xFF6D3B9C),
                    size: 29,
                  ),
                ),
                Positioned(
                  right: -1,
                  bottom: -1,
                  child: Container(
                    width: 23,
                    height: 23,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0A3158),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 15,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  dedaText(
                    'شاهد إعلانًا واربح ماسات',
                    'Watch an ad and earn diamonds',
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    color: Color(0xFF183B60),
                    fontSize: 13.6,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  dedaText(
                    '3 ماسات لكل إعلان • الحد اليومي 15 ماسة',
                    '3 diamonds per ad • daily limit 15 diamonds',
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    color: Color(0xFF6E6780),
                    fontSize: 10.6,
                    height: 1.18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  completed
                      ? dedaText(
                          'اكتملت مشاهدات اليوم • تتجدد غدًا',
                          'Today\'s views are complete • resets tomorrow',
                        )
                      : dedaText(
                          'المتبقي اليوم: $remaining من 5 • رصيدك $_diamondsBalance 💎',
                          'Remaining today: $remaining of 5 • balance $_diamondsBalance 💎',
                        ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: completed
                        ? const Color(0xFF7A6D82)
                        : const Color(0xFF7546A1),
                    fontSize: 9.8,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 67,
            height: 38,
            child: FilledButton(
              onPressed: disabled ? null : _watchDiamondsRewardedAd,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF0A3158),
                disabledBackgroundColor: const Color(0xFF87919A),
                foregroundColor: Colors.white,
                disabledForegroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13),
                ),
              ),
              child: _watchingDiamondAd
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        completed
                            ? dedaText('اكتمل', 'Done')
                            : dedaText('شاهد', 'Watch'),
                        maxLines: 1,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

'''
text = text.replace(open_task_marker, diamonds_methods + open_task_marker, 1)

info_end_marker = '''                    ),
                  ],
                ),
              ),
            ],
          ),
'''
info_phrase = (
    "توضيح: يمكن إنجاز بعض مهام الخريطة ضمن مسار واحد، "
    "وسيحتسبها DEDA تلقائيًا عند تحقق شروطها."
)
info_pos = text.find(info_phrase)
if info_pos < 0:
    raise SystemExit('Daily tasks explanation phrase not found')
tail_pos = text.find(info_end_marker, info_pos)
if tail_pos < 0:
    raise SystemExit('Daily tasks explanation tail not found')
info_end_replacement = '''                    ),
                    const SizedBox(height: 8),
                    _diamondsRewardCard(),
                  ],
                ),
              ),
            ],
          ),
'''
text = (
    text[:tail_pos]
    + info_end_replacement
    + text[tail_pos + len(info_end_marker):]
)

for required in (
    "class DedaDiamondsWallet",
    "rewardPerAd = 3",
    "maxAdsPerDay = 5",
    "تم منحك 3 ماسات بنجاح 💎",
    "_diamondsRewardCard()",
    "_diamondsBalanceCard(diamonds)",
    "MaterialPageRoute(builder: (_) => const DedaAccountHubPage())",
):
    if required not in text:
        raise SystemExit(f'Missing diamonds feature marker: {required}')

path.write_text(text, encoding='utf-8')
print('DEDA 100259 diamonds rewarded-ad feature applied.')
