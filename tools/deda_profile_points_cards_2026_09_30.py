from pathlib import Path

path = Path('lib/main.dart')
text = path.read_text(encoding='utf-8')

state_marker = """class _DedaAccountHubPageState extends State<DedaAccountHubPage> {
  String get _personalDedaId =>
"""
state_replacement = """class _DedaAccountHubPageState extends State<DedaAccountHubPage> {
  bool _pointsExpanded = false;
  final Set<int> _openedPointTiers = <int>{};

  String get _pointTierPrefsKey =>
      'deda_opened_point_tiers_${DedaPreferences.phone.trim()}';

  @override
  void initState() {
    super.initState();
    _loadOpenedPointTiers();
  }

  Future<void> _loadOpenedPointTiers() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_pointTierPrefsKey) ?? const <String>[];
    final loaded = raw.map(int.tryParse).whereType<int>().toSet();
    if (!mounted) return;
    setState(() {
      _openedPointTiers
        ..clear()
        ..addAll(loaded);
    });
  }

  Future<void> _openPointTier(int threshold, int totalPoints) async {
    if (totalPoints < threshold) {
      final remaining = threshold - totalPoints;
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
    if (_openedPointTiers.contains(threshold)) return;
    setState(() => _openedPointTiers.add(threshold));
    final prefs = await SharedPreferences.getInstance();
    final ordered = _openedPointTiers.toList()..sort();
    await prefs.setStringList(
      _pointTierPrefsKey,
      ordered.map((value) => value.toString()).toList(),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          dedaText(
            'تم فتح بطاقة ${_formatPointTier(threshold)} نقطة بنجاح.',
            '${_formatPointTier(threshold)} point card opened successfully.',
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  String _formatPointTier(int value) {
    final digits = value.toString();
    final out = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
      out.write(digits[i]);
    }
    return out.toString();
  }

  String get _personalDedaId =>
"""
if text.count(state_marker) != 1:
    raise SystemExit(f'Expected account hub state marker once, found {text.count(state_marker)}')
text = text.replace(state_marker, state_replacement, 1)

profile_marker = """  Widget _profileHero(DedaAccountType type) {
"""
profile_methods = """  Widget _pointsTierCard({
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
    final stageAr = <String>['الأولى', 'الثانية', 'الثالثة', 'الرابعة', 'الخامسة'][index];
    final locked = totalPoints < threshold;
    final opened = _openedPointTiers.contains(threshold);
    final available = !locked && !opened;
    const gold = Color(0xFFFFD76A);
    const deepGold = Color(0xFFB88418);

    return Semantics(
      button: true,
      label: dedaText(
        'بطاقة ${_formatPointTier(threshold)} نقطة، المرحلة $stageAr',
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
          child: Stack(
            children: [
              Positioned(
                top: 0,
                left: 0,
                child: Icon(Icons.diamond_outlined, size: 13, color: gold.withOpacity(0.90)),
              ),
              Positioned(
                top: 0,
                right: 0,
                child: Icon(Icons.diamond_outlined, size: 13, color: gold.withOpacity(0.90)),
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
                        colors: [
                          gold.withOpacity(0.36),
                          Colors.transparent,
                        ],
                      ),
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        const Icon(
                          Icons.shield_rounded,
                          size: 70,
                          color: gold,
                        ),
                        Container(
                          width: 37,
                          height: 37,
                          decoration: BoxDecoration(
                            color: opened
                                ? const Color(0xFFFFF1A8)
                                : const Color(0xFF081B31),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white.withOpacity(0.82)),
                          ),
                          child: Icon(
                            opened
                                ? Icons.workspace_premium_rounded
                                : available
                                    ? Icons.lock_open_rounded
                                    : Icons.lock_rounded,
                            size: 23,
                            color: opened
                                ? const Color(0xFF8A5D00)
                                : gold,
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
                      opened
                          ? dedaText('تم فتح البطاقة', 'Card opened')
                          : available
                              ? dedaText('اضغط للفتح', 'Tap to open')
                              : dedaText(
                                  'تفتح عند ${_formatPointTier(threshold)}',
                                  'Unlocks at ${_formatPointTier(threshold)}',
                                ),
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
          ),
        ),
      ),
    );
  }

  Widget _pointsCardsPanel(int totalPoints) {
    const thresholds = <int>[5000, 10000, 15000, 20000, 25000];
    return AnimatedSize(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      child: !_pointsExpanded
          ? const SizedBox.shrink()
          : Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFF8FBF5), Color(0xFFF2F7EE)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: const Color(0xFFD8E3D4)),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x11000000),
                    blurRadius: 12,
                    offset: Offset(0, 5),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.swipe_rounded,
                        color: Color(0xFF6A735F),
                        size: 19,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          dedaText(
                            'مرّر البطاقات من اليسار إلى اليمين',
                            'Swipe cards from left to right',
                          ),
                          textAlign: DedaLanguageState.isArabic
                              ? TextAlign.right
                              : TextAlign.left,
                          style: const TextStyle(
                            color: Color(0xFF687169),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 9),
                  SizedBox(
                    height: 237,
                    child: Directionality(
                      textDirection: TextDirection.ltr,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        itemCount: thresholds.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 10),
                        itemBuilder: (context, index) => _pointsTierCard(
                          threshold: thresholds[index],
                          index: index,
                          totalPoints: totalPoints,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _profileHero(DedaAccountType type) {
"""
if text.count(profile_marker) != 1:
    raise SystemExit(f'Expected profile hero marker once, found {text.count(profile_marker)}')
text = text.replace(profile_marker, profile_methods, 1)

old_points = """            ValueListenableBuilder<int>(
              valueListenable: DedaTaskEngine.totalPointsNotifier,
              builder: (context, totalPoints, _) {
                return _sectionCard(
                  icon: Icons.star_rounded,
                  iconColor: const Color(0xFFE2A400),
                  title: dedaText('النقاط', 'Points'),
                  subtitle: dedaText(
                    'رصيدك الحالي: $totalPoints نقطة',
                    'Current balance: $totalPoints points',
                  ),
                  badgeText: totalPoints.toString(),
                  onTap: () {
                    showDialog<void>(
                      context: context,
                      builder: (dialogContext) => AlertDialog(
                        title: Text(dedaText('النقاط', 'Points')),
                        content: Text(
                          dedaText(
                            'رصيدك الحالي هو $totalPoints نقطة. تضاف 5 نقاط لكل مهمة مكتملة و5 نقاط لكل إجابة مرورية صحيحة.',
                            'Your current balance is $totalPoints points. You earn 5 points per completed task and 5 points per correct traffic answer.',
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(dialogContext),
                            child: Text(dedaText('حسنًا', 'OK')),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
"""
new_points = """            ValueListenableBuilder<int>(
              valueListenable: DedaTaskEngine.totalPointsNotifier,
              builder: (context, totalPoints, _) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _sectionCard(
                      icon: Icons.star_rounded,
                      iconColor: const Color(0xFFE2A400),
                      title: dedaText('النقاط', 'Points'),
                      subtitle: dedaText(
                        'رصيدك الحالي: $totalPoints نقطة',
                        'Current balance: $totalPoints points',
                      ),
                      badgeText: totalPoints.toString(),
                      onTap: () {
                        setState(() => _pointsExpanded = !_pointsExpanded);
                      },
                    ),
                    _pointsCardsPanel(totalPoints),
                  ],
                );
              },
            ),
"""
if text.count(old_points) != 1:
    raise SystemExit(f'Expected old points block once, found {text.count(old_points)}')
text = text.replace(old_points, new_points, 1)

path.write_text(text, encoding='utf-8')
print('Applied expandable DEDA profile point cards successfully.')
