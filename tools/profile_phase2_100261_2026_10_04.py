from pathlib import Path

path = Path('lib/main.dart')
text = path.read_text(encoding='utf-8')

marker = '// DEDA_PROFILE_PHASE2_100261'
if marker in text:
    print('profile phase 2 already applied')
    raise SystemExit(0)

social_marker = 'class DedaSocialHubPage extends StatefulWidget {'
if social_marker not in text:
    raise SystemExit('100260 social hub must be applied before 100261 profile phase 2')

old_child = '''          // Keep the existing account/profile screen fully intact in phase 1.\n          DedaAccountHubPage(),'''
new_child = '''          // DEDA_PROFILE_PHASE2_100261\n          DedaProfilePhase2Page(),'''
if text.count(old_child) != 1:
    raise SystemExit(f'expected exactly one phase1 profile child, found {text.count(old_child)}')
text = text.replace(old_child, new_child, 1)

insert_at = text.index(social_marker)
phase2_code = r'''
// DEDA_PROFILE_PHASE2_100261
// Visual profile upgrade based on the approved DEDA reference. Friend backend,
// request handling and decoration purchases intentionally remain out of scope.
class DedaProfilePhase2Page extends StatefulWidget {
  const DedaProfilePhase2Page({super.key});

  @override
  State<DedaProfilePhase2Page> createState() => _DedaProfilePhase2PageState();
}

class _DedaProfilePhase2PageState extends State<DedaProfilePhase2Page> {
  static const Color _navy = Color(0xFF0A477E);
  static const Color _deepNavy = Color(0xFF062E57);
  static const Color _gold = Color(0xFFFFD76A);
  static const Color _cream = Color(0xFFF8FAF2);

  String get _dedaId =>
      DedaBackend.personalShareIdForPhone(DedaPreferences.phone).trim();

  DedaAccountType get _accountType =>
      DedaPreferences.accountType ?? DedaAccountType.user;

  @override
  void initState() {
    super.initState();
    unawaited(DedaDiamondsWallet.load());
    unawaited(DedaTaskEngine.initializeForCurrentAccount());
  }

  Future<void> _openEditProfile() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const DedaEditProfilePage()),
    );
    if (changed == true && mounted) setState(() {});
  }

  Future<void> _copyDedaId() async {
    final id = _dedaId;
    if (id.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: id));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          dedaText('تم نسخ معرف DEDA', 'DEDA ID copied'),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  void _showPhase2Notice(String ar, String en) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          dedaText(ar, en),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _cream,
      appBar: AppBar(
        centerTitle: true,
        elevation: 0,
        foregroundColor: Colors.white,
        backgroundColor: _navy,
        title: Text(
          dedaText('ملفي', 'My profile'),
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: <Widget>[
          IconButton(
            tooltip: dedaText('نسخ المعرف', 'Copy ID'),
            onPressed: _copyDedaId,
            icon: const Icon(Icons.copy_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.zero,
        children: <Widget>[
          _profileBackdrop(),
          Transform.translate(
            offset: const Offset(0, -22),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: <Widget>[
                  _profileHeroCard(),
                  const SizedBox(height: 12),
                  _statsRow(),
                  const SizedBox(height: 14),
                  _featureGrid(),
                  const SizedBox(height: 14),
                  _bioCard(),
                  const SizedBox(height: 22),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _profileBackdrop() {
    return Container(
      height: 165,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: <Color>[
            Color(0xFF0C528C),
            Color(0xFF0A477E),
            Color(0xFF0A365F),
          ],
        ),
      ),
      child: Stack(
        children: <Widget>[
          Positioned(
            right: -42,
            top: -35,
            child: Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.06),
              ),
            ),
          ),
          Positioned(
            left: -30,
            bottom: -55,
            child: Container(
              width: 170,
              height: 170,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _gold.withOpacity(0.10),
              ),
            ),
          ),
          Positioned.fill(
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: 20),
                child: Column(
                  children: <Widget>[
                    const Icon(
                      Icons.location_on_rounded,
                      color: _gold,
                      size: 27,
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'DEDA - ${dedaText('الدليل الدقيق', 'The Accurate Guide')}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _profileHeroCard() {
    final background = dedaProfileBackgroundColors(
      DedaPreferences.profileBackgroundStyle,
    );
    final frameColors = <Color>[
      const Color(0xFFD4A72C),
      const Color(0xFF1B8F6C),
      const Color(0xFF9A4E72),
    ];
    final frame = frameColors[
        DedaPreferences.profileFrameStyle.abs() % frameColors.length];
    final name = DedaPreferences.userName.trim().isEmpty
        ? dedaText('مستخدم DEDA', 'DEDA user')
        : DedaPreferences.userName.trim();
    final id = _dedaId.isEmpty ? '@DEDA' : _dedaId;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: <Color>[
            Colors.white,
            background.first.withOpacity(0.95),
            background.last.withOpacity(0.82),
          ],
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: _gold.withOpacity(0.72), width: 1.3),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x26062E57),
            blurRadius: 18,
            offset: Offset(0, 7),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 360;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              _avatar(frame, compact ? 92 : 104),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.start,
                      style: const TextStyle(
                        color: _deepNavy,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Flexible(
                            child: Text(
                              id,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF536577),
                                fontSize: 15.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(width: 7),
                          InkWell(
                            onTap: _copyDedaId,
                            borderRadius: BorderRadius.circular(12),
                            child: const Padding(
                              padding: EdgeInsets.all(4),
                              child: Icon(
                                Icons.copy_rounded,
                                size: 18,
                                color: _navy,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      dedaText(
                        'عضو في مجتمع DEDA',
                        'Member of the DEDA community',
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF66737B),
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 11),
                    Wrap(
                      alignment: WrapAlignment.start,
                      spacing: 7,
                      runSpacing: 7,
                      children: <Widget>[
                        _miniPill(
                          icon: Icons.verified_rounded,
                          label: dedaText('عضو DEDA', 'DEDA member'),
                          color: const Color(0xFFB47A05),
                          surface: const Color(0xFFFFF1C3),
                        ),
                        _miniPill(
                          icon: Icons.person_outline_rounded,
                          label: dedaAccountTypeLabel(_accountType),
                          color: const Color(0xFF14614A),
                          surface: const Color(0xFFE4F5ED),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _avatar(Color frame, double size) {
    return SizedBox(
      width: size,
      height: size + 10,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          Container(
            width: size,
            height: size,
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: <Color>[
                  frame.withOpacity(0.98),
                  Colors.white,
                  frame.withOpacity(0.82),
                ],
              ),
              boxShadow: const <BoxShadow>[
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 11,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
              ),
              child: DedaAvatarPortrait(
                style: DedaPreferences.profileAvatarStyle,
                size: size - 16,
              ),
            ),
          ),
          Positioned(
            right: 3,
            top: 4,
            child: Container(
              width: 17,
              height: 17,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF12B76A),
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
          ),
          Positioned(
            right: -1,
            bottom: 1,
            child: Material(
              color: _navy,
              shape: const CircleBorder(),
              elevation: 3,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _openEditProfile,
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(
                    Icons.edit_rounded,
                    color: Colors.white,
                    size: 17,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniPill({
    required IconData icon,
    required String label,
    required Color color,
    required Color surface,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statsRow() {
    return Row(
      children: <Widget>[
        Expanded(
          child: ValueListenableBuilder<int>(
            valueListenable: DedaDiamondsWallet.balanceNotifier,
            builder: (context, diamonds, _) => _statCard(
              icon: Icons.diamond_rounded,
              value: '$diamonds',
              label: dedaText('الماسات', 'Diamonds'),
              color: const Color(0xFF7639D4),
              surface: const Color(0xFFF1E8FF),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _statCard(
            icon: Icons.people_alt_rounded,
            value: '0',
            label: dedaText('الأصدقاء', 'Friends'),
            color: const Color(0xFF079466),
            surface: const Color(0xFFE2F8EF),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ValueListenableBuilder<int>(
            valueListenable: DedaTaskEngine.totalPointsNotifier,
            builder: (context, points, _) => _statCard(
              icon: Icons.star_rounded,
              value: '$points',
              label: dedaText('النقاط', 'Points'),
              color: const Color(0xFFC97D00),
              surface: const Color(0xFFFFF2CE),
            ),
          ),
        ),
      ],
    );
  }

  Widget _statCard({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
    required Color surface,
  }) {
    return Container(
      constraints: const BoxConstraints(minHeight: 104),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: color.withOpacity(0.22)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x12062E57),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(icon, color: color, size: 25),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              maxLines: 1,
              style: const TextStyle(
                color: _deepNavy,
                fontWeight: FontWeight.w900,
                fontSize: 21,
              ),
            ),
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF43566A),
              fontWeight: FontWeight.w800,
              fontSize: 11.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _featureGrid() {
    return Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: _featureCard(
                icon: Icons.edit_rounded,
                title: dedaText('تعديل الملف', 'Edit profile'),
                subtitle: dedaText('بياناتك وشخصيتك', 'Your profile details'),
                colors: const <Color>[Color(0xFF0877C9), Color(0xFF07579B)],
                onTap: _openEditProfile,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _featureCard(
                icon: Icons.photo_library_rounded,
                title: dedaText('الصور', 'Photos'),
                subtitle: dedaText('صورتك وهويتك', 'Avatar and identity'),
                colors: const <Color>[Color(0xFF914BE1), Color(0xFF6530B7)],
                onTap: _openEditProfile,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: <Widget>[
            Expanded(
              child: _featureCard(
                icon: Icons.workspace_premium_rounded,
                title: dedaText('الشارات', 'Badges'),
                subtitle: dedaText('شاراتك وإنجازاتك', 'Badges and achievements'),
                colors: const <Color>[Color(0xFF0BB97B), Color(0xFF07885D)],
                onTap: () => _showPhase2Notice(
                  'تم تجهيز مكان الشارات. سيتم ربطها بالإنجازات في مرحلتها.',
                  'The badges area is ready and will be linked to achievements in its dedicated phase.',
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _featureCard(
                icon: Icons.favorite_rounded,
                title: dedaText('المفضلة', 'Favorites'),
                subtitle: dedaText('أماكنك المفضلة', 'Your favorite places'),
                colors: const <Color>[Color(0xFFF3A411), Color(0xFFD77D00)],
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const SavedPlacesPage(showFavorites: true),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: <Widget>[
            Expanded(
              child: _featureCard(
                icon: Icons.history_rounded,
                title: dedaText('نشاطاتي', 'My activity'),
                subtitle: dedaText('الأماكن الأخيرة', 'Recent places'),
                colors: const <Color>[Color(0xFFE8465D), Color(0xFFC92A44)],
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const SavedPlacesPage(showFavorites: false),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _featureCard(
                icon: Icons.visibility_rounded,
                title: dedaText('عرض الملف العام', 'Public profile'),
                subtitle: dedaText('كما سيراه أصدقاؤك', 'As friends will see it'),
                colors: const <Color>[Color(0xFF17A8B5), Color(0xFF087F91)],
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const DedaPublicProfilePreviewPage(),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _featureCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required List<Color> colors,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Ink(
          height: 112,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: colors,
            ),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withOpacity(0.55)),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: colors.last.withOpacity(0.20),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.18),
                  border: Border.all(color: Colors.white.withOpacity(0.38)),
                ),
                child: Icon(icon, color: Colors.white, size: 26),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.86),
                        fontWeight: FontWeight.w600,
                        fontSize: 11.5,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_left_rounded,
                color: Colors.white,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bioCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE2D9BC)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  dedaText('نبذة عني', 'About me'),
                  style: const TextStyle(
                    color: _deepNavy,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF1FF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Icon(Icons.edit_rounded, size: 15, color: _navy),
                    const SizedBox(width: 4),
                    Text(
                      dedaText('لاحقًا', 'Later'),
                      style: const TextStyle(
                        color: _navy,
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF3F6FB),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Text(
              dedaText(
                'عضو في مجتمع DEDA – الدليل الدقيق. سيتم تفعيل كتابة النبذة الشخصية ضمن مرحلة الملف الاجتماعي دون إضافة بيانات وهمية.',
                'Member of the DEDA community. Personal bio editing will be enabled in the social-profile stage without adding fake information.',
              ),
              textAlign: TextAlign.start,
              style: const TextStyle(
                color: Color(0xFF495C6B),
                fontWeight: FontWeight.w600,
                fontSize: 13,
                height: 1.55,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class DedaPublicProfilePreviewPage extends StatelessWidget {
  const DedaPublicProfilePreviewPage({super.key});

  static const Color _navy = Color(0xFF0A477E);
  static const Color _deepNavy = Color(0xFF062E57);
  static const Color _gold = Color(0xFFFFD76A);

  String get _dedaId =>
      DedaBackend.personalShareIdForPhone(DedaPreferences.phone).trim();

  @override
  Widget build(BuildContext context) {
    final name = DedaPreferences.userName.trim().isEmpty
        ? dedaText('مستخدم DEDA', 'DEDA user')
        : DedaPreferences.userName.trim();
    final id = _dedaId.isEmpty ? '@DEDA' : _dedaId;
    final background = dedaProfileBackgroundColors(
      DedaPreferences.profileBackgroundStyle,
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF2),
      appBar: AppBar(
        centerTitle: true,
        foregroundColor: Colors.white,
        backgroundColor: _navy,
        title: Text(
          dedaText('معاينة الملف العام', 'Public profile preview'),
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: <Widget>[
          Container(
            padding: const EdgeInsets.fromLTRB(18, 24, 18, 22),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
                colors: <Color>[
                  Colors.white,
                  background.first,
                  background.last,
                ],
              ),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: _gold, width: 1.2),
              boxShadow: const <BoxShadow>[
                BoxShadow(
                  color: Color(0x22062E57),
                  blurRadius: 18,
                  offset: Offset(0, 7),
                ),
              ],
            ),
            child: Column(
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: <Color>[_gold, Colors.white, _navy],
                    ),
                  ),
                  child: DedaAvatarPortrait(
                    style: DedaPreferences.profileAvatarStyle,
                    size: 112,
                  ),
                ),
                const SizedBox(height: 15),
                Text(
                  name,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: _deepNavy,
                    fontWeight: FontWeight.w900,
                    fontSize: 25,
                  ),
                ),
                const SizedBox(height: 6),
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: Text(
                    id,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF536577),
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF1C3),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Text(
                    dedaText('عضو DEDA', 'DEDA member'),
                    style: const TextStyle(
                      color: Color(0xFFB47A05),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: const Color(0xFFE0E6EA)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const Icon(Icons.lock_outline_rounded, color: _navy),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        dedaText(
                          'هذه هي المعلومات التي سيراها الصديق فقط',
                          'This is the information a friend will be able to see',
                        ),
                        style: const TextStyle(
                          color: _deepNavy,
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  dedaText(
                    'الاسم • معرف DEDA • الشخصية • الإطار • الخلفية • الشارات والزينة. رقم الهاتف والموقع والبيانات الخاصة لا تظهر هنا.',
                    'Name • DEDA ID • avatar • frame • background • badges and decorations. Phone, location and private data are never shown here.',
                  ),
                  style: const TextStyle(
                    color: Color(0xFF546674),
                    fontWeight: FontWeight.w600,
                    fontSize: 13.5,
                    height: 1.55,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

'''

text = text[:insert_at] + phase2_code + text[insert_at:]
path.write_text(text, encoding='utf-8')
print('applied DEDA profile phase 2 for build 100261')
