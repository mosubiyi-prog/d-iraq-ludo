from pathlib import Path

MAIN = Path('lib/main.dart')
PUBSPEC = Path('pubspec.yaml')
text = MAIN.read_text(encoding='utf-8')
marker = '// DEDA_STYLE_BADGES_FRAMES_100273'
if marker in text:
    print('DEDA 100273 matched badge/frame patch already applied')
    raise SystemExit(0)

if '// DEDA_STYLE_PURCHASE_SEPARATION_100272' not in text:
    raise SystemExit('DEDA 100272 purchase/level separation must exist before 100273')
if '// DEDA_GIFTS_MAIN_UI_100271' not in text:
    raise SystemExit('DEDA 100271 gifts UI marker missing')


def replace_single_class(source: str, declaration: str, replacement: str) -> str:
    start = source.find(declaration)
    if start < 0:
        raise SystemExit(f'class not found: {declaration}')
    end = source.find('\nclass ', start + len(declaration))
    if end < 0:
        raise SystemExit(f'next class not found after: {declaration}')
    return source[:start] + replacement.rstrip() + '\n\n' + source[end + 1:]


def matching_paren_end(source: str, call_start: int) -> int:
    open_pos = source.find('(', call_start)
    if open_pos < 0:
        return -1
    depth = 0
    quote = None
    escaped = False
    for i in range(open_pos, len(source)):
        ch = source[i]
        if quote is not None:
            if escaped:
                escaped = False
            elif ch == '\\':
                escaped = True
            elif ch == quote:
                quote = None
            continue
        if ch in ("'", '"'):
            quote = ch
            continue
        if ch == '(':
            depth += 1
        elif ch == ')':
            depth -= 1
            if depth == 0:
                return i + 1
    return -1


# ---------------------------------------------------------------------------
# 1) Inventory migration: one free pair for new users, preserve any persisted
#    ownership and the currently equipped legacy free frame. Exactly one badge
#    is active at a time.
# ---------------------------------------------------------------------------
inventory_code = r'''class DedaStyleInventory {
  static final ValueNotifier<String> activeBadgeNotifier =
      ValueNotifier<String>('badge_member');

  static String _scope() {
    final key = DedaBackend.accountKeyForPhone(DedaPreferences.phone).trim();
    return key.isEmpty ? DedaPreferences.phone.trim() : key;
  }

  static String _key() => 'deda_style_inventory_v1_${_scope()}';

  static Future<DedaStyleInventorySnapshot> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key());
    final owned = <String>{'frame_0', 'badge_member'};
    var selectedBadge = 'badge_member';

    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          final rawOwned = decoded['owned'];
          final rawActive = decoded['activeBadges'];
          if (rawOwned is List) {
            owned.addAll(rawOwned.map((e) => e.toString()));
          }
          if (rawActive is List) {
            final candidates = rawActive.map((e) => e.toString()).toList();
            for (final id in candidates) {
              if (owned.contains(id) && dedaStyleBadgeIds.contains(id)) {
                selectedBadge = id;
                if (id != 'badge_member') break;
              }
            }
          }
        }
      } catch (_) {}
    }

    // Earlier DEDA builds gave frame 1/2 as free defaults. If one of those is
    // actively equipped during migration, keep that exact frame owned so the
    // update never strips a user's currently visible decoration.
    final legacyFrame = DedaPreferences.profileFrameStyle.clamp(0, 5).toInt();
    if (legacyFrame == 1 || legacyFrame == 2) {
      owned.add('frame_$legacyFrame');
    }

    if (!owned.contains(selectedBadge)) selectedBadge = 'badge_member';
    final active = <String>{selectedBadge};
    activeBadgeNotifier.value = selectedBadge;
    return DedaStyleInventorySnapshot(owned: owned, activeBadges: active);
  }

  static Future<void> _save(DedaStyleInventorySnapshot snapshot) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key(),
      jsonEncode(<String, dynamic>{
        'owned': snapshot.owned.toList()..sort(),
        'activeBadges': snapshot.activeBadges.toList(),
      }),
    );
  }

  static Future<void> addOwned(String itemId) async {
    final current = await load();
    final owned = Set<String>.from(current.owned)..add(itemId);
    await _save(DedaStyleInventorySnapshot(
      owned: owned,
      activeBadges: current.activeBadges,
    ));
  }

  static Future<void> toggleBadge(String badgeId) async {
    final current = await load();
    if (!current.owned.contains(badgeId)) return;
    final active = <String>{badgeId};
    activeBadgeNotifier.value = badgeId;
    await _save(DedaStyleInventorySnapshot(
      owned: current.owned,
      activeBadges: active,
    ));
  }
}

const List<String> dedaStyleBadgeIds = <String>[
  'badge_member',
  'badge_spark',
  'badge_elite',
  'badge_royal',
  'badge_season1',
  'badge_legendary',
];

const List<String> _dedaStyleNamesAr = <String>[
  'عضو DEDA',
  'متألق',
  'نخبوي',
  'ملكي',
  'الموسم الأول',
  'أسطوري',
];

const List<String> _dedaStyleNamesEn = <String>[
  'DEDA member',
  'Spark',
  'Elite',
  'Royal',
  'Season 1',
  'Legendary',
];

const List<int> dedaStylePrices = <int>[0, 100, 200, 150, 300, 200];
const List<bool> dedaStyleUsesDiamonds = <bool>[true, true, false, true, false, true];

String dedaStyleName(int index) {
  final safe = index.clamp(0, 5).toInt();
  return dedaText(_dedaStyleNamesAr[safe], _dedaStyleNamesEn[safe]);
}

String dedaStyleBadgeId(int index) =>
    dedaStyleBadgeIds[index.clamp(0, 5).toInt()];

String dedaStylePriceLabel(int index) {
  final safe = index.clamp(0, 5).toInt();
  final price = dedaStylePrices[safe];
  if (price == 0) return dedaText('مجاني', 'Free');
  return dedaStyleUsesDiamonds[safe] ? '💎 $price' : '🪙 $price';
}

class DedaBadgeAsset extends StatelessWidget {
  final String id;
  final double size;
  const DedaBadgeAsset({super.key, required this.id, required this.size});

  @override
  Widget build(BuildContext context) {
    final index = dedaStyleBadgeIds.indexOf(id).clamp(0, 5).toInt();
    return SizedBox(
      width: size,
      height: size,
      child: Image.asset(
        'assets/deda_style/badge_$index.png',
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
      ),
    );
  }
}'''
text = replace_single_class(text, 'class DedaStyleInventory {', inventory_code)


# ---------------------------------------------------------------------------
# 2) Every profile/friend preview uses the same real artwork frame source.
# ---------------------------------------------------------------------------
framed_avatar_code = r'''class DedaFramedAvatar extends StatelessWidget {
  final int avatarStyle;
  final int frameStyle;
  final double size;
  const DedaFramedAvatar({
    super.key,
    required this.avatarStyle,
    required this.frameStyle,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final safeStyle = frameStyle.clamp(0, 5).toInt();
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: <Widget>[
          Container(
            width: size * 0.54,
            height: size * 0.54,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              boxShadow: const <BoxShadow>[
                BoxShadow(color: Color(0x22000000), blurRadius: 5),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Center(
              child: DedaAvatarPortrait(
                style: avatarStyle,
                size: size * 0.52,
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: Image.asset(
                'assets/deda_style/frame_$safeStyle.png',
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
              ),
            ),
          ),
        ],
      ),
    );
  }
}'''
text = replace_single_class(text, 'class DedaFramedAvatar extends StatelessWidget {', framed_avatar_code)


# ---------------------------------------------------------------------------
# 3) My Profile: keep the gold level pill and place the one active badge beside
#    it as a separate visual item, exactly as agreed.
# ---------------------------------------------------------------------------
profile_state = text.find('class _DedaProfilePhase2PageState')
level_phrase = text.find("'مستوى ذهبي • $profileLevel'", profile_state)
if level_phrase < 0:
    # Formatter/history fallback: English side of the same approved pill.
    level_phrase = text.find("'Gold level • $profileLevel'", profile_state)
if level_phrase >= 0:
    pill_start = text.rfind('_miniPill(', profile_state, level_phrase)
    pill_end = matching_paren_end(text, pill_start)
    if pill_start >= 0 and pill_end > 0:
        comma = text.find(',', pill_end, pill_end + 8)
        if comma >= 0:
            active_badge_widget = r'''
                        ValueListenableBuilder<String>(
                          valueListenable:
                              DedaStyleInventory.activeBadgeNotifier,
                          builder: (context, badgeId, _) => Container(
                            width: 38,
                            height: 38,
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.88),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: const Color(0xFFE5C05A),
                                width: 1.2,
                              ),
                            ),
                            child: DedaBadgeAsset(id: badgeId, size: 34),
                          ),
                        ),'''
            text = text[:comma + 1] + active_badge_widget + text[comma + 1:]


# ---------------------------------------------------------------------------
# 4) Friend public profile: six badge labels, one active badge, exact frame.
#    Phone/private account data remains intentionally absent.
# ---------------------------------------------------------------------------
public_profile_code = r'''class DedaFriendPublicProfilePage extends StatelessWidget {
  final DedaSocialProfile profile;
  const DedaFriendPublicProfilePage({super.key, required this.profile});

  String _badgeLabel(String id) {
    final index = dedaStyleBadgeIds.indexOf(id);
    return index < 0 ? dedaStyleName(0) : dedaStyleName(index);
  }

  @override
  Widget build(BuildContext context) {
    final bg = dedaProfileBackgroundColors(profile.backgroundStyle);
    final activeBadge = profile.badges.isEmpty
        ? 'badge_member'
        : (dedaStyleBadgeIds.contains(profile.badges.first)
            ? profile.badges.first
            : 'badge_member');
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF2),
      appBar: AppBar(
        centerTitle: true,
        foregroundColor: Colors.white,
        backgroundColor: const Color(0xFF0B4D8D),
        title: Text(dedaText('الملف العام', 'Public profile')),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 22),
        children: <Widget>[
          Container(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: bg,
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFE1CB82)),
              boxShadow: const <BoxShadow>[
                BoxShadow(
                  color: Color(0x19062E57),
                  blurRadius: 16,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              children: <Widget>[
                DedaFramedAvatar(
                  avatarStyle: profile.avatarStyle,
                  frameStyle: profile.frameStyle,
                  size: 142,
                ),
                const SizedBox(height: 6),
                Text(
                  profile.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF0B3C6F),
                    fontWeight: FontWeight.w900,
                    fontSize: 23,
                  ),
                ),
                const SizedBox(height: 3),
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      profile.publicId,
                      maxLines: 1,
                      style: const TextStyle(
                        color: Color(0xFF536779),
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFEFB9),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Text(
                        dedaText(
                          '⭐ المستوى ${profile.level}',
                          '⭐ Level ${profile.level}',
                        ),
                        style: const TextStyle(
                          color: Color(0xFF9A6800),
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 48,
                      height: 48,
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.9),
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFFE0BD57)),
                      ),
                      child: DedaBadgeAsset(id: activeBadge, size: 44),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  _badgeLabel(activeBadge),
                  style: const TextStyle(
                    color: Color(0xFF7B5B0A),
                    fontWeight: FontWeight.w900,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFDCE6DC)),
            ),
            child: Text(
              dedaText(
                'هذا هو الملف الشخصي العام الذي يراه الأصدقاء فقط داخل واجهة DEDA. لا تظهر هنا أرقام الهاتف أو إعدادات الحساب الخاصة.',
                'This public personal profile is shown to friends in DEDA. Phone numbers and private account settings are never shown here.',
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF65776C),
                height: 1.35,
                fontWeight: FontWeight.w600,
                fontSize: 12.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}'''
text = replace_single_class(
    text,
    'class DedaFriendPublicProfilePage extends StatelessWidget {',
    public_profile_code,
)


# ---------------------------------------------------------------------------
# 5) Replace the old generic store with six matched luxurious sets. Badge and
#    frame remain separately purchasable/equippable, but are always presented
#    together with the exact same identity and price currency.
# ---------------------------------------------------------------------------
style_start = text.find('class DedaStylePage extends StatefulWidget {')
gifts_marker = text.find('// DEDA_GIFTS_MAIN_UI_100271', style_start)
if style_start < 0 or gifts_marker < 0:
    raise SystemExit('Style page or 100271 gifts marker not found')

style_code = r'''// DEDA_STYLE_BADGES_FRAMES_100273
class DedaStylePage extends StatefulWidget {
  const DedaStylePage({super.key});
  @override
  State<DedaStylePage> createState() => _DedaStylePageState();
}

class _DedaStylePageState extends State<DedaStylePage> {
  DedaSocialProgressSnapshot? _progress;
  DedaStyleInventorySnapshot? _inventory;
  int _diamonds = 0;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final values = await Future.wait<dynamic>(<Future<dynamic>>[
      DedaSocialProgressWallet.load(),
      DedaStyleInventory.load(),
      DedaDiamondsWallet.load(),
    ]);
    if (!mounted) return;
    setState(() {
      _progress = values[0] as DedaSocialProgressSnapshot;
      _inventory = values[1] as DedaStyleInventorySnapshot;
      _diamonds = DedaDiamondsWallet.purchasableBalance;
    });
  }

  Future<bool> _payForIndex(int index) async {
    final price = dedaStylePrices[index];
    if (price <= 0) return true;
    if (dedaStyleUsesDiamonds[index]) {
      return DedaDiamondsWallet.spend(price);
    }
    return DedaSocialProgressWallet.spendCoins(price);
  }

  Future<void> _buyFrame(int index) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final paid = await _payForIndex(index);
      if (!paid) {
        _message(dedaText(
          dedaStyleUsesDiamonds[index]
              ? 'رصيد الماسات غير كافٍ.'
              : 'رصيد عملة DEDA غير كافٍ.',
          'Your balance is not enough.',
        ));
        return;
      }
      await DedaStyleInventory.addOwned('frame_$index');
      await _load();
      _message(dedaText(
        'تم شراء إطار ${dedaStyleName(index)} وأصبح ضمن مقتنياتك.',
        '${dedaStyleName(index)} frame is now owned.',
      ));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _buyBadge(int index) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final paid = await _payForIndex(index);
      if (!paid) {
        _message(dedaText(
          dedaStyleUsesDiamonds[index]
              ? 'رصيد الماسات غير كافٍ.'
              : 'رصيد عملة DEDA غير كافٍ.',
          'Your balance is not enough.',
        ));
        return;
      }
      await DedaStyleInventory.addOwned(dedaStyleBadgeId(index));
      await _load();
      _message(dedaText(
        'تم شراء شارة ${dedaStyleName(index)} وأصبحت ضمن مقتنياتك.',
        '${dedaStyleName(index)} badge is now owned.',
      ));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _equipFrame(int index) async {
    final inventory = _inventory;
    if (inventory == null || !inventory.owned.contains('frame_$index')) return;
    await DedaPreferences.setProfileAppearance(
      avatarStyle: DedaPreferences.profileAvatarStyle,
      frameStyle: index,
      backgroundStyle: DedaPreferences.profileBackgroundStyle,
    );
    DedaProfileAppearanceState.frameNotifier.value = index;
    await dedaEnsurePersonalSocialSession();
    if (mounted) setState(() {});
  }

  Future<void> _activateBadge(int index) async {
    final id = dedaStyleBadgeId(index);
    final inventory = _inventory;
    if (inventory == null || !inventory.owned.contains(id)) return;
    await DedaStyleInventory.toggleBadge(id);
    await _load();
    await dedaEnsurePersonalSocialSession();
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message, textAlign: TextAlign.center)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final progress = _progress;
    final inventory = _inventory;
    if (progress == null || inventory == null) {
      return const Scaffold(
        backgroundColor: Color(0xFFF8FAF2),
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final within = progress.xp % DedaSocialProgressWallet.xpPerLevel;
    final ratio = within / DedaSocialProgressWallet.xpPerLevel;
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF2),
      appBar: AppBar(
        centerTitle: true,
        foregroundColor: Colors.white,
        backgroundColor: const Color(0xFF0B4D8D),
        title: Text(
          dedaText('الشارات والإطارات', 'Badges & Frames'),
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: <Widget>[
          _walletCard(progress, ratio, within),
          const SizedBox(height: 12),
          Text(
            dedaText(
              'مجموعات DEDA المطابقة',
              'Matched DEDA collections',
            ),
            style: const TextStyle(
              color: Color(0xFF0B3C6F),
              fontWeight: FontWeight.w900,
              fontSize: 19,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            dedaText(
              'كل شارة مع إطارها من نفس الهوية. الشراء منفصل، والتفعيل فوري.',
              'Each badge is paired with its matching frame. Purchases are separate and activation is immediate.',
            ),
            style: const TextStyle(
              color: Color(0xFF677987),
              fontWeight: FontWeight.w600,
              fontSize: 12,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 10),
          ...List<Widget>.generate(
            6,
            (index) => _pairCard(index, inventory),
          ),
        ],
      ),
    );
  }

  Widget _walletCard(
    DedaSocialProgressSnapshot progress,
    double ratio,
    int within,
  ) {
    return Container(
      padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: <Color>[Color(0xFF102E59), Color(0xFF164D83)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE0BD57), width: 1.15),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x25062E57),
            blurRadius: 13,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            dedaText('رصيد المشتريات', 'Purchase balance'),
            style: const TextStyle(
              color: Color(0xFFFFDD77),
              fontWeight: FontWeight.w900,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: _balancePill(
                  icon: '💎',
                  value: _diamonds,
                  label: DedaDiamondsWallet.hasGeneralManagerPersonalWallet
                      ? dedaText('ماساتي الشخصية', 'Personal diamonds')
                      : dedaText('الماسات', 'Diamonds'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _balancePill(
                  icon: '🪙',
                  value: progress.coins,
                  label: dedaText('عملة DEDA', 'DEDA coins'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Text(
                dedaText('المستوى ${progress.level}', 'Level ${progress.level}'),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: ratio,
                    minHeight: 7,
                    backgroundColor: Colors.white24,
                    color: const Color(0xFFFFD45F),
                  ),
                ),
              ),
              const SizedBox(width: 7),
              Text(
                '$within/${DedaSocialProgressWallet.xpPerLevel}',
                style: const TextStyle(
                  color: Color(0xFFE8EEF5),
                  fontWeight: FontWeight.w700,
                  fontSize: 10.5,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _balancePill({
    required String icon,
    required int value,
    required String label,
  }) {
    return Container(
      constraints: const BoxConstraints(minHeight: 62),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.10),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        children: <Widget>[
          Text(icon, style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    '$value',
                    maxLines: 1,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 17,
                    ),
                  ),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFDDE7F1),
                    fontWeight: FontWeight.w600,
                    fontSize: 10.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Color> _pairGradient(int index) {
    const gradients = <List<Color>>[
      <Color>[Color(0xFFFFFBEB), Color(0xFFFFF1BD)],
      <Color>[Color(0xFFF0FBFF), Color(0xFFDDF5FF)],
      <Color>[Color(0xFFFFFBED), Color(0xFFFFF0BF)],
      <Color>[Color(0xFFFFF3FF), Color(0xFFF3E1FF)],
      <Color>[Color(0xFFF4F7FF), Color(0xFFE4EBFF)],
      <Color>[Color(0xFFFFF4EE), Color(0xFFFFE1D2)],
    ];
    return gradients[index.clamp(0, 5).toInt()];
  }

  Color _pairAccent(int index) {
    const colors = <Color>[
      Color(0xFFB47A05),
      Color(0xFF1687C9),
      Color(0xFFB47A05),
      Color(0xFF8A46C7),
      Color(0xFF163D7A),
      Color(0xFFC64522),
    ];
    return colors[index.clamp(0, 5).toInt()];
  }

  Widget _pairCard(int index, DedaStyleInventorySnapshot inventory) {
    final badgeId = dedaStyleBadgeId(index);
    final frameId = 'frame_$index';
    final badgeOwned = inventory.owned.contains(badgeId);
    final frameOwned = inventory.owned.contains(frameId);
    final badgeActive = inventory.activeBadges.contains(badgeId);
    final frameEquipped = DedaPreferences.profileFrameStyle == index;
    final accent = _pairAccent(index);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(9, 10, 9, 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: _pairGradient(index),
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withOpacity(0.35), width: 1.1),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x12062E57),
            blurRadius: 9,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Text(
                  '${index + 1}. ${dedaStyleName(index)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                dedaStylePriceLabel(index),
                style: TextStyle(
                  color: accent,
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: _badgeSide(
                  index: index,
                  owned: badgeOwned,
                  active: badgeActive,
                  accent: accent,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 46),
                child: Icon(
                  Icons.compare_arrows_rounded,
                  color: accent.withOpacity(0.72),
                  size: 25,
                ),
              ),
              Expanded(
                child: _frameSide(
                  index: index,
                  owned: frameOwned,
                  equipped: frameEquipped,
                  accent: accent,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _badgeSide({
    required int index,
    required bool owned,
    required bool active,
    required Color accent,
  }) {
    return Column(
      children: <Widget>[
        SizedBox(
          height: 104,
          child: DedaBadgeAsset(id: dedaStyleBadgeId(index), size: 102),
        ),
        Text(
          dedaText('شارة ${dedaStyleName(index)}', '${dedaStyleName(index)} badge'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: accent,
            fontWeight: FontWeight.w900,
            fontSize: 11.5,
          ),
        ),
        const SizedBox(height: 5),
        SizedBox(
          height: 38,
          width: double.infinity,
          child: owned
              ? OutlinedButton(
                  onPressed: active ? null : () => _activateBadge(index),
                  child: Text(
                    active ? dedaText('مفعلة', 'Active') : dedaText('تفعيل', 'Use'),
                  ),
                )
              : FilledButton(
                  onPressed: _busy ? null : () => _buyBadge(index),
                  child: Text(dedaStylePriceLabel(index)),
                ),
        ),
      ],
    );
  }

  Widget _frameSide({
    required int index,
    required bool owned,
    required bool equipped,
    required Color accent,
  }) {
    return Column(
      children: <Widget>[
        SizedBox(
          height: 104,
          child: Center(
            child: DedaFramedAvatar(
              avatarStyle: DedaPreferences.profileAvatarStyle,
              frameStyle: index,
              size: 102,
            ),
          ),
        ),
        Text(
          dedaText('إطار ${dedaStyleName(index)}', '${dedaStyleName(index)} frame'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: accent,
            fontWeight: FontWeight.w900,
            fontSize: 11.5,
          ),
        ),
        const SizedBox(height: 5),
        SizedBox(
          height: 38,
          width: double.infinity,
          child: owned
              ? OutlinedButton(
                  onPressed: equipped ? null : () => _equipFrame(index),
                  child: Text(
                    equipped ? dedaText('مستخدم', 'Equipped') : dedaText('استخدام', 'Equip'),
                  ),
                )
              : FilledButton(
                  onPressed: _busy ? null : () => _buyFrame(index),
                  child: Text(dedaStylePriceLabel(index)),
                ),
        ),
      ],
    );
  }
}

'''
text = text[:style_start] + style_code + text[gifts_marker:]

MAIN.write_text(text, encoding='utf-8')

pubspec = PUBSPEC.read_text(encoding='utf-8')
asset_line = '    - assets/deda_style/\n'
if asset_line not in pubspec:
    anchor = '    - assets/deda_home_bg.jpg\n'
    if anchor not in pubspec:
        raise SystemExit('pubspec asset anchor missing')
    pubspec = pubspec.replace(anchor, anchor + asset_line, 1)
    PUBSPEC.write_text(pubspec, encoding='utf-8')

print('Applied DEDA 100273 matched 6 badges + 6 frames, store balances, and single active badge')
