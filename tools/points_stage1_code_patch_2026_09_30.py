from pathlib import Path
import re

MAIN = Path('lib/main.dart')
BUILD = Path('.github/workflows/build.yml')

text = MAIN.read_text()

old_fields = """class _DedaAccountHubPageState extends State<DedaAccountHubPage> {\n  bool _pointsExpanded = false;\n  final Set<int> _openedPointTiers = <int>{};\n\n  String get _pointTierPrefsKey =>\n      'deda_opened_point_tiers_${DedaPreferences.phone.trim()}';\n"""
new_fields = """class _DedaAccountHubPageState extends State<DedaAccountHubPage> {\n  bool _pointsExpanded = false;\n  final Set<int> _openedPointTiers = <int>{};\n\n  String get _pointTierPrefsKey =>\n      'deda_opened_point_tiers_${DedaPreferences.phone.trim()}';\n\n  String _rewardAccountDigits() {\n    var digits = DedaBackend.accountKeyForPhone(DedaPreferences.phone);\n    if (digits.startsWith('00964')) {\n      digits = digits.substring(2);\n    } else if (digits.startsWith('07') && digits.length == 11) {\n      digits = '964${digits.substring(1)}';\n    } else if (digits.startsWith('7') && digits.length == 10) {\n      digits = '964$digits';\n    }\n    return digits;\n  }\n\n  // Stage 1 uses a deterministic one-to-one transformation of the stable\n  // DEDA account phone key. The 14-character base62 body is injective for\n  // the supported phone-number domain; the two-character prefix guarantees\n  // every reward code visibly mixes letters and digits. The full 16\n  // characters are never shown at stage 1.\n  String _rewardCode16() {\n    const alphabet =\n        '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';\n    final digits = _rewardAccountDigits();\n    final value = BigInt.tryParse(digits) ?? BigInt.zero;\n    final base = BigInt.from(alphabet.length);\n    final modulus = base.pow(14);\n    final multiplier = BigInt.parse('6364136223846793005');\n    final increment = BigInt.parse('1442695040888963407');\n    final mixed = (value * multiplier + increment) % modulus;\n\n    var cursor = mixed;\n    final encoded = List<String>.filled(14, '0');\n    for (var i = encoded.length - 1; i >= 0; i--) {\n      encoded[i] = alphabet[(cursor % base).toInt()];\n      cursor ~/= base;\n    }\n\n    const letters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';\n    final prefixLetter = letters[(mixed % BigInt.from(26)).toInt()];\n    final prefixDigit =\n        ((mixed ~/ BigInt.from(26)) % BigInt.from(10)).toString();\n    return '$prefixLetter$prefixDigit${encoded.join()}';\n  }\n\n  String get _rewardStageOnePart {\n    final code = _rewardCode16();\n    return code.length >= 3 ? code.substring(0, 3) : '---';\n  }\n"""
if old_fields not in text:
    raise SystemExit('account hub field marker not found')
text = text.replace(old_fields, new_fields, 1)

open_pattern = re.compile(
    r"  Future<void> _openPointTier\(int threshold, int totalPoints\) async \{.*?\n  \}\n\n  String _formatPointTier",
    re.S,
)
new_open = """  Future<void> _openPointTier(int threshold, int totalPoints) async {\n    if (threshold != 5000) {\n      ScaffoldMessenger.of(context).showSnackBar(\n        SnackBar(\n          content: Text(\n            dedaText(\n              'نثبت المرحلة الأولى أولاً، وبعد نجاحها نفعّل هذه البطاقة بالتسلسل.',\n              'Stage one is being completed first; this card will unlock in sequence.',\n            ),\n            textAlign: TextAlign.center,\n          ),\n        ),\n      );\n      return;\n    }\n\n    if (totalPoints < threshold) {\n      final remaining = threshold - totalPoints;\n      ScaffoldMessenger.of(context).showSnackBar(\n        SnackBar(\n          content: Text(\n            dedaText(\n              'تحتاج $remaining نقطة إضافية لفتح هذه البطاقة.',\n              'You need $remaining more points to open this card.',\n            ),\n            textAlign: TextAlign.center,\n          ),\n        ),\n      );\n      return;\n    }\n    if (_openedPointTiers.contains(threshold)) return;\n\n    setState(() => _openedPointTiers.add(threshold));\n    final prefs = await SharedPreferences.getInstance();\n    final ordered = _openedPointTiers.toList()..sort();\n    await prefs.setStringList(\n      _pointTierPrefsKey,\n      ordered.map((value) => value.toString()).toList(),\n    );\n    if (!mounted) return;\n    ScaffoldMessenger.of(context).showSnackBar(\n      SnackBar(\n        content: Text(\n          dedaText(\n            'تم كشف أول 3 خانات من رمزك الخاص.',\n            'The first 3 characters of your private code were revealed.',\n          ),\n          textAlign: TextAlign.center,\n        ),\n      ),\n    );\n  }\n\n  String _formatPointTier"""
text, count = open_pattern.subn(new_open, text, count=1)
if count != 1:
    raise SystemExit(f'open tier function replacement count={count}')

card_pattern = re.compile(
    r"  Widget _pointsTierCard\(\{.*?\n  \}\n\n  Widget _pointsCardsPanel\(int totalPoints\)",
    re.S,
)
new_card = r'''  Widget _rewardStageOneBackFace() {
    const gold = Color(0xFFFFD76A);
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
            const SizedBox(height: 5),
            Text(
              dedaText('الجزء الأول من الرمز', 'First code part'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: gold,
                fontSize: 11.5,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 7),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xCC020914),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: gold, width: 1.5),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x44E8C56C),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: Text(
                  _rewardStageOnePart,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 27,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 4.2,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 7),
            Text(
              dedaText(
                'تم كشف الجزء الأول من رمزك',
                'The first part of your code is revealed',
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 7),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xAA020914),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: gold.withOpacity(0.84)),
              ),
              child: const Text(
                '3 / 16',
                style: TextStyle(
                  color: gold,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(height: 7),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.check_circle_rounded, color: gold, size: 17),
                const SizedBox(width: 5),
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
            const SizedBox(height: 7),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Icon(
                    Icons.arrow_forward_rounded,
                    color: gold,
                    size: 17,
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    dedaText(
                      'واصل جمع النقاط وافتح البطاقة التالية لإكمال الرمز',
                      'Keep collecting points and open the next card to complete the code',
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      height: 1.25,
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

  Widget _pointTierFrontFace({
    required int threshold,
    required int index,
    required bool opened,
    required bool available,
    required bool locked,
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
                    : threshold == 5000
                        ? dedaText(
                            'تفتح عند ${_formatPointTier(threshold)}',
                            'Unlocks at ${_formatPointTier(threshold)}',
                          )
                        : dedaText('بانتظار المرحلة السابقة', 'Previous stage required'),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9.5,
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

  Widget _pointsTierCard({
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
    final firstTier = threshold == 5000;
    final opened = firstTier && _openedPointTiers.contains(5000);
    final lockedByPoints = totalPoints < threshold;
    final available = firstTier && !opened && !lockedByPoints;

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
            duration: const Duration(milliseconds: 520),
            switchInCurve: Curves.easeInOutCubic,
            switchOutCurve: Curves.easeInOutCubic,
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
                ? _rewardStageOneBackFace()
                : _pointTierFrontFace(
                    threshold: threshold,
                    index: index,
                    opened: opened,
                    available: available,
                    locked: lockedByPoints || !firstTier,
                  ),
          ),
        ),
      ),
    );
  }

  Widget _pointsCardsPanel(int totalPoints)'''
text, count = card_pattern.subn(new_card, text, count=1)
if count != 1:
    raise SystemExit(f'points tier card replacement count={count}')

# Avoid analyzer warnings from retained signature parameters while preserving
# the current front-card call shape for the later stages.
text = text.replace(
    """  Widget _pointTierFrontFace({\n    required int threshold,\n    required int index,\n    required bool opened,\n    required bool available,\n    required bool locked,\n  }) {""",
    """  Widget _pointTierFrontFace({\n    required int threshold,\n    required int index,\n    required bool available,\n  }) {""",
    1,
)
text = text.replace(
    """                : _pointTierFrontFace(\n                    threshold: threshold,\n                    index: index,\n                    opened: opened,\n                    available: available,\n                    locked: lockedByPoints || !firstTier,\n                  ),""",
    """                : _pointTierFrontFace(\n                    threshold: threshold,\n                    index: index,\n                    available: available,\n                  ),""",
    1,
)

MAIN.write_text(text)

build = BUILD.read_text()
branch_line = '      - points-stage1-code-2026-09-30\n'
if branch_line not in build:
    marker = '      - nav-hotfix-build227-2026-09-30\n'
    if marker not in build:
        raise SystemExit('build workflow branch marker not found')
    build = build.replace(marker, marker + branch_line, 1)
    BUILD.write_text(build)

# Basic invariants before the workflow runs Flutter analyze.
final = MAIN.read_text()
checks = [
    'String _rewardCode16()',
    "threshold != 5000",
    "'3 / 16'",
    "_rewardStageOneBackFace()",
    'Matrix4.identity()',
]
missing = [item for item in checks if item not in final]
if missing:
    raise SystemExit(f'missing expected markers: {missing}')
print('DEDA points stage 1 patch applied successfully')
