from pathlib import Path
import re

MAIN = Path('lib/main.dart')
text = MAIN.read_text()

# 1) Reward claim UI/state for the first 5,000-point card.
field_marker = "  final Set<int> _openedPointTiers = <int>{};\n"
field_replacement = (
    field_marker
    + "  bool _stageOneRewardClaimed = false;\n"
    + "  bool _stageOneRewardClaiming = false;\n"
)
if '_stageOneRewardClaimed' not in text:
    if field_marker not in text:
        raise SystemExit('stage one field marker not found')
    text = text.replace(field_marker, field_replacement, 1)

load_pattern = re.compile(
    r"  Future<void> _loadOpenedPointTiers\(\) async \{.*?\n  \}\n\n  Future<void> _openPointTier",
    re.S,
)
load_replacement = r'''  Future<void> _loadOpenedPointTiers() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_pointTierPrefsKey) ?? const <String>[];
    final loaded = raw.map(int.tryParse).whereType<int>().toSet();

    var rewardClaimed = false;
    final accountKey = DedaTaskEngine._accountKey();
    if (accountKey.isNotEmpty) {
      final state = await DedaTaskEngine._readState(prefs, accountKey);
      final awardsRaw = state['awards'];
      if (awardsRaw is Map) {
        rewardClaimed = awardsRaw.containsKey('point_tier|5000');
      }
    }

    if (!mounted) return;
    setState(() {
      _openedPointTiers
        ..clear()
        ..addAll(loaded);
      _stageOneRewardClaimed = rewardClaimed;
    });
  }

  Future<void> _claimStageOneReward() async {
    if (_stageOneRewardClaimed ||
        _stageOneRewardClaiming ||
        !_openedPointTiers.contains(5000)) {
      return;
    }

    setState(() => _stageOneRewardClaiming = true);
    var awardedNow = false;
    try {
      final accountKey = DedaTaskEngine._accountKey();
      if (accountKey.isEmpty) {
        throw StateError('points-account-not-ready');
      }

      final prefs = await SharedPreferences.getInstance();
      final state = await DedaTaskEngine._readState(prefs, accountKey);
      final awards = Map<String, dynamic>.from(state['awards'] as Map);
      final ledger = List<dynamic>.from(state['ledger'] as List);
      const awardId = 'point_tier|5000';

      if (!awards.containsKey(awardId)) {
        final award = <String, dynamic>{
          'id': awardId,
          'points': 50,
          'type': 'point_tier',
          'event': 'stage_one_reward_claimed',
          'threshold': 5000,
          'createdAt': DateTime.now().toUtc().toIso8601String(),
        };
        awards[awardId] = award;
        ledger.add(award);
        if (ledger.length > DedaTaskEngine._maxLedgerEntries) {
          ledger.removeRange(
            0,
            ledger.length - DedaTaskEngine._maxLedgerEntries,
          );
        }
        state['awards'] = awards;
        state['ledger'] = ledger;
        await DedaTaskEngine._writeState(prefs, accountKey, state);
        awardedNow = true;
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
            awardedNow
                ? dedaText(
                    'تم استرداد نقاطك وإضافة 50 نقطة مكافأة إلى رصيدك.',
                    'Your points were restored and 50 bonus points were added.',
                  )
                : dedaText(
                    'تم استرداد مكافأة هذه البطاقة مسبقًا.',
                    'This card reward was already claimed.',
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
              'تعذر استرداد النقاط الآن. حاول مرة أخرى.',
              'Could not claim the points right now. Please try again.',
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
  }

  Future<void> _openPointTier'''
text, count = load_pattern.subn(load_replacement, text, count=1)
if count != 1:
    raise SystemExit(f'load/reward replacement count={count}')

# 2 + 3) Remove the visible 3/16 clue, add the 5,000 + 50 claim control,
# and compact the back face so every line including "تم الفتح" is visible.
back_pattern = re.compile(
    r"  Widget _rewardStageOneBackFace\(\) \{.*?\n  \}\n\n  Widget _pointTierFrontFace",
    re.S,
)
back_replacement = r'''  Widget _rewardStageOneBackFace() {
    const gold = Color(0xFFFFD76A);
    const deep = Color(0xFF020914);
    final claimLabel = _stageOneRewardClaimed
        ? dedaText('تم الاسترداد +50', 'Claimed +50')
        : dedaText('استرد نقاطك 5,000 + 50', 'Restore 5,000 + 50');

    return Stack(
      key: const ValueKey<String>('reward-stage1-back'),
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
              dedaText('الجزء الأول من الرمز', 'First code part'),
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
                  _rewardStageOnePart,
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
            SizedBox(
              height: 35,
              child: Material(
                color: _stageOneRewardClaimed
                    ? const Color(0xFF173F31)
                    : deep,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: _stageOneRewardClaimed || _stageOneRewardClaiming
                      ? null
                      : _claimStageOneReward,
                  child: Container(
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: gold, width: 1.2),
                    ),
                    child: _stageOneRewardClaiming
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
                    dedaText(
                      'واصل جمع النقاط وافتح البطاقة التالية لإكمال الرمز',
                      'Keep collecting points and open the next card to complete the code',
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

  Widget _pointTierFrontFace'''
text, count = back_pattern.subn(back_replacement, text, count=1)
if count != 1:
    raise SystemExit(f'back face replacement count={count}')

# 4) Keep the complete Arabic points unit visible in the upper balance card.
old_balance = "'رصيدك الحالي: $totalPoints نقطة'"
new_balance = "'رصيدك: $totalPoints نقطة'"
if old_balance not in text:
    raise SystemExit('points balance subtitle marker not found')
text = text.replace(old_balance, new_balance, 1)

# 5) Eliminate outgoing-child overlap/ghosting during the card flip.
switch_marker = """          child: AnimatedSwitcher(\n            duration: const Duration(milliseconds: 520),\n            switchInCurve: Curves.easeInOutCubic,\n            switchOutCurve: Curves.easeInOutCubic,\n            transitionBuilder: (child, animation) {"""
switch_replacement = """          child: AnimatedSwitcher(\n            duration: const Duration(milliseconds: 420),\n            switchInCurve: Curves.easeOutCubic,\n            switchOutCurve: Curves.easeInCubic,\n            layoutBuilder: (currentChild, previousChildren) =>\n                currentChild ?? const SizedBox.shrink(),\n            transitionBuilder: (child, animation) {"""
if switch_marker not in text:
    raise SystemExit('animated switcher marker not found')
text = text.replace(switch_marker, switch_replacement, 1)

# Give the compact back face enough vertical room so nothing is clipped.
panel_marker = """                  SizedBox(\n                    height: 237,\n                    child: Directionality("""
panel_replacement = """                  SizedBox(\n                    height: 270,\n                    child: Directionality("""
if panel_marker not in text:
    raise SystemExit('points panel height marker not found')
text = text.replace(panel_marker, panel_replacement, 1)

MAIN.write_text(text)

final = MAIN.read_text()
required = [
    "'استرد نقاطك 5,000 + 50'",
    "'تم الفتح'",
    "'رصيدك: $totalPoints نقطة'",
    "layoutBuilder: (currentChild, previousChildren)",
    "height: 270",
    "'point_tier|5000'",
]
missing = [item for item in required if item not in final]
if missing:
    raise SystemExit(f'missing expected markers: {missing}')

for forbidden in ["'3 / 16'", 'TextOverflow.ellipsis,\n                    style: const TextStyle(\n                      color: Colors.white,\n                      fontSize: 8.6']:
    if forbidden in final:
        raise SystemExit(f'forbidden stage-one marker remains: {forbidden}')

print('DEDA stage one five-fix patch applied successfully')
