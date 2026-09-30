from pathlib import Path

path = Path('lib/main.dart')
text = path.read_text(encoding='utf-8')

old_fields = """  final Set<int> _openedPointTiers = <int>{};
  bool _stageOneRewardClaimed = false;
  bool _stageOneRewardClaiming = false;
"""
new_fields = """  final Set<int> _openedPointTiers = <int>{};
  final Set<int> _claimedPointTiers = <int>{};
  final Set<int> _claimingPointTiers = <int>{};

  static const List<int> _pointTierThresholds = <int>[
    5000,
    10000,
    15000,
    20000,
    25000,
  ];
  static const Map<int, int> _pointTierBonuses = <int, int>{
    5000: 50,
    10000: 100,
    15000: 150,
    20000: 200,
    25000: 250,
  };
"""
if old_fields not in text:
    raise SystemExit('field anchor not found')
text = text.replace(old_fields, new_fields, 1)

old_part = """  String get _rewardStageOnePart {
    final code = _rewardCode16();
    return code.length >= 3 ? code.substring(0, 3) : '---';
  }
"""
new_part = """  int _pointTierBonus(int threshold) => _pointTierBonuses[threshold] ?? 0;

  int _pointTierIndex(int threshold) => _pointTierThresholds.indexOf(threshold);

  String _rewardPartForTier(int threshold) {
    final index = _pointTierIndex(threshold);
    if (index < 0) return '---';
    final code = _rewardCode16();
    const starts = <int>[0, 3, 6, 9, 12];
    const ends = <int>[3, 6, 9, 12, 16];
    final start = starts[index];
    final end = ends[index];
    if (code.length < end) return '---';
    return code.substring(start, end);
  }

  String _tierPartLabel(int index) {
    const labelsAr = <String>[
      'الجزء الأول من الرمز',
      'الجزء الثاني من الرمز',
      'الجزء الثالث من الرمز',
      'الجزء الرابع من الرمز',
      'الجزء الخامس من الرمز',
    ];
    const labelsEn = <String>[
      'First code part',
      'Second code part',
      'Third code part',
      'Fourth code part',
      'Fifth code part',
    ];
    if (index < 0 || index >= labelsAr.length) return '';
    return dedaText(labelsAr[index], labelsEn[index]);
  }
"""
if old_part not in text:
    raise SystemExit('reward part anchor not found')
text = text.replace(old_part, new_part, 1)

start = text.index('  Future<void> _loadOpenedPointTiers() async {')
end = text.index('  String _formatPointTier(int value) {', start)
new_logic = r'''  Future<void> _loadOpenedPointTiers() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_pointTierPrefsKey) ?? const <String>[];
    final loaded = raw.map(int.tryParse).whereType<int>().toSet();
    final claimed = <int>{};

    var migratedLegacyStageOne = false;
    final accountKey = DedaTaskEngine._accountKey();
    if (accountKey.isNotEmpty) {
      final state = await DedaTaskEngine._readState(prefs, accountKey);
      final awards = Map<String, dynamic>.from(state['awards'] as Map);
      final ledger = List<dynamic>.from(state['ledger'] as List);

      const legacyId = 'point_tier|5000';
      const stageOneReserveId = 'point_tier_reserve|5000';
      const stageOneClaimId = 'point_tier_claim|5000';
      if (!awards.containsKey(stageOneReserveId) &&
          !awards.containsKey(stageOneClaimId) &&
          awards.containsKey(legacyId)) {
        // Build 232 temporarily awarded only +50. Remove it once so that
        // accounts coming directly from that build can use the agreed flow.
        awards.remove(legacyId);
        ledger.removeWhere((entry) {
          if (entry is! Map) return false;
          return entry['id']?.toString() == legacyId;
        });
        state['awards'] = awards;
        state['ledger'] = ledger;
        await DedaTaskEngine._writeState(prefs, accountKey, state);
        migratedLegacyStageOne = true;
      }

      for (final threshold in _pointTierThresholds) {
        final reserveId = 'point_tier_reserve|$threshold';
        final claimId = 'point_tier_claim|$threshold';
        final hasReserve = awards.containsKey(reserveId);
        final hasClaim = awards.containsKey(claimId);
        if (hasReserve || hasClaim) loaded.add(threshold);
        if (hasClaim) claimed.add(threshold);
        if (!hasReserve && !hasClaim) loaded.remove(threshold);
      }

      if (migratedLegacyStageOne) {
        final total = DedaTaskEngine._effectiveTotalFromState(state);
        DedaTaskEngine._loadedAccountKey = accountKey;
        DedaTaskEngine.totalPointsNotifier.value = total;
        DedaTaskEngine.revisionNotifier.value++;
      }
    }

    final ordered = loaded.toList()..sort();
    await prefs.setStringList(
      _pointTierPrefsKey,
      ordered.map((value) => value.toString()).toList(),
    );

    if (!mounted) return;
    setState(() {
      _openedPointTiers
        ..clear()
        ..addAll(loaded);
      _claimedPointTiers
        ..clear()
        ..addAll(claimed);
    });
  }

  Future<void> _claimPointTierReward(int threshold) async {
    if (!_pointTierThresholds.contains(threshold) ||
        _claimedPointTiers.contains(threshold) ||
        _claimingPointTiers.contains(threshold) ||
        !_openedPointTiers.contains(threshold)) {
      return;
    }

    setState(() => _claimingPointTiers.add(threshold));
    var claimedNow = false;
    try {
      final accountKey = DedaTaskEngine._accountKey();
      if (accountKey.isEmpty) {
        throw StateError('points-account-not-ready');
      }

      final prefs = await SharedPreferences.getInstance();
      final state = await DedaTaskEngine._readState(prefs, accountKey);
      final awards = Map<String, dynamic>.from(state['awards'] as Map);
      final ledger = List<dynamic>.from(state['ledger'] as List);
      final reserveId = 'point_tier_reserve|$threshold';
      final claimId = 'point_tier_claim|$threshold';
      final bonus = _pointTierBonus(threshold);

      if (!awards.containsKey(reserveId)) {
        throw StateError('tier-points-not-reserved');
      }

      if (!awards.containsKey(claimId)) {
        final now = DateTime.now().toUtc().toIso8601String();
        final claim = <String, dynamic>{
          'id': claimId,
          'points': threshold + bonus,
          'type': 'point_tier_claim',
          'event': 'point_tier_points_claimed',
          'threshold': threshold,
          'reservedPoints': threshold,
          'bonusPoints': bonus,
          'createdAt': now,
        };
        awards[claimId] = claim;
        ledger.add(claim);
        if (ledger.length > DedaTaskEngine._maxLedgerEntries) {
          ledger.removeRange(
            0,
            ledger.length - DedaTaskEngine._maxLedgerEntries,
          );
        }
        state['awards'] = awards;
        state['ledger'] = ledger;
        await DedaTaskEngine._writeState(prefs, accountKey, state);
        claimedNow = true;
      }

      final total = DedaTaskEngine._effectiveTotalFromState(state);
      DedaTaskEngine._loadedAccountKey = accountKey;
      DedaTaskEngine.totalPointsNotifier.value = total;
      DedaTaskEngine.revisionNotifier.value++;

      if (!mounted) return;
      setState(() {
        _claimedPointTiers.add(threshold);
        _claimingPointTiers.remove(threshold);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            claimedNow
                ? dedaText(
                    'تم استلام ${_formatPointTier(threshold)} نقطة وإضافة هدية $bonus نقطة إلى رصيدك.',
                    '${_formatPointTier(threshold)} points were returned and the $bonus-point bonus was added.',
                  )
                : dedaText(
                    'تم استلام نقاط هذه البطاقة مسبقًا.',
                    'This card was already claimed.',
                  ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _claimingPointTiers.remove(threshold));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            dedaText(
              'تعذر استلام النقاط الآن. حاول مرة أخرى.',
              'Could not claim the points right now. Please try again.',
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
  }

  Future<void> _openPointTier(int threshold, int totalPoints) async {
    final index = _pointTierIndex(threshold);
    if (index < 0 || _openedPointTiers.contains(threshold)) return;

    final previousThreshold = index == 0 ? null : _pointTierThresholds[index - 1];
    if (previousThreshold != null &&
        !_claimedPointTiers.contains(previousThreshold)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            dedaText(
              'استلم نقاط المرحلة السابقة أولًا حتى تفتح هذه البطاقة.',
              'Claim the previous stage first to unlock this card.',
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
      return;
    }

    try {
      final accountKey = DedaTaskEngine._accountKey();
      if (accountKey.isEmpty) {
        throw StateError('points-account-not-ready');
      }
      final prefs = await SharedPreferences.getInstance();
      final state = await DedaTaskEngine._readState(prefs, accountKey);
      final awards = Map<String, dynamic>.from(state['awards'] as Map);
      final ledger = List<dynamic>.from(state['ledger'] as List);
      final reserveId = 'point_tier_reserve|$threshold';
      final claimId = 'point_tier_claim|$threshold';
      final bonus = _pointTierBonus(threshold);

      if (previousThreshold != null &&
          !awards.containsKey('point_tier_claim|$previousThreshold')) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                dedaText(
                  'استلم نقاط المرحلة السابقة أولًا حتى تفتح هذه البطاقة.',
                  'Claim the previous stage first to unlock this card.',
                ),
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        return;
      }

      if (awards.containsKey(claimId) || awards.containsKey(reserveId)) {
        if (!mounted) return;
        setState(() {
          _openedPointTiers.add(threshold);
          if (awards.containsKey(claimId)) {
            _claimedPointTiers.add(threshold);
          }
        });
        final ordered = _openedPointTiers.toList()..sort();
        await prefs.setStringList(
          _pointTierPrefsKey,
          ordered.map((value) => value.toString()).toList(),
        );
        return;
      }

      final currentTotal = DedaTaskEngine._effectiveTotalFromState(state);
      if (currentTotal < threshold) {
        final remaining = threshold - currentTotal;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              dedaText(
                'تحتاج $remaining نقطة إضافية لفتح هذه البطاقة.',
                'You need $remaining more points to open this card.',
              ),
              textAlign: TextAlign.center,
            ),
          ),
        );
        return;
      }

      final now = DateTime.now().toUtc().toIso8601String();
      final reserve = <String, dynamic>{
        'id': reserveId,
        'points': -threshold,
        'type': 'point_tier_reserve',
        'event': 'point_tier_points_reserved',
        'threshold': threshold,
        'reservedPoints': threshold,
        'bonusPoints': bonus,
        'createdAt': now,
      };
      awards[reserveId] = reserve;
      ledger.add(reserve);
      if (ledger.length > DedaTaskEngine._maxLedgerEntries) {
        ledger.removeRange(
          0,
          ledger.length - DedaTaskEngine._maxLedgerEntries,
        );
      }
      state['awards'] = awards;
      state['ledger'] = ledger;
      await DedaTaskEngine._writeState(prefs, accountKey, state);

      final afterReserve = DedaTaskEngine._effectiveTotalFromState(state);
      DedaTaskEngine._loadedAccountKey = accountKey;
      DedaTaskEngine.totalPointsNotifier.value = afterReserve;
      DedaTaskEngine.revisionNotifier.value++;

      _openedPointTiers.add(threshold);
      final ordered = _openedPointTiers.toList()..sort();
      await prefs.setStringList(
        _pointTierPrefsKey,
        ordered.map((value) => value.toString()).toList(),
      );
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            dedaText(
              'تم خصم ${_formatPointTier(threshold)} نقطة وحجزها داخل البطاقة. استلمها مع هدية $bonus نقطة.',
              '${_formatPointTier(threshold)} points were reserved in the card. Claim them with the $bonus-point bonus.',
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            dedaText(
              'تعذر فتح البطاقة الآن. حاول مرة أخرى.',
              'Could not open the card right now. Please try again.',
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
  }

'''
text = text[:start] + new_logic + text[end:]

start = text.index('  Widget _rewardStageOneBackFace() {')
end = text.index('  Widget _pointTierFrontFace({', start)
new_back = r'''  Widget _rewardTierBackFace({
    required int threshold,
    required int index,
  }) {
    const gold = Color(0xFFFFD76A);
    const deep = Color(0xFF020914);
    final bonus = _pointTierBonus(threshold);
    final claimed = _claimedPointTiers.contains(threshold);
    final claiming = _claimingPointTiers.contains(threshold);
    final thresholdLabel = _formatPointTier(threshold);
    final claimLabel = claimed
        ? dedaText(
            'تم استلام $thresholdLabel + $bonus',
            'Claimed $thresholdLabel + $bonus',
          )
        : dedaText(
            'استلم $thresholdLabel + $bonus',
            'Claim $thresholdLabel + $bonus',
          );

    return Stack(
      key: ValueKey<String>('reward-back-$threshold'),
      children: [
        Positioned(
          top: 0,
          left: 0,
          child: Icon(
            Icons.diamond_outlined,
            size: 13,
            color: gold.withOpacity(0.90),
          ),
        ),
        Positioned(
          top: 0,
          right: 0,
          child: Icon(
            Icons.diamond_outlined,
            size: 13,
            color: gold.withOpacity(0.90),
          ),
        ),
        Column(
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
            const SizedBox(height: 4),
            Text(
              _tierPartLabel(index),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: gold,
                fontSize: 11.5,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 5),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xCC020914),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: gold, width: 1.5),
              ),
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: Text(
                  _rewardPartForTier(threshold),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 25,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 4.0,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 5),
            Text(
              dedaText(
                'تم كشف هذا الجزء من رمزك',
                'This part of your code is revealed',
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                height: 1.18,
              ),
            ),
            const SizedBox(height: 5),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0x55173F31),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: gold.withOpacity(0.72)),
              ),
              child: Text(
                claimed
                    ? dedaText(
                        'تم استلام $thresholdLabel نقطة + هدية $bonus',
                        '$thresholdLabel points + $bonus bonus claimed',
                      )
                    : dedaText(
                        '$thresholdLabel نقطة مستقطعة وجاهزة للاستلام + هدية $bonus',
                        '$thresholdLabel points reserved and ready + $bonus bonus',
                      ),
                textAlign: TextAlign.center,
                maxLines: 2,
                style: const TextStyle(
                  color: gold,
                  fontSize: 9.2,
                  fontWeight: FontWeight.w900,
                  height: 1.15,
                ),
              ),
            ),
            const SizedBox(height: 5),
            SizedBox(
              height: 35,
              child: Material(
                color: claimed ? const Color(0xFF173F31) : deep,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: claimed || claiming
                      ? null
                      : () => _claimPointTierReward(threshold),
                  child: Container(
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: gold, width: 1.2),
                    ),
                    child: claiming
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: gold,
                            ),
                          )
                        : FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              claimLabel,
                              maxLines: 1,
                              style: const TextStyle(
                                color: gold,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.check_circle_rounded, color: gold, size: 16),
                const SizedBox(width: 4),
                Text(
                  dedaText('تم الفتح', 'Opened'),
                  style: const TextStyle(
                    color: gold,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 1),
                  child: Icon(
                    Icons.arrow_forward_rounded,
                    color: gold,
                    size: 15,
                  ),
                ),
                const SizedBox(width: 3),
                Expanded(
                  child: Text(
                    index == _pointTierThresholds.length - 1
                        ? dedaText(
                            'اكتملت مراحل بطاقات النقاط',
                            'Point card stages completed',
                          )
                        : dedaText(
                            'استلم نقاطك ثم افتح البطاقة التالية لإكمال الرمز',
                            'Claim your points, then open the next card to continue the code',
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
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

'''
text = text[:start] + new_back + text[end:]

start = text.index('  Widget _pointTierFrontFace({')
end = text.index('  Widget _pointsTierCard({', start)
new_front = r'''  Widget _pointTierFrontFace({
    required int threshold,
    required int index,
    required bool available,
    required bool waitingForPrevious,
  }) {
    const gold = Color(0xFFFFD76A);
    const deepGold = Color(0xFFB88418);
    final stageAr = <String>[
      'الأولى',
      'الثانية',
      'الثالثة',
      'الرابعة',
      'الخامسة',
    ][index];
    return Stack(
      key: ValueKey<String>('reward-front-$threshold'),
      children: [
        Positioned(
          top: 0,
          left: 0,
          child: Icon(
            Icons.diamond_outlined,
            size: 13,
            color: gold.withOpacity(0.90),
          ),
        ),
        Positioned(
          top: 0,
          right: 0,
          child: Icon(
            Icons.diamond_outlined,
            size: 13,
            color: gold.withOpacity(0.90),
          ),
        ),
        Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'DEDA',
              style: TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 2.1,
              ),
            ),
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xAA020914),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: deepGold.withOpacity(0.9)),
              ),
              child: Text(
                dedaText('بطاقة النقاط', 'POINT CARD'),
                textAlign: TextAlign.center,
                maxLines: 1,
                style: const TextStyle(
                  color: gold,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(height: 7),
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [gold.withOpacity(0.36), Colors.transparent],
                ),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  const Icon(Icons.shield_rounded, size: 70, color: gold),
                  Container(
                    width: 37,
                    height: 37,
                    decoration: BoxDecoration(
                      color: const Color(0xFF081B31),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withOpacity(0.82)),
                    ),
                    child: Icon(
                      available ? Icons.lock_open_rounded : Icons.lock_rounded,
                      size: 23,
                      color: gold,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              _formatPointTier(threshold),
              maxLines: 1,
              style: const TextStyle(
                color: gold,
                fontSize: 25,
                height: 1.0,
                fontWeight: FontWeight.w900,
                shadows: [Shadow(color: Colors.black54, blurRadius: 5)],
              ),
            ),
            Text(
              dedaText('نقطة', 'points'),
              style: const TextStyle(
                color: gold,
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 5),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0x88000000),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: gold.withOpacity(0.68)),
              ),
              child: Text(
                available
                    ? dedaText('اضغط للفتح', 'Tap to open')
                    : waitingForPrevious
                        ? dedaText(
                            'بانتظار استلام المرحلة السابقة',
                            'Previous stage claim required',
                          )
                        : dedaText(
                            'تفتح عند ${_formatPointTier(threshold)}',
                            'Unlocks at ${_formatPointTier(threshold)}',
                          ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9.2,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 5),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xAA020914),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: gold.withOpacity(0.82)),
              ),
              child: Text(
                DedaLanguageState.isArabic
                    ? 'المرحلة $stageAr'
                    : 'Stage ${index + 1}',
                maxLines: 1,
                style: const TextStyle(
                  color: gold,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

'''
text = text[:start] + new_front + text[end:]

start = text.index('  Widget _pointsTierCard({')
end = text.index('  Widget _pointsCardsPanel(int totalPoints) {', start)
new_card = r'''  Widget _pointsTierCard({
    required int threshold,
    required int index,
    required int totalPoints,
  }) {
    const starts = <Color>[
      Color(0xFF0B3D78),
      Color(0xFF07613F),
      Color(0xFF5A1878),
      Color(0xFF8C101B),
      Color(0xFF1C1C1C),
    ];
    const ends = <Color>[
      Color(0xFF041B36),
      Color(0xFF02341F),
      Color(0xFF260634),
      Color(0xFF41050B),
      Color(0xFF050505),
    ];
    const gold = Color(0xFFFFD76A);
    final opened = _openedPointTiers.contains(threshold);
    final previousThreshold = index == 0 ? null : _pointTierThresholds[index - 1];
    final waitingForPrevious = previousThreshold != null &&
        !_claimedPointTiers.contains(previousThreshold);
    final lockedByPoints = totalPoints < threshold;
    final available = !opened && !waitingForPrevious && !lockedByPoints;

    return Semantics(
      button: true,
      label: dedaText(
        'بطاقة ${_formatPointTier(threshold)} نقطة، المرحلة ${index + 1}',
        '${_formatPointTier(threshold)} point reward card, stage ${index + 1}',
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _openPointTier(threshold, totalPoints),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          width: 154,
          padding: const EdgeInsets.fromLTRB(9, 9, 9, 10),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [starts[index], ends[index]],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: available ? const Color(0xFFFFF0A3) : gold,
              width: available ? 2.2 : 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: starts[index].withOpacity(0.30),
                blurRadius: available ? 16 : 10,
                offset: const Offset(0, 6),
              ),
              const BoxShadow(
                color: Color(0x44E8C56C),
                blurRadius: 8,
                spreadRadius: -2,
              ),
            ],
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 420),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            layoutBuilder: (currentChild, previousChildren) =>
                currentChild ?? const SizedBox.shrink(),
            transitionBuilder: (child, animation) {
              final turn = Tween<double>(
                begin: math.pi / 2,
                end: 0,
              ).animate(animation);
              return AnimatedBuilder(
                animation: turn,
                child: child,
                builder: (context, child) {
                  final matrix = Matrix4.identity()
                    ..setEntry(3, 2, 0.0012)
                    ..rotateY(turn.value);
                  return Transform(
                    alignment: Alignment.center,
                    transform: matrix,
                    child: child,
                  );
                },
              );
            },
            child: opened
                ? _rewardTierBackFace(threshold: threshold, index: index)
                : _pointTierFrontFace(
                    threshold: threshold,
                    index: index,
                    available: available,
                    waitingForPrevious: waitingForPrevious,
                  ),
          ),
        ),
      ),
    );
  }

'''
text = text[:start] + new_card + text[end:]

# Reuse the shared threshold definition in the panel instead of duplicating it.
text = text.replace(
    """  Widget _pointsCardsPanel(int totalPoints) {\n    const thresholds = <int>[5000, 10000, 15000, 20000, 25000];\n""",
    """  Widget _pointsCardsPanel(int totalPoints) {\n    const thresholds = _pointTierThresholds;\n""",
    1,
)

required = [
    "final Set<int> _claimedPointTiers = <int>{};",
    "10000: 100",
    "25000: 250",
    "Future<void> _claimPointTierReward(int threshold) async",
    "'points': threshold + bonus",
    "'points': -threshold",
    "_rewardPartForTier(threshold)",
    "waitingForPrevious",
    "_rewardTierBackFace(threshold: threshold, index: index)",
]
for needle in required:
    if needle not in text:
        raise SystemExit(f'missing expected result: {needle}')

for forbidden in [
    'bool _stageOneRewardClaimed',
    'bool _stageOneRewardClaiming',
    'Widget _rewardStageOneBackFace()',
    "if (threshold != 5000)",
]:
    if forbidden in text:
        raise SystemExit(f'old stage-one-only logic still present: {forbidden}')

path.write_text(text, encoding='utf-8')
print('all tiers points engine patch applied')
