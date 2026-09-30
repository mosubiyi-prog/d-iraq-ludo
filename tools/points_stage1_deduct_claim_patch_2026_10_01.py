from pathlib import Path
import re

path = Path('lib/main.dart')
text = path.read_text()


def replace_block(start_marker: str, end_marker: str, replacement: str) -> None:
    global text
    start = text.find(start_marker)
    if start < 0:
        raise SystemExit(f'missing start marker: {start_marker}')
    end = text.find(end_marker, start)
    if end < 0:
        raise SystemExit(f'missing end marker: {end_marker}')
    text = text[:start] + replacement + text[end:]

# Stage-one state loading + one-time migration from Build 232's temporary +50-only flow.
load_replacement = r'''  Future<void> _loadOpenedPointTiers() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_pointTierPrefsKey) ?? const <String>[];
    final loaded = raw.map(int.tryParse).whereType<int>().toSet();

    var rewardClaimed = false;
    var pointsReserved = false;
    var migratedLegacyStageOne = false;
    final accountKey = DedaTaskEngine._accountKey();
    if (accountKey.isNotEmpty) {
      final state = await DedaTaskEngine._readState(prefs, accountKey);
      final awards = Map<String, dynamic>.from(state['awards'] as Map);
      final ledger = List<dynamic>.from(state['ledger'] as List);
      const reserveId = 'point_tier_reserve|5000';
      const claimId = 'point_tier_claim|5000';
      const legacyId = 'point_tier|5000';

      final hasNewReserve = awards.containsKey(reserveId);
      final hasNewClaim = awards.containsKey(claimId);
      if (!hasNewReserve && !hasNewClaim && awards.containsKey(legacyId)) {
        // Build 232 awarded only +50. Remove that temporary test award once so
        // this account can run the agreed deduct -> claim 5,000 + 50 flow.
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

      pointsReserved = awards.containsKey(reserveId);
      rewardClaimed = awards.containsKey(claimId);

      if (migratedLegacyStageOne) {
        final total = DedaTaskEngine._effectiveTotalFromState(state);
        DedaTaskEngine._loadedAccountKey = accountKey;
        DedaTaskEngine.totalPointsNotifier.value = total;
        DedaTaskEngine.revisionNotifier.value++;
      }
    }

    // The points ledger is now the source of truth for whether the first card
    // is actually opened. Old Build 232 visual-only state is reset safely.
    if (pointsReserved || rewardClaimed) {
      loaded.add(5000);
    } else {
      loaded.remove(5000);
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
      _stageOneRewardClaimed = rewardClaimed;
    });
  }

'''
replace_block(
    '  Future<void> _loadOpenedPointTiers() async {',
    '  Future<void> _claimStageOneReward() async {',
    load_replacement,
)

claim_replacement = r'''  Future<void> _claimStageOneReward() async {
    if (_stageOneRewardClaimed ||
        _stageOneRewardClaiming ||
        !_openedPointTiers.contains(5000)) {
      return;
    }

    setState(() => _stageOneRewardClaiming = true);
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
      const reserveId = 'point_tier_reserve|5000';
      const claimId = 'point_tier_claim|5000';

      if (!awards.containsKey(reserveId)) {
        throw StateError('stage-one-points-not-reserved');
      }

      if (!awards.containsKey(claimId)) {
        final now = DateTime.now().toUtc().toIso8601String();
        final claim = <String, dynamic>{
          'id': claimId,
          'points': 5050,
          'type': 'point_tier_claim',
          'event': 'stage_one_points_claimed',
          'threshold': 5000,
          'reservedPoints': 5000,
          'bonusPoints': 50,
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
        _stageOneRewardClaimed = true;
        _stageOneRewardClaiming = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            claimedNow
                ? dedaText(
                    'تم استلام 5,000 نقطة وإضافة هدية 50 نقطة إلى رصيدك.',
                    '5,000 points were returned and the 50-point bonus was added.',
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
      setState(() => _stageOneRewardClaiming = false);
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

'''
replace_block(
    '  Future<void> _claimStageOneReward() async {',
    '  Future<void> _openPointTier(int threshold, int totalPoints) async {',
    claim_replacement,
)

open_replacement = r'''  Future<void> _openPointTier(int threshold, int totalPoints) async {
    if (threshold != 5000) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            dedaText(
              'نثبت المرحلة الأولى أولاً، وبعد نجاحها نفعّل هذه البطاقة بالتسلسل.',
              'Stage one is being completed first; this card will unlock in sequence.',
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
      return;
    }
    if (_openedPointTiers.contains(threshold)) return;

    try {
      final accountKey = DedaTaskEngine._accountKey();
      if (accountKey.isEmpty) {
        throw StateError('points-account-not-ready');
      }
      final prefs = await SharedPreferences.getInstance();
      final state = await DedaTaskEngine._readState(prefs, accountKey);
      final awards = Map<String, dynamic>.from(state['awards'] as Map);
      final ledger = List<dynamic>.from(state['ledger'] as List);
      const reserveId = 'point_tier_reserve|5000';
      const claimId = 'point_tier_claim|5000';

      if (awards.containsKey(claimId) || awards.containsKey(reserveId)) {
        setState(() => _openedPointTiers.add(threshold));
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
        'points': -5000,
        'type': 'point_tier_reserve',
        'event': 'stage_one_points_reserved',
        'threshold': 5000,
        'reservedPoints': 5000,
        'bonusPoints': 50,
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
              'تم خصم 5,000 نقطة وحجزها داخل البطاقة. استلمها مع هدية 50 نقطة.',
              '5,000 points were reserved in the card. Claim them with the 50-point bonus.',
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
replace_block(
    '  Future<void> _openPointTier(int threshold, int totalPoints) async {',
    '  String _formatPointTier(int value) {',
    open_replacement,
)

# Make the first card clearly show the reserved principal and the +50 gift.
old_claim_label = """    final claimLabel = _stageOneRewardClaimed
        ? dedaText('تم الاسترداد +50', 'Claimed +50')
        : dedaText('استرد نقاطك 5,000 + 50', 'Restore 5,000 + 50');
"""
new_claim_label = """    final claimLabel = _stageOneRewardClaimed
        ? dedaText('تم استلام 5,000 + 50', 'Claimed 5,000 + 50')
        : dedaText('استلم 5,000 + 50', 'Claim 5,000 + 50');
"""
if old_claim_label not in text:
    raise SystemExit('claim label marker missing')
text = text.replace(old_claim_label, new_claim_label, 1)

old_revealed = """            Text(
              dedaText(
                'تم كشف الجزء الأول من رمزك',
                'The first part of your code is revealed',
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
            const SizedBox(height: 6),
"""
new_revealed = """            Text(
              dedaText(
                'تم كشف الجزء الأول من رمزك',
                'The first part of your code is revealed',
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
                _stageOneRewardClaimed
                    ? dedaText(
                        'تم استلام 5,000 نقطة + هدية 50',
                        '5,000 points + 50 bonus claimed',
                      )
                    : dedaText(
                        '5,000 نقطة مستقطعة وجاهزة للاستلام + هدية 50',
                        '5,000 points reserved and ready + 50 bonus',
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
"""
if old_revealed not in text:
    raise SystemExit('stage one revealed marker missing')
text = text.replace(old_revealed, new_revealed, 1)

# Give the corrected card a little more vertical room.
old_height = """                  SizedBox(
                    height: 270,
                    child: Directionality(
"""
new_height = """                  SizedBox(
                    height: 292,
                    child: Directionality(
"""
if old_height not in text:
    raise SystemExit('points cards height marker missing')
text = text.replace(old_height, new_height, 1)

# Fix the top points summary: short subtitle + wider badge containing the full
# number and the word نقطة, without changing other section cards.
old_param = """    Color trailingColor = const Color(0xFF59635B),
    String? badgeText,
  }) {
"""
new_param = """    Color trailingColor = const Color(0xFF59635B),
    String? badgeText,
    double badgeMaxWidth = 96,
  }) {
"""
if old_param not in text:
    raise SystemExit('section card parameter marker missing')
text = text.replace(old_param, new_param, 1)
text = text.replace(
    'constraints: const BoxConstraints(maxWidth: 96),',
    'constraints: BoxConstraints(maxWidth: badgeMaxWidth),',
    1,
)
old_points_card = """                      subtitle: dedaText(
                        'رصيدك: $totalPoints نقطة',
                        'Current balance: $totalPoints points',
                      ),
                      badgeText: totalPoints.toString(),
"""
new_points_card = """                      subtitle: dedaText(
                        'الرصيد الحالي',
                        'Current balance',
                      ),
                      badgeText: dedaText(
                        '$totalPoints نقطة',
                        '$totalPoints points',
                      ),
                      badgeMaxWidth: 138,
"""
if old_points_card not in text:
    raise SystemExit('top points card marker missing')
text = text.replace(old_points_card, new_points_card, 1)

path.write_text(text)

final = path.read_text()
required = [
    "'point_tier_reserve|5000'",
    "'point_tier_claim|5000'",
    "'points': -5000",
    "'points': 5050",
    "'bonusPoints': 50",
    '5,000 نقطة مستقطعة وجاهزة للاستلام + هدية 50',
    "dedaText('استلم 5,000 + 50', 'Claim 5,000 + 50')",
    "badgeMaxWidth: 138",
    "'$totalPoints نقطة'",
    'intervalDuration: const Duration(milliseconds: 500)',
    'setState(() => _autoFollowMap = false);',
    "class _DedaCleanPageTransitionsBuilder extends PageTransitionsBuilder",
    'generalManagerBonusPoints = 1000000',
]
missing = [marker for marker in required if marker not in final]
if missing:
    raise SystemExit(f'missing required corrected markers: {missing}')
for forbidden in ["'3 / 16'", "'points': 50,\n          'type': 'point_tier'"]:
    if forbidden in final:
        raise SystemExit(f'forbidden legacy marker remains: {forbidden}')
print('DEDA stage-one deduct/claim correction applied successfully')
