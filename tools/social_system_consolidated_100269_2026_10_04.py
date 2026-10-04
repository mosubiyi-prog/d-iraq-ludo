from pathlib import Path

path = Path('lib/main.dart')
text = path.read_text(encoding='utf-8')
marker = '// DEDA_SOCIAL_SYSTEM_100269'
if marker in text:
    print('DEDA consolidated social system 100269 already applied')
    raise SystemExit(0)

if '// DEDA_ADD_FRIEND_UI_100267' not in text:
    raise SystemExit('100267 add-friend UI must be applied before 100269')

# Import the dedicated Firestore social service.
import_anchor = "import 'deda_backend.dart';\n"
if text.count(import_anchor) != 1:
    raise SystemExit(f'expected one deda_backend import, found {text.count(import_anchor)}')
text = text.replace(
    import_anchor,
    import_anchor + "import 'deda_social_service.dart';\n",
    1,
)

# Requests and Style become real personal-account pages.
requests_placeholder = """          _DedaSocialPlaceholderPage(
            arabicTitle: 'الطلبات',
            englishTitle: 'Requests',
            icon: Icons.mail_rounded,
            accent: Color(0xFF6B35C9),
          ),"""
if text.count(requests_placeholder) != 1:
    raise SystemExit('requests placeholder not found exactly once')
text = text.replace(requests_placeholder, "          const DedaFriendRequestsPage(),", 1)

style_placeholder = """          _DedaSocialPlaceholderPage(
            arabicTitle: 'الزينة',
            englishTitle: 'Style',
            icon: Icons.auto_awesome_rounded,
            accent: Color(0xFFE39A14),
          ),"""
if text.count(style_placeholder) != 1:
    raise SystemExit('style placeholder not found exactly once')
text = text.replace(style_placeholder, "          const DedaStylePage(),", 1)

# Allow purchased frames 3..5 to persist. The three original free frames remain 0..2.
old_frame_load = """    profileFrameStyle =
        (prefs.getInt(_profileFrameKey(phone)) ?? 0).clamp(0, 2).toInt();"""
new_frame_load = """    profileFrameStyle =
        (prefs.getInt(_profileFrameKey(phone)) ?? 0).clamp(0, 5).toInt();"""
if text.count(old_frame_load) != 1:
    raise SystemExit('profile frame load clamp anchor missing')
text = text.replace(old_frame_load, new_frame_load, 1)

old_login_frame = """    profileFrameStyle = (prefs.getInt(_profileFrameKey(normalizedPhone)) ?? 0)
        .clamp(0, 2)
        .toInt();"""
new_login_frame = """    profileFrameStyle = (prefs.getInt(_profileFrameKey(normalizedPhone)) ?? 0)
        .clamp(0, 5)
        .toInt();"""
if text.count(old_login_frame) != 1:
    raise SystemExit('profile login frame clamp anchor missing')
text = text.replace(old_login_frame, new_login_frame, 1)

old_set_frame = '    profileFrameStyle = frameStyle.clamp(0, 2).toInt();'
if text.count(old_set_frame) != 1:
    raise SystemExit('profile frame setter clamp anchor missing')
text = text.replace(
    old_set_frame,
    '    profileFrameStyle = frameStyle.clamp(0, 5).toInt();',
    1,
)

# Spend support for the existing account-scoped diamonds wallet.
wallet_write = '  static Future<void> _write(\n'
if text.count(wallet_write) != 1:
    raise SystemExit(f'expected one diamonds _write marker, found {text.count(wallet_write)}')
diamond_spend = r'''  static Future<bool> spend(int amount) async {
    if (amount <= 0) return true;
    final prefs = await SharedPreferences.getInstance();
    final current = await load();
    if (current.balance < amount) return false;
    final next = current.balance - amount;
    await _write(
      prefs,
      balance: next,
      viewsToday: current.viewsToday,
      dayKey: current.dayKey,
    );
    balanceNotifier.value = next;
    return true;
  }

'''
text = text.replace(wallet_write, diamond_spend + wallet_write, 1)

# Task claims power the personal social level + DEDA digital currency.
task_claim_anchor = '    final result = await DedaTaskEngine.claimTaskReward(taskId);\n'
if text.count(task_claim_anchor) != 1:
    raise SystemExit(f'expected one task claim UI anchor, found {text.count(task_claim_anchor)}')
text = text.replace(
    task_claim_anchor,
    task_claim_anchor
    + "    if (result.pointsAwarded) {\n"
      "      unawaited(DedaSocialProgressWallet.awardTaskClaim(taskId));\n"
      "    }\n",
    1,
)

# Replace the old constant level seed with the live account-scoped level notifier value.
old_level_seed = """    // UI seed only in 100262. Later this value will come from level tasks.
    const int profileLevel = 1;"""
new_level_seed = """    final int profileLevel = DedaSocialProgressWallet.levelNotifier.value;"""
if text.count(old_level_seed) != 1:
    raise SystemExit('100262 level seed anchor missing')
text = text.replace(old_level_seed, new_level_seed, 1)

# Keep profile counters current when opening My profile.
profile_init_anchor = """    unawaited(DedaDiamondsWallet.load());
    unawaited(DedaTaskEngine.initializeForCurrentAccount());"""
profile_init_replacement = """    unawaited(DedaDiamondsWallet.load());
    unawaited(DedaTaskEngine.initializeForCurrentAccount());
    unawaited(DedaSocialProgressWallet.load());
    unawaited(dedaRefreshFriendCount());
    unawaited(dedaEnsurePersonalSocialSession());"""
if text.count(profile_init_anchor) != 1:
    raise SystemExit('profile init anchor missing')
text = text.replace(profile_init_anchor, profile_init_replacement, 1)

old_friend_stat = """        Expanded(
          child: _statCard(
            icon: Icons.people_alt_rounded,
            value: '0',
            label: dedaText('الأصدقاء', 'Friends'),
            color: const Color(0xFF079466),
            surface: const Color(0xFFE2F8EF),
          ),
        ),"""
new_friend_stat = """        Expanded(
          child: ValueListenableBuilder<int>(
            valueListenable: DedaSocialFriendCount.notifier,
            builder: (context, friends, _) => _statCard(
              icon: Icons.people_alt_rounded,
              value: '$friends',
              label: dedaText('الأصدقاء', 'Friends'),
              color: const Color(0xFF079466),
              surface: const Color(0xFFE2F8EF),
            ),
          ),
        ),"""
if text.count(old_friend_stat) != 1:
    raise SystemExit('hardcoded profile friends stat anchor missing')
text = text.replace(old_friend_stat, new_friend_stat, 1)

# Everything appended by 100266/100267 is replaced as one consolidated social block.
friends_marker = '// DEDA_FRIENDS_PAGE_UI_100266'
friends_start = text.index(friends_marker)
text = text[:friends_start].rstrip() + '\n\n'

social_code = r'''
// DEDA_SOCIAL_SYSTEM_100269
// Personal-account social system. This intentionally stores no place-owner data.
class DedaSocialProgressSnapshot {
  final int coins;
  final int xp;
  final int level;

  const DedaSocialProgressSnapshot({
    required this.coins,
    required this.xp,
    required this.level,
  });
}

class DedaSocialProgressWallet {
  static const int coinsPerTaskClaim = 10;
  static const int xpPerTaskClaim = 20;
  static const int xpPerLevel = 100;
  static final ValueNotifier<int> coinsNotifier = ValueNotifier<int>(0);
  static final ValueNotifier<int> xpNotifier = ValueNotifier<int>(0);
  static final ValueNotifier<int> levelNotifier = ValueNotifier<int>(1);

  static String _scope() {
    final key = DedaBackend.accountKeyForPhone(DedaPreferences.phone).trim();
    return key.isEmpty ? DedaPreferences.phone.trim() : key;
  }

  static String _key() => 'deda_social_progress_v1_${_scope()}';

  static int levelForXp(int xp) => 1 + (xp.clamp(0, 99999999) ~/ xpPerLevel);

  static Future<DedaSocialProgressSnapshot> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key());
    var coins = 0;
    var xp = 0;
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          coins = ((decoded['coins'] as num?)?.toInt() ?? 0).clamp(0, 1 << 30);
          xp = ((decoded['xp'] as num?)?.toInt() ?? 0).clamp(0, 1 << 30);
        }
      } catch (_) {}
    }
    final level = levelForXp(xp);
    coinsNotifier.value = coins;
    xpNotifier.value = xp;
    levelNotifier.value = level;
    return DedaSocialProgressSnapshot(coins: coins, xp: xp, level: level);
  }

  static Future<void> awardTaskClaim(String taskId) async {
    final prefs = await SharedPreferences.getInstance();
    final snapshot = await load();
    final cycle = DedaTaskEngine.currentLocalCycleId();
    final awardId = '$cycle|$taskId';
    final raw = prefs.getString(_key());
    final decoded = raw == null || raw.isEmpty
        ? <String, dynamic>{}
        : (() {
            try {
              final value = jsonDecode(raw);
              return value is Map
                  ? Map<String, dynamic>.from(value)
                  : <String, dynamic>{};
            } catch (_) {
              return <String, dynamic>{};
            }
          })();
    final claimed = (decoded['taskClaims'] is List)
        ? List<String>.from((decoded['taskClaims'] as List).map((e) => e.toString()))
        : <String>[];
    if (claimed.contains(awardId)) return;
    claimed.add(awardId);
    if (claimed.length > 180) claimed.removeRange(0, claimed.length - 180);
    final coins = snapshot.coins + coinsPerTaskClaim;
    final xp = snapshot.xp + xpPerTaskClaim;
    await prefs.setString(
      _key(),
      jsonEncode(<String, dynamic>{
        'coins': coins,
        'xp': xp,
        'taskClaims': claimed,
      }),
    );
    coinsNotifier.value = coins;
    xpNotifier.value = xp;
    levelNotifier.value = levelForXp(xp);
  }

  static Future<bool> spendCoins(int amount) async {
    if (amount <= 0) return true;
    final prefs = await SharedPreferences.getInstance();
    final snapshot = await load();
    if (snapshot.coins < amount) return false;
    final raw = prefs.getString(_key());
    Map<String, dynamic> decoded = <String, dynamic>{};
    if (raw != null && raw.isNotEmpty) {
      try {
        final value = jsonDecode(raw);
        if (value is Map) decoded = Map<String, dynamic>.from(value);
      } catch (_) {}
    }
    final next = snapshot.coins - amount;
    decoded['coins'] = next;
    decoded['xp'] = snapshot.xp;
    await prefs.setString(_key(), jsonEncode(decoded));
    coinsNotifier.value = next;
    return true;
  }
}

class DedaStyleInventorySnapshot {
  final Set<String> owned;
  final Set<String> activeBadges;

  const DedaStyleInventorySnapshot({
    required this.owned,
    required this.activeBadges,
  });
}

class DedaStyleInventory {
  static String _scope() {
    final key = DedaBackend.accountKeyForPhone(DedaPreferences.phone).trim();
    return key.isEmpty ? DedaPreferences.phone.trim() : key;
  }

  static String _key() => 'deda_style_inventory_v1_${_scope()}';

  static Future<DedaStyleInventorySnapshot> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key());
    final owned = <String>{'frame_0', 'frame_1', 'frame_2', 'badge_member'};
    final active = <String>{'badge_member'};
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          final rawOwned = decoded['owned'];
          final rawActive = decoded['activeBadges'];
          if (rawOwned is List) owned.addAll(rawOwned.map((e) => e.toString()));
          if (rawActive is List) {
            active
              ..clear()
              ..addAll(rawActive.map((e) => e.toString()));
          }
        }
      } catch (_) {}
    }
    active.removeWhere((id) => !owned.contains(id));
    if (active.isEmpty) active.add('badge_member');
    return DedaStyleInventorySnapshot(owned: owned, activeBadges: active);
  }

  static Future<void> _save(DedaStyleInventorySnapshot snapshot) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key(),
      jsonEncode(<String, dynamic>{
        'owned': snapshot.owned.toList()..sort(),
        'activeBadges': snapshot.activeBadges.toList()..sort(),
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
    final active = Set<String>.from(current.activeBadges);
    if (active.contains(badgeId) && badgeId != 'badge_member') {
      active.remove(badgeId);
    } else {
      active.add(badgeId);
    }
    if (active.length > 3) {
      final removable = active.firstWhere(
        (id) => id != 'badge_member' && id != badgeId,
        orElse: () => '',
      );
      if (removable.isNotEmpty) active.remove(removable);
    }
    await _save(DedaStyleInventorySnapshot(
      owned: current.owned,
      activeBadges: active,
    ));
  }
}

class DedaSocialFriendCount {
  static final ValueNotifier<int> notifier = ValueNotifier<int>(0);
}

Future<DedaSocialSession> dedaEnsurePersonalSocialSession() async {
  final progress = await DedaSocialProgressWallet.load();
  final inventory = await DedaStyleInventory.load();
  final type = DedaPreferences.accountType ?? DedaAccountType.user;
  return DedaSocialService.ensurePersonalSession(
    name: DedaPreferences.userName,
    phone: DedaPreferences.phone,
    accountType: type == DedaAccountType.placeOwner ? 'placeOwner' : 'user',
    hasApprovedPlace: type == DedaAccountType.placeOwner,
    avatarStyle: DedaPreferences.profileAvatarStyle,
    frameStyle: DedaPreferences.profileFrameStyle,
    backgroundStyle: DedaPreferences.profileBackgroundStyle,
    level: progress.level,
    badges: inventory.activeBadges.toList(),
  );
}

Future<void> dedaRefreshFriendCount() async {
  try {
    final session = await dedaEnsurePersonalSocialSession();
    final relations = await DedaSocialService.watchRelations(session.uid).first;
    DedaSocialFriendCount.notifier.value =
        relations.where((item) => item.status == 'accepted').length;
  } catch (_) {}
}

class DedaFriendsPage extends StatefulWidget {
  final VoidCallback onAddFriend;
  const DedaFriendsPage({super.key, required this.onAddFriend});

  @override
  State<DedaFriendsPage> createState() => _DedaFriendsPageState();
}

class _DedaFriendsPageState extends State<DedaFriendsPage> {
  static const Color _navy = Color(0xFF0B4D8D);
  DedaSocialSession? _session;
  Object? _error;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    try {
      final session = await dedaEnsurePersonalSocialSession();
      if (!mounted) return;
      setState(() {
        _session = session;
        _error = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _remove(DedaFriendshipRecord relation) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(dedaText('إزالة الصديق', 'Remove friend')),
        content: Text(dedaText(
          'هل تريد إزالة هذا الحساب من أصدقائك؟',
          'Remove this account from your friends?',
        )),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(dedaText('إلغاء', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(dedaText('إزالة', 'Remove')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await DedaSocialService.removeRelation(relation.id);
    unawaited(dedaRefreshFriendCount());
  }

  Future<void> _openProfile(DedaFriendshipRecord relation) async {
    final session = _session;
    if (session == null) return;
    final profile = await DedaSocialService.profileForFriend(relation, session.uid);
    if (!mounted) return;
    if (profile == null) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => DedaFriendPublicProfilePage(profile: profile),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF2),
      appBar: AppBar(
        centerTitle: true,
        elevation: 0,
        foregroundColor: Colors.white,
        backgroundColor: _navy,
        title: Text(dedaText('أصدقائي', 'Friends'),
            style: const TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: session == null
          ? Center(
              child: _error == null
                  ? const CircularProgressIndicator()
                  : FilledButton.icon(
                      onPressed: _prepare,
                      icon: const Icon(Icons.refresh_rounded),
                      label: Text(dedaText('إعادة المحاولة', 'Retry')),
                    ),
            )
          : StreamBuilder<List<DedaFriendshipRecord>>(
              stream: DedaSocialService.watchRelations(session.uid),
              builder: (context, snapshot) {
                final friends = (snapshot.data ?? const <DedaFriendshipRecord>[])
                    .where((item) => item.status == 'accepted')
                    .where((item) {
                  final q = _query.trim().toLowerCase();
                  if (q.isEmpty) return true;
                  return item.otherName(session.uid).toLowerCase().contains(q) ||
                      item.otherPublicId(session.uid).toLowerCase().contains(q);
                }).toList();
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (DedaSocialFriendCount.notifier.value != friends.length) {
                    DedaSocialFriendCount.notifier.value = friends.length;
                  }
                });
                return ListView(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 18),
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            gradient: const LinearGradient(
                              colors: <Color>[Color(0xFF2B83D7), Color(0xFF1769C2)],
                            ),
                          ),
                          child: const Icon(Icons.people_alt_rounded,
                              color: Colors.white, size: 23),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              Text(dedaText('أصدقائي', 'Friends'),
                                  style: const TextStyle(
                                      color: Color(0xFF0B3C6F),
                                      fontWeight: FontWeight.w900,
                                      fontSize: 21)),
                              Text(
                                dedaText('${friends.length} صديق', '${friends.length} friends'),
                                style: const TextStyle(
                                    color: Color(0xFF6B7A89),
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12.5),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 54,
                      child: TextField(
                        onChanged: (value) => setState(() => _query = value),
                        decoration: InputDecoration(
                          hintText: dedaText('ابحث بالاسم أو معرف DEDA', 'Search by name or DEDA ID'),
                          prefixIcon: const Icon(Icons.search_rounded, size: 21),
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(color: Color(0xFFC9DCEB)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(color: Color(0xFFC9DCEB)),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (friends.isEmpty)
                      Container(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 15),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: const Color(0xFFD3E1EC)),
                        ),
                        child: Column(
                          children: <Widget>[
                            const Icon(Icons.people_outline_rounded,
                                color: Color(0xFF2577C7), size: 40),
                            const SizedBox(height: 7),
                            Text(dedaText('ما عندك أصدقاء بعد', 'No friends yet'),
                                style: const TextStyle(
                                    color: Color(0xFF0B3C6F),
                                    fontWeight: FontWeight.w900,
                                    fontSize: 18)),
                            const SizedBox(height: 5),
                            Text(
                              dedaText('أضف صديقًا بمعرف DEDA، وبعد قبول الطلب سيظهر هنا.',
                                  'Add a friend by DEDA ID. They will appear here after accepting.'),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  color: Color(0xFF687B88),
                                  height: 1.35,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12.5),
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              height: 48,
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: widget.onAddFriend,
                                icon: const Icon(Icons.person_add_alt_1_rounded, size: 20),
                                label: Text(dedaText('إضافة صديق', 'Add friend')),
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      ...friends.map((relation) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _DedaFriendCompactCard(
                              name: relation.otherName(session.uid),
                              dedaId: relation.otherPublicId(session.uid),
                              onOpen: () => _openProfile(relation),
                              onRemove: () => _remove(relation),
                            ),
                          )),
                  ],
                );
              },
            ),
    );
  }
}

class _DedaFriendCompactCard extends StatelessWidget {
  final String name;
  final String dedaId;
  final VoidCallback onOpen;
  final VoidCallback onRemove;
  const _DedaFriendCompactCard({
    required this.name,
    required this.dedaId,
    required this.onOpen,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(17),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(17),
        child: Container(
          constraints: const BoxConstraints(minHeight: 78),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(17),
            border: Border.all(color: const Color(0xFFD5E3ED)),
          ),
          child: Row(
            children: <Widget>[
              const CircleAvatar(
                radius: 25,
                backgroundColor: Color(0xFFE6F1FC),
                child: Icon(Icons.person_rounded, color: Color(0xFF1769C2), size: 27),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Color(0xFF0B3C6F),
                            fontWeight: FontWeight.w900, fontSize: 16)),
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: Text(dedaId, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Color(0xFF647787),
                              fontWeight: FontWeight.w700, fontSize: 12.5)),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: dedaText('إزالة الصديق', 'Remove friend'),
                onPressed: onRemove,
                icon: const Icon(Icons.more_vert_rounded, color: Color(0xFF607487)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DedaAddFriendPage extends StatefulWidget {
  const DedaAddFriendPage({super.key});
  @override
  State<DedaAddFriendPage> createState() => _DedaAddFriendPageState();
}

class _DedaAddFriendPageState extends State<DedaAddFriendPage> {
  final TextEditingController _idController = TextEditingController();
  static const Color _navy = Color(0xFF0B4D8D);
  DedaSocialSession? _session;
  DedaSocialProfile? _result;
  bool _searching = false;
  bool _sending = false;
  String? _resultMessage;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  @override
  void dispose() {
    _idController.dispose();
    super.dispose();
  }

  Future<void> _prepare() async {
    try {
      final session = await dedaEnsurePersonalSocialSession();
      if (mounted) setState(() => _session = session);
    } catch (_) {
      if (mounted) setState(() => _resultMessage = dedaText(
          'تعذر تجهيز حساب الصداقة الآن.', 'Could not prepare the friendship account.'));
    }
  }

  Future<void> _copyMyId() async {
    final id = _session?.publicId ?? DedaBackend.personalShareIdForPhone(DedaPreferences.phone);
    if (id.trim().isEmpty) return;
    await Clipboard.setData(ClipboardData(text: id));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(dedaText('تم نسخ معرفك في DEDA', 'Your DEDA ID was copied'),
          textAlign: TextAlign.center),
    ));
  }

  Future<void> _search() async {
    final session = _session;
    if (session == null) {
      await _prepare();
      if (_session == null) return;
    }
    final id = DedaSocialService.normalizePublicId(_idController.text);
    if (!DedaSocialService.looksLikePersonalId(id)) {
      setState(() {
        _result = null;
        _resultMessage = dedaText('تحقق من المعرف. مثال: @DEDA-AQPYXJ',
            'Check the ID. Example: @DEDA-AQPYXJ');
      });
      return;
    }
    if (id == _session!.publicId) {
      setState(() {
        _result = null;
        _resultMessage = dedaText('لا يمكنك إضافة نفسك كصديق.',
            'You cannot add yourself as a friend.');
      });
      return;
    }
    setState(() {
      _searching = true;
      _result = null;
      _resultMessage = null;
    });
    try {
      final found = await DedaSocialService.findByPublicId(id);
      if (!mounted) return;
      setState(() {
        _result = found;
        _resultMessage = found == null
            ? dedaText('لم يتم العثور على حساب بهذا المعرف.',
                'No account was found for this ID.')
            : null;
        _idController.value = TextEditingValue(
          text: id,
          selection: TextSelection.collapsed(offset: id.length),
        );
      });
    } catch (_) {
      if (mounted) setState(() => _resultMessage = dedaText(
          'تعذر البحث الآن. تحقق من الإنترنت وحاول مرة أخرى.',
          'Search failed. Check your connection and try again.'));
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _send() async {
    final sender = _session;
    final target = _result;
    if (sender == null || target == null || _sending) return;
    setState(() => _sending = true);
    try {
      await DedaSocialService.sendFriendRequest(sender: sender, target: target);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(dedaText('تم إرسال طلب الصداقة بنجاح.',
            'Friend request sent successfully.'), textAlign: TextAlign.center),
      ));
    } on StateError catch (error) {
      if (!mounted) return;
      final code = error.message;
      final ar = code == 'social-already-friends'
          ? 'هذا الحساب ضمن أصدقائك بالفعل.'
          : code == 'social-request-pending'
              ? 'يوجد طلب صداقة معلّق بينكما بالفعل.'
              : code == 'social-self-request'
                  ? 'لا يمكنك إضافة نفسك كصديق.'
                  : 'تعذر إرسال الطلب الآن.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(dedaText(ar, 'Could not send the request right now.'),
            textAlign: TextAlign.center),
      ));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(dedaText('تعذر إرسال الطلب الآن.',
            'Could not send the request right now.'), textAlign: TextAlign.center),
      ));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final myId = _session?.publicId ??
        DedaBackend.personalShareIdForPhone(DedaPreferences.phone).trim();
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF2),
      appBar: AppBar(
        centerTitle: true,
        elevation: 0,
        foregroundColor: Colors.white,
        backgroundColor: _navy,
        title: Text(dedaText('إضافة صديق', 'Add friend'),
            style: const TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 18),
          children: <Widget>[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: <Color>[Color(0xFFE5F7EF), Color(0xFFF7FCF9)]),
                borderRadius: BorderRadius.circular(17),
                border: Border.all(color: const Color(0xFFB9E1D2)),
              ),
              child: Row(
                children: <Widget>[
                  const CircleAvatar(
                    radius: 23,
                    backgroundColor: Color(0xFF15946A),
                    child: Icon(Icons.person_add_alt_1_rounded,
                        color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Text(dedaText('أضف صديقك بمعرف DEDA', 'Add by DEDA ID'),
                            style: const TextStyle(color: Color(0xFF0B3C6F),
                                fontWeight: FontWeight.w900, fontSize: 17)),
                        const SizedBox(height: 2),
                        Text(dedaText('ابحث عن المعرف ثم أرسل طلب الصداقة.',
                                'Find the ID, then send a friend request.'),
                            style: const TextStyle(color: Color(0xFF607487),
                                fontWeight: FontWeight.w600, fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(17),
                border: Border.all(color: const Color(0xFFD7E4EE)),
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Text(dedaText('معرفي في DEDA', 'My DEDA ID'),
                            style: const TextStyle(color: Color(0xFF0B3C6F),
                                fontWeight: FontWeight.w900, fontSize: 13.5)),
                        const SizedBox(height: 2),
                        Directionality(
                          textDirection: TextDirection.ltr,
                          child: FittedBox(
                            alignment: Alignment.centerLeft,
                            fit: BoxFit.scaleDown,
                            child: Text(myId.isEmpty ? '@DEDA' : myId,
                                maxLines: 1,
                                style: const TextStyle(color: Color(0xFF334E68),
                                    fontWeight: FontWeight.w900, fontSize: 15)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton.filledTonal(
                    onPressed: _copyMyId,
                    tooltip: dedaText('نسخ', 'Copy'),
                    icon: const Icon(Icons.copy_rounded, size: 19),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(17),
                border: Border.all(color: const Color(0xFFBFD7EB)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(dedaText('معرف الصديق', 'Friend DEDA ID'),
                      style: const TextStyle(color: Color(0xFF0B3C6F),
                          fontWeight: FontWeight.w900, fontSize: 14)),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 54,
                    child: Directionality(
                      textDirection: TextDirection.ltr,
                      child: TextField(
                        controller: _idController,
                        textDirection: TextDirection.ltr,
                        textCapitalization: TextCapitalization.characters,
                        autocorrect: false,
                        enableSuggestions: false,
                        onSubmitted: (_) => _search(),
                        decoration: InputDecoration(
                          hintText: '@DEDA-AQPYXJ',
                          filled: true,
                          fillColor: const Color(0xFFF7FAFC),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: Color(0xFFD5E3EF)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: _navy, width: 1.5),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 48,
                    child: FilledButton.icon(
                      onPressed: _searching ? null : _search,
                      icon: _searching
                          ? const SizedBox(width: 18, height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.search_rounded, size: 20),
                      label: Text(dedaText('بحث عن المعرف', 'Search ID'),
                          style: const TextStyle(fontWeight: FontWeight.w900)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            if (_result != null)
              _DedaSearchResultCard(
                profile: _result!,
                sending: _sending,
                onSend: _send,
              )
            else if (_resultMessage != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFCF3),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFF0D99A)),
                ),
                child: Text(_resultMessage!, textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFF765D25),
                        fontWeight: FontWeight.w700, fontSize: 12.5)),
              ),
          ],
        ),
      ),
    );
  }
}

class _DedaSearchResultCard extends StatelessWidget {
  final DedaSocialProfile profile;
  final bool sending;
  final VoidCallback onSend;
  const _DedaSearchResultCard({
    required this.profile,
    required this.sending,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: const Color(0xFFE2CE8B)),
      ),
      child: Row(
        children: <Widget>[
          DedaFramedAvatar(
            avatarStyle: profile.avatarStyle,
            frameStyle: profile.frameStyle,
            size: 68,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(profile.displayName, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Color(0xFF0B3C6F),
                        fontWeight: FontWeight.w900, fontSize: 15.5)),
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: Text(profile.publicId, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Color(0xFF647787),
                          fontWeight: FontWeight.w700, fontSize: 12)),
                ),
                const SizedBox(height: 3),
                Text(dedaText('⭐ مستوى ${profile.level}', '⭐ Level ${profile.level}'),
                    style: const TextStyle(color: Color(0xFF9A6800),
                        fontWeight: FontWeight.w900, fontSize: 11.5)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 44,
            child: FilledButton(
              onPressed: sending ? null : onSend,
              child: sending
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(dedaText('إرسال', 'Send')),
            ),
          ),
        ],
      ),
    );
  }
}

class DedaFriendRequestsPage extends StatefulWidget {
  const DedaFriendRequestsPage({super.key});
  @override
  State<DedaFriendRequestsPage> createState() => _DedaFriendRequestsPageState();
}

class _DedaFriendRequestsPageState extends State<DedaFriendRequestsPage> {
  DedaSocialSession? _session;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    try {
      final value = await dedaEnsurePersonalSocialSession();
      if (mounted) setState(() => _session = value);
    } catch (_) {}
  }

  Future<void> _respond(DedaFriendshipRecord relation, bool accept) async {
    try {
      await DedaSocialService.respondToRequest(
        relationId: relation.id,
        accept: accept,
      );
      if (accept) unawaited(dedaRefreshFriendCount());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          dedaText(accept ? 'تم قبول طلب الصداقة.' : 'تم رفض طلب الصداقة.',
              accept ? 'Friend request accepted.' : 'Friend request rejected.'),
          textAlign: TextAlign.center,
        ),
      ));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(dedaText('تعذر تحديث الطلب الآن.',
            'Could not update the request right now.'), textAlign: TextAlign.center),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF2),
      appBar: AppBar(
        centerTitle: true,
        foregroundColor: Colors.white,
        backgroundColor: const Color(0xFF0B4D8D),
        title: Text(dedaText('الطلبات', 'Requests'),
            style: const TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: session == null
          ? const Center(child: CircularProgressIndicator())
          : StreamBuilder<List<DedaFriendshipRecord>>(
              stream: DedaSocialService.watchRelations(session.uid),
              builder: (context, snapshot) {
                final all = snapshot.data ?? const <DedaFriendshipRecord>[];
                final incoming = all
                    .where((item) => item.status == 'pending' &&
                        item.recipientUid == session.uid)
                    .toList();
                final outgoing = all
                    .where((item) => item.status == 'pending' &&
                        item.requesterUid == session.uid)
                    .toList();
                return ListView(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 18),
                  children: <Widget>[
                    _requestSectionTitle(
                      dedaText('طلبات واردة', 'Incoming requests'),
                      incoming.length,
                    ),
                    const SizedBox(height: 7),
                    if (incoming.isEmpty)
                      _emptyRequestBox(dedaText('لا توجد طلبات واردة حاليًا.',
                          'No incoming requests right now.'))
                    else
                      ...incoming.map((item) => _requestCard(
                            name: item.requesterName,
                            dedaId: item.requesterPublicId,
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                IconButton.filled(
                                  tooltip: dedaText('قبول', 'Accept'),
                                  onPressed: () => _respond(item, true),
                                  icon: const Icon(Icons.check_rounded, size: 20),
                                ),
                                const SizedBox(width: 5),
                                IconButton.outlined(
                                  tooltip: dedaText('رفض', 'Reject'),
                                  onPressed: () => _respond(item, false),
                                  icon: const Icon(Icons.close_rounded, size: 20),
                                ),
                              ],
                            ),
                          )),
                    const SizedBox(height: 14),
                    _requestSectionTitle(
                      dedaText('طلبات مرسلة', 'Sent requests'),
                      outgoing.length,
                    ),
                    const SizedBox(height: 7),
                    if (outgoing.isEmpty)
                      _emptyRequestBox(dedaText('لا توجد طلبات معلّقة مرسلة.',
                          'No pending sent requests.'))
                    else
                      ...outgoing.map((item) => _requestCard(
                            name: item.recipientName,
                            dedaId: item.recipientPublicId,
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFF1C7),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(dedaText('بانتظار القبول', 'Pending'),
                                  style: const TextStyle(color: Color(0xFF926500),
                                      fontWeight: FontWeight.w800, fontSize: 10.5)),
                            ),
                          )),
                  ],
                );
              },
            ),
    );
  }

  Widget _requestSectionTitle(String title, int count) => Row(
        children: <Widget>[
          Expanded(child: Text(title, style: const TextStyle(
              color: Color(0xFF0B3C6F), fontWeight: FontWeight.w900, fontSize: 17))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: const Color(0xFFE6EFF8),
                borderRadius: BorderRadius.circular(12)),
            child: Text('$count', style: const TextStyle(color: Color(0xFF0B4D8D),
                fontWeight: FontWeight.w900)),
          ),
        ],
      );

  Widget _emptyRequestBox(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(color: Colors.white,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: const Color(0xFFD9E5ED))),
        child: Text(text, textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF6B7C89),
                fontWeight: FontWeight.w600, fontSize: 12.5)),
      );

  Widget _requestCard({
    required String name,
    required String dedaId,
    required Widget trailing,
  }) => Container(
        margin: const EdgeInsets.only(bottom: 7),
        constraints: const BoxConstraints(minHeight: 70),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        decoration: BoxDecoration(color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFD7E3EC))),
        child: Row(
          children: <Widget>[
            const CircleAvatar(radius: 22, backgroundColor: Color(0xFFE8F1FA),
                child: Icon(Icons.person_rounded, color: Color(0xFF1769C2), size: 24)),
            const SizedBox(width: 8),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Color(0xFF0B3C6F),
                        fontWeight: FontWeight.w900, fontSize: 14)),
                Directionality(textDirection: TextDirection.ltr,
                  child: Text(dedaId, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Color(0xFF687A89),
                          fontWeight: FontWeight.w700, fontSize: 11.5))),
              ],
            )),
            const SizedBox(width: 6),
            trailing,
          ],
        ),
      );
}

class DedaFriendPublicProfilePage extends StatelessWidget {
  final DedaSocialProfile profile;
  const DedaFriendPublicProfilePage({super.key, required this.profile});

  String _badgeLabel(String id) {
    switch (id) {
      case 'badge_spark': return dedaText('متألق', 'Spark');
      case 'badge_elite': return dedaText('نخبوي', 'Elite');
      default: return dedaText('عضو DEDA', 'DEDA member');
    }
  }

  @override
  Widget build(BuildContext context) {
    final bg = dedaProfileBackgroundColors(profile.backgroundStyle);
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF2),
      appBar: AppBar(
        centerTitle: true,
        title: Text(dedaText('الملف العام', 'Public profile')),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 22),
        children: <Widget>[
          Container(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: bg,
                  begin: Alignment.topRight, end: Alignment.bottomLeft),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFE1CB82)),
            ),
            child: Column(
              children: <Widget>[
                DedaFramedAvatar(
                  avatarStyle: profile.avatarStyle,
                  frameStyle: profile.frameStyle,
                  size: 132,
                ),
                const SizedBox(height: 8),
                Text(profile.displayName, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Color(0xFF0B3C6F),
                        fontWeight: FontWeight.w900, fontSize: 23)),
                const SizedBox(height: 3),
                Directionality(textDirection: TextDirection.ltr,
                  child: FittedBox(fit: BoxFit.scaleDown,
                    child: Text(profile.publicId, maxLines: 1,
                        style: const TextStyle(color: Color(0xFF536779),
                            fontWeight: FontWeight.w800, fontSize: 15)))),
                const SizedBox(height: 9),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: const Color(0xFFFFEFB9),
                      borderRadius: BorderRadius.circular(15)),
                  child: Text(dedaText('⭐ المستوى ${profile.level}',
                      '⭐ Level ${profile.level}'),
                      style: const TextStyle(color: Color(0xFF9A6800),
                          fontWeight: FontWeight.w900, fontSize: 13)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(dedaText('الشارات', 'Badges'),
              style: const TextStyle(color: Color(0xFF0B3C6F),
                  fontWeight: FontWeight.w900, fontSize: 17)),
          const SizedBox(height: 7),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: (profile.badges.isEmpty ? const <String>['badge_member'] : profile.badges)
                .map((id) => Chip(
                      avatar: const Icon(Icons.workspace_premium_rounded,
                          color: Color(0xFFB47A05), size: 18),
                      label: Text(_badgeLabel(id),
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                    ))
                .toList(),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFDCE6DC))),
            child: Text(
              dedaText('هذا هو الملف الشخصي العام الذي يراه الأصدقاء فقط داخل واجهة DEDA. لا تظهر هنا أرقام الهاتف أو إعدادات الحساب الخاصة.',
                  'This is the public personal profile shown to friends in DEDA. Phone numbers and private account settings are never shown here.'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF65776C),
                  height: 1.35, fontWeight: FontWeight.w600, fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }
}

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
    final values = await Future.wait<dynamic>([
      DedaSocialProgressWallet.load(),
      DedaStyleInventory.load(),
      DedaDiamondsWallet.load(),
    ]);
    if (!mounted) return;
    final diamonds = values[2] as DedaDiamondsState;
    setState(() {
      _progress = values[0] as DedaSocialProgressSnapshot;
      _inventory = values[1] as DedaStyleInventorySnapshot;
      _diamonds = diamonds.balance;
    });
  }

  Future<void> _equipFrame(int index) async {
    final inventory = _inventory;
    if (inventory == null || !inventory.owned.contains('frame_$index')) return;
    await DedaPreferences.setProfileAppearance(
      avatarStyle: DedaPreferences.profileAvatarStyle,
      frameStyle: index,
      backgroundStyle: DedaPreferences.profileBackgroundStyle,
    );
    await dedaEnsurePersonalSocialSession();
    if (mounted) setState(() {});
  }

  Future<void> _buyFrame(int index) async {
    if (_busy) return;
    final progress = _progress;
    if (progress == null) return;
    final minLevel = index == 3 ? 2 : index == 4 ? 3 : 5;
    if (progress.level < minLevel) {
      _message(dedaText('يحتاج هذا الإطار إلى المستوى $minLevel أولًا.',
          'This frame requires level $minLevel first.'));
      return;
    }
    setState(() => _busy = true);
    try {
      bool paid;
      if (index == 4) {
        paid = await DedaSocialProgressWallet.spendCoins(120);
      } else {
        paid = await DedaDiamondsWallet.spend(index == 3 ? 30 : 60);
      }
      if (!paid) {
        _message(dedaText(index == 4 ? 'رصيد عملة DEDA غير كافٍ.' : 'رصيد الماسات غير كافٍ.',
            'Your balance is not enough.'));
        return;
      }
      await DedaStyleInventory.addOwned('frame_$index');
      await _load();
      if (mounted) _message(dedaText('تم فتح الإطار وأصبح ضمن مقتنياتك.',
          'The frame is now unlocked and owned.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _buyBadge(String id, int level, int amount, bool diamonds) async {
    if (_busy) return;
    final progress = _progress;
    if (progress == null) return;
    if (progress.level < level) {
      _message(dedaText('تحتاج إلى المستوى $level أولًا.',
          'You need level $level first.'));
      return;
    }
    setState(() => _busy = true);
    try {
      final paid = diamonds
          ? await DedaDiamondsWallet.spend(amount)
          : await DedaSocialProgressWallet.spendCoins(amount);
      if (!paid) {
        _message(dedaText('الرصيد غير كافٍ لفتح هذه الشارة.',
            'Your balance is not enough to unlock this badge.'));
        return;
      }
      await DedaStyleInventory.addOwned(id);
      await _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleBadge(String id) async {
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
        title: Text(dedaText('الزينة', 'Style'),
            style: const TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 22),
        children: <Widget>[
          Container(
            padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: <Color>[Color(0xFFFFF0B9), Color(0xFFFFFAE8)]),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE5C76A)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(children: <Widget>[
                  const Icon(Icons.star_rounded, color: Color(0xFFC88900), size: 28),
                  const SizedBox(width: 8),
                  Expanded(child: Text(dedaText('المستوى ${progress.level}', 'Level ${progress.level}'),
                      style: const TextStyle(color: Color(0xFF704F00),
                          fontWeight: FontWeight.w900, fontSize: 18))),
                  Text('💎 $_diamonds', style: const TextStyle(fontWeight: FontWeight.w900)),
                  const SizedBox(width: 10),
                  Text('🪙 ${progress.coins}', style: const TextStyle(fontWeight: FontWeight.w900)),
                ]),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: ratio,
                    minHeight: 8,
                    backgroundColor: Colors.white.withOpacity(0.8),
                    color: const Color(0xFFC88900),
                  ),
                ),
                const SizedBox(height: 5),
                Text(dedaText('$within / ${DedaSocialProgressWallet.xpPerLevel} XP للمستوى التالي',
                    '$within / ${DedaSocialProgressWallet.xpPerLevel} XP to next level'),
                    style: const TextStyle(color: Color(0xFF806725),
                        fontWeight: FontWeight.w700, fontSize: 11.5)),
              ],
            ),
          ),
          const SizedBox(height: 13),
          Text(dedaText('إطارات DEDA', 'DEDA frames'),
              style: const TextStyle(color: Color(0xFF0B3C6F),
                  fontWeight: FontWeight.w900, fontSize: 18)),
          const SizedBox(height: 4),
          Text(dedaText('3 مجانية، والبقية تُفتح بالمستوى ثم بالماسات أو عملة DEDA.',
              'Three are free; the rest unlock by level and diamonds or DEDA currency.'),
              style: const TextStyle(color: Color(0xFF6C7B86),
                  fontWeight: FontWeight.w600, fontSize: 12.5)),
          const SizedBox(height: 9),
          LayoutBuilder(builder: (context, constraints) {
            final width = ((constraints.maxWidth - 10) / 2).clamp(135.0, 220.0).toDouble();
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: List<Widget>.generate(6, (index) {
                final id = 'frame_$index';
                final owned = inventory.owned.contains(id);
                final equipped = DedaPreferences.profileFrameStyle == index;
                final minLevel = index == 3 ? 2 : index == 4 ? 3 : index == 5 ? 5 : 1;
                final price = index == 3 ? '💎 30' : index == 4 ? '🪙 120' : index == 5 ? '💎 60' : dedaText('مجاني', 'Free');
                return Container(
                  width: width,
                  padding: const EdgeInsets.fromLTRB(8, 9, 8, 9),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(17),
                    border: Border.all(color: equipped
                        ? dedaProfileFrameColors(index)[1]
                        : const Color(0xFFDCE5DC), width: equipped ? 2 : 1),
                  ),
                  child: Column(children: <Widget>[
                    DedaProfileFramePreview(
                      style: index,
                      avatarStyle: DedaPreferences.profileAvatarStyle,
                      size: 92,
                      selected: equipped,
                    ),
                    const SizedBox(height: 4),
                    Text(index < 3
                        ? <String>[dedaText('ذهبي', 'Gold'), dedaText('زمردي', 'Emerald'), dedaText('وردي', 'Rose')][index]
                        : dedaText('إطار مميز ${index - 2}', 'Premium frame ${index - 2}'),
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12.5)),
                    Text(minLevel > 1 ? dedaText('يتطلب مستوى $minLevel', 'Requires level $minLevel') : price,
                        style: const TextStyle(color: Color(0xFF7A817A),
                            fontWeight: FontWeight.w700, fontSize: 10.5)),
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 38,
                      width: double.infinity,
                      child: owned
                          ? OutlinedButton(
                              onPressed: equipped ? null : () => _equipFrame(index),
                              child: Text(equipped ? dedaText('مستخدم', 'Equipped') : dedaText('استخدام', 'Equip')),
                            )
                          : FilledButton(
                              onPressed: _busy ? null : () => _buyFrame(index),
                              child: Text(price),
                            ),
                    ),
                  ]),
                );
              }),
            );
          }),
          const SizedBox(height: 16),
          Text(dedaText('الشارات', 'Badges'),
              style: const TextStyle(color: Color(0xFF0B3C6F),
                  fontWeight: FontWeight.w900, fontSize: 18)),
          const SizedBox(height: 8),
          _badgeTile('badge_member', dedaText('عضو DEDA', 'DEDA member'),
              1, 0, true, inventory),
          _badgeTile('badge_spark', dedaText('متألق', 'Spark'),
              2, 20, true, inventory),
          _badgeTile('badge_elite', dedaText('نخبوي', 'Elite'),
              4, 200, false, inventory),
        ],
      ),
    );
  }

  Widget _badgeTile(
    String id,
    String title,
    int level,
    int price,
    bool diamonds,
    DedaStyleInventorySnapshot inventory,
  ) {
    final owned = inventory.owned.contains(id);
    final active = inventory.activeBadges.contains(id);
    return Container(
      margin: const EdgeInsets.only(bottom: 7),
      constraints: const BoxConstraints(minHeight: 64),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: active ? const Color(0xFFD2A530) : const Color(0xFFDDE5DD),
              width: active ? 1.7 : 1)),
      child: Row(children: <Widget>[
        Container(width: 42, height: 42,
          decoration: BoxDecoration(shape: BoxShape.circle,
              color: active ? const Color(0xFFFFF0BC) : const Color(0xFFF0F3F0)),
          child: Icon(Icons.workspace_premium_rounded,
              color: active ? const Color(0xFFB47A05) : const Color(0xFF7C8780), size: 23)),
        const SizedBox(width: 9),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(title, style: const TextStyle(color: Color(0xFF0B3C6F),
                fontWeight: FontWeight.w900, fontSize: 14)),
            Text(level > 1 ? dedaText('المستوى $level', 'Level $level') : dedaText('مجانية', 'Free'),
                style: const TextStyle(color: Color(0xFF738078), fontSize: 10.5,
                    fontWeight: FontWeight.w700)),
          ],
        )),
        if (owned)
          SizedBox(height: 38,
            child: OutlinedButton(
              onPressed: () => _toggleBadge(id),
              child: Text(active ? dedaText('مفعلة', 'Active') : dedaText('تفعيل', 'Use')),
            ))
        else
          SizedBox(height: 38,
            child: FilledButton(
              onPressed: _busy ? null : () => _buyBadge(id, level, price, diamonds),
              child: Text(diamonds ? '💎 $price' : '🪙 $price'),
            )),
      ]),
    );
  }
}
'''

text += social_code + '\n'
path.write_text(text, encoding='utf-8')
print('applied DEDA consolidated social system 100269')
