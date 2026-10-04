from pathlib import Path

path = Path('lib/main.dart')
text = path.read_text(encoding='utf-8')
marker = '// DEDA_SOCIAL_UI_WALLET_FIXES_100270'
if marker in text:
    print('100270 social UI/wallet fixes already applied')
    raise SystemExit(0)

if '// DEDA_SOCIAL_SYSTEM_100269' not in text:
    raise SystemExit('100269 social system must be applied first')

# ---------------------------------------------------------------------------
# 1) Server-backed gifted diamonds augment, but never overwrite, local earned
#    rewarded-ad diamonds.
# ---------------------------------------------------------------------------
wallet_seed = '''  static const int maxAdsPerDay = 5;
  static final ValueNotifier<int> balanceNotifier = ValueNotifier<int>(0);
'''
wallet_seed_new = '''  static const int maxAdsPerDay = 5;
  static final ValueNotifier<int> balanceNotifier = ValueNotifier<int>(0);
  static int _localBalance = 0;
  static int _giftedBalance = 0;

  static int get giftedBalance => _giftedBalance;
  static int get effectiveBalance => _localBalance + _giftedBalance;
'''
if text.count(wallet_seed) != 1:
    raise SystemExit(f'diamond wallet seed count={text.count(wallet_seed)}')
text = text.replace(wallet_seed, wallet_seed_new, 1)

load_tail = '''    balanceNotifier.value = balance;
    return DedaDiamondsState(
      balance: balance,
      viewsToday: viewsToday,
      dayKey: storedDay,
    );
  }
'''
load_tail_new = '''    _localBalance = balance;
    // Gift credits live on Firestore and are keyed by the stable personal DEDA
    // ID. A temporary network failure never erases the last known gift value.
    final publicId =
        DedaBackend.personalShareIdForPhone(DedaPreferences.phone).trim();
    if (publicId.isNotEmpty) {
      try {
        _giftedBalance =
            await DedaBackend.personalGiftedDiamondBalance(publicId);
      } catch (_) {}
    }
    balanceNotifier.value = effectiveBalance;
    return DedaDiamondsState(
      // Internal state remains LOCAL earned diamonds. Callers that render the
      // user balance use balanceNotifier/effectiveBalance to avoid persisting a
      // remote gift into SharedPreferences by mistake.
      balance: balance,
      viewsToday: viewsToday,
      dayKey: storedDay,
    );
  }
'''
if text.count(load_tail) != 1:
    raise SystemExit(f'diamond load tail count={text.count(load_tail)}')
text = text.replace(load_tail, load_tail_new, 1)

claim_tail = '''    balanceNotifier.value = newBalance;
    return DedaDiamondsClaimResult(
      awarded: true,
      balance: newBalance,
      viewsToday: newViews,
    );'''
claim_tail_new = '''    _localBalance = newBalance;
    balanceNotifier.value = effectiveBalance;
    return DedaDiamondsClaimResult(
      awarded: true,
      balance: effectiveBalance,
      viewsToday: newViews,
    );'''
if text.count(claim_tail) != 1:
    raise SystemExit(f'diamond claim tail count={text.count(claim_tail)}')
text = text.replace(claim_tail, claim_tail_new, 1)

old_spend = '''  static Future<bool> spend(int amount) async {
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
new_spend = '''  static Future<bool> spend(int amount) async {
    if (amount <= 0) return true;
    final prefs = await SharedPreferences.getInstance();
    final current = await load();
    final available = current.balance + _giftedBalance;
    if (available < amount) return false;

    final localToSpend = amount <= current.balance ? amount : current.balance;
    final giftedToSpend = amount - localToSpend;
    var nextGifted = _giftedBalance;

    // Spend the protected remote portion first when needed. Firestore rules
    // allow the owner only to DECREASE this balance, never to increase it.
    if (giftedToSpend > 0) {
      final publicId =
          DedaBackend.personalShareIdForPhone(DedaPreferences.phone).trim();
      if (publicId.isEmpty) return false;
      try {
        nextGifted = await DedaBackend.spendPersonalGiftedDiamonds(
          publicId: publicId,
          amount: giftedToSpend,
        );
      } catch (_) {
        return false;
      }
    }

    final nextLocal = current.balance - localToSpend;
    await _write(
      prefs,
      balance: nextLocal,
      viewsToday: current.viewsToday,
      dayKey: current.dayKey,
    );
    _localBalance = nextLocal;
    _giftedBalance = nextGifted;
    balanceNotifier.value = effectiveBalance;
    return true;
  }
'''
if text.count(old_spend) != 1:
    raise SystemExit(f'diamond spend block count={text.count(old_spend)}')
text = text.replace(old_spend, new_spend, 1)

# Style page must render the effective local + gifted balance.
style_load = '''    final diamonds = values[2] as DedaDiamondsState;
    setState(() {
      _progress = values[0] as DedaSocialProgressSnapshot;
      _inventory = values[1] as DedaStyleInventorySnapshot;
      _diamonds = diamonds.balance;
    });'''
style_load_new = '''    // values[2] intentionally keeps the local wallet state; the notifier is
    // the effective local + server-gifted balance shown to the user.
    values[2] as DedaDiamondsState;
    setState(() {
      _progress = values[0] as DedaSocialProgressSnapshot;
      _inventory = values[1] as DedaStyleInventorySnapshot;
      _diamonds = DedaDiamondsWallet.balanceNotifier.value;
    });'''
if text.count(style_load) != 1:
    raise SystemExit(f'style diamond load count={text.count(style_load)}')
text = text.replace(style_load, style_load_new, 1)

# ---------------------------------------------------------------------------
# 2) One appearance source: Style -> My profile -> public preview -> friend card.
# ---------------------------------------------------------------------------
appearance_insert = '''class DedaSocialFriendCount {
  static final ValueNotifier<int> notifier = ValueNotifier<int>(0);
}
'''
appearance_new = '''class DedaSocialFriendCount {
  static final ValueNotifier<int> notifier = ValueNotifier<int>(0);
}

class DedaProfileAppearanceState {
  static final ValueNotifier<int> frameNotifier =
      ValueNotifier<int>(DedaPreferences.profileFrameStyle);

  static void syncFromPreferences() {
    frameNotifier.value = DedaPreferences.profileFrameStyle;
  }
}
'''
if text.count(appearance_insert) != 1:
    raise SystemExit(f'appearance state insertion count={text.count(appearance_insert)}')
text = text.replace(appearance_insert, appearance_new, 1)

frame_colors = '''    final frameColors = <Color>[
      const Color(0xFFD4A72C),
      const Color(0xFF1B8F6C),
      const Color(0xFF9A4E72),
    ];
    final frame = frameColors[
        DedaPreferences.profileFrameStyle.abs() % frameColors.length];
'''
if text.count(frame_colors) != 1:
    raise SystemExit(f'legacy profile frame color block count={text.count(frame_colors)}')
text = text.replace(frame_colors, '', 1)

avatar_call = '_avatar(frame, compact ? 92 : 104),'
avatar_call_new = '''ValueListenableBuilder<int>(
                valueListenable: DedaProfileAppearanceState.frameNotifier,
                builder: (context, frameStyle, _) =>
                    _avatar(frameStyle, compact ? 92 : 104),
              ),'''
if text.count(avatar_call) != 1:
    raise SystemExit(f'profile avatar call count={text.count(avatar_call)}')
text = text.replace(avatar_call, avatar_call_new, 1)

avatar_start = text.index('  Widget _avatar(Color frame, double size) {')
avatar_end = text.index('  Widget _miniPill({', avatar_start)
new_avatar = r'''  Widget _avatar(int frameStyle, double size) {
    return SizedBox(
      width: size,
      height: size + 10,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          DedaFramedAvatar(
            avatarStyle: DedaPreferences.profileAvatarStyle,
            frameStyle: frameStyle,
            size: size,
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

'''
text = text[:avatar_start] + new_avatar + text[avatar_end:]

public_avatar = '''                Container(
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
                ),'''
public_avatar_new = '''                ValueListenableBuilder<int>(
                  valueListenable: DedaProfileAppearanceState.frameNotifier,
                  builder: (context, frameStyle, _) => DedaFramedAvatar(
                    avatarStyle: DedaPreferences.profileAvatarStyle,
                    frameStyle: frameStyle,
                    size: 124,
                  ),
                ),'''
if text.count(public_avatar) != 1:
    raise SystemExit(f'public preview avatar block count={text.count(public_avatar)}')
text = text.replace(public_avatar, public_avatar_new, 1)

style_equip = '''    await DedaPreferences.setProfileAppearance(
      avatarStyle: DedaPreferences.profileAvatarStyle,
      frameStyle: index,
      backgroundStyle: DedaPreferences.profileBackgroundStyle,
    );
    await dedaEnsurePersonalSocialSession();
    if (mounted) setState(() {});'''
style_equip_new = '''    await DedaPreferences.setProfileAppearance(
      avatarStyle: DedaPreferences.profileAvatarStyle,
      frameStyle: index,
      backgroundStyle: DedaPreferences.profileBackgroundStyle,
    );
    DedaProfileAppearanceState.frameNotifier.value = index;
    await dedaEnsurePersonalSocialSession();
    if (mounted) setState(() {});'''
if text.count(style_equip) != 1:
    raise SystemExit(f'style equip block count={text.count(style_equip)}')
text = text.replace(style_equip, style_equip_new, 1)

# The profile page is kept alive by IndexedStack, so explicitly synchronize the
# notifier when it initializes instead of relying on a parent rebuild.
profile_init_marker = '''    unawaited(DedaDiamondsWallet.load());
    unawaited(DedaTaskEngine.initializeForCurrentAccount());'''
# 100263/100269 replaced this block. Synchronization can be inserted directly
# after super.initState() inside the new profile state instead.
profile_state = 'class _DedaProfilePhase2PageState extends State<DedaProfilePhase2Page> {'
profile_pos = text.index(profile_state)
init_pos = text.index('  void initState() {', profile_pos)
super_pos = text.index('    super.initState();', init_pos) + len('    super.initState();')
text = text[:super_pos] + '\n    DedaProfileAppearanceState.syncFromPreferences();' + text[super_pos:]

# Locked prices should look locked, not like active green purchase buttons.
frame_button = '''                          : FilledButton(
                              onPressed: _busy ? null : () => _buyFrame(index),
                              child: Text(price),
                            ),'''
frame_button_new = '''                          : FilledButton(
                              onPressed: _busy || progress.level < minLevel
                                  ? null
                                  : () => _buyFrame(index),
                              child: Text(progress.level < minLevel
                                  ? dedaText('مقفول • مستوى $minLevel',
                                      'Locked • Lv $minLevel')
                                  : price),
                            ),'''
if text.count(frame_button) != 1:
    raise SystemExit(f'frame locked button count={text.count(frame_button)}')
text = text.replace(frame_button, frame_button_new, 1)

badge_button = '''          SizedBox(height: 38,
            child: FilledButton(
              onPressed: _busy ? null : () => _buyBadge(id, level, price, diamonds),
              child: Text(diamonds ? '💎 $price' : '🪙 $price'),
            )),'''
badge_button_new = '''          SizedBox(height: 38,
            child: FilledButton(
              onPressed: _busy || (_progress?.level ?? 1) < level
                  ? null
                  : () => _buyBadge(id, level, price, diamonds),
              child: Text((_progress?.level ?? 1) < level
                  ? dedaText('مقفول • $level', 'Locked • $level')
                  : (diamonds ? '💎 $price' : '🪙 $price')),
            )),'''
if text.count(badge_button) != 1:
    raise SystemExit(f'badge locked button count={text.count(badge_button)}')
text = text.replace(badge_button, badge_button_new, 1)

# ---------------------------------------------------------------------------
# 3) New incoming request badge. Seen IDs are account-scoped and persisted;
#    opening Requests clears only the notification badge, never the request.
# ---------------------------------------------------------------------------
notify_anchor = '''class DedaProfileAppearanceState {
  static final ValueNotifier<int> frameNotifier =
      ValueNotifier<int>(DedaPreferences.profileFrameStyle);

  static void syncFromPreferences() {
    frameNotifier.value = DedaPreferences.profileFrameStyle;
  }
}
'''
notify_code = notify_anchor + r'''

class DedaIncomingRequestNotifications {
  static final ValueNotifier<int> unseenNotifier = ValueNotifier<int>(0);
  static StreamSubscription<List<DedaFriendshipRecord>>? _subscription;
  static Set<String> _seen = <String>{};
  static Set<String> _currentIncoming = <String>{};
  static String _scope = '';

  static String _prefsKey(String scope) =>
      'deda_social_seen_incoming_v1_$scope';

  static Future<void> start() async {
    await stop();
    try {
      final session = await dedaEnsurePersonalSocialSession();
      final scope = DedaBackend.accountKeyForPhone(DedaPreferences.phone).trim();
      _scope = scope.isEmpty ? session.publicId : scope;
      final prefs = await SharedPreferences.getInstance();
      _seen = (prefs.getStringList(_prefsKey(_scope)) ?? const <String>[])
          .toSet();
      _subscription = DedaSocialService.watchRelations(session.uid).listen(
        (relations) {
          _currentIncoming = relations
              .where((item) => item.status == 'pending' &&
                  item.recipientPublicId == session.publicId)
              .map((item) => item.id)
              .toSet();
          unseenNotifier.value =
              _currentIncoming.where((id) => !_seen.contains(id)).length;
        },
        onError: (_) {
          // Keep the previous badge instead of converting a query error into 0.
        },
      );
    } catch (_) {}
  }

  static Future<void> markCurrentIncomingSeen() async {
    if (_scope.isEmpty || _currentIncoming.isEmpty) {
      unseenNotifier.value = 0;
      return;
    }
    _seen.addAll(_currentIncoming);
    if (_seen.length > 250) {
      _seen = _seen.toList().skip(_seen.length - 250).toSet();
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefsKey(_scope), _seen.toList()..sort());
    unseenNotifier.value = 0;
  }

  static Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    _currentIncoming = <String>{};
  }
}
'''
if text.count(notify_anchor) != 1:
    raise SystemExit(f'notification insertion anchor count={text.count(notify_anchor)}')
text = text.replace(notify_anchor, notify_code, 1)

hub_seed = '''class _DedaSocialHubPageState extends State<DedaSocialHubPage> {
  int _selectedIndex = 0;
'''
hub_seed_new = '''class _DedaSocialHubPageState extends State<DedaSocialHubPage> {
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    unawaited(DedaIncomingRequestNotifications.start());
  }

  @override
  void dispose() {
    unawaited(DedaIncomingRequestNotifications.stop());
    super.dispose();
  }
'''
if text.count(hub_seed) != 1:
    raise SystemExit(f'social hub state seed count={text.count(hub_seed)}')
text = text.replace(hub_seed, hub_seed_new, 1)

hub_tap = '''          onTap: () {
            if (_selectedIndex == index) return;
            setState(() => _selectedIndex = index);
          },'''
hub_tap_new = '''          onTap: () {
            if (index == 2) {
              unawaited(
                DedaIncomingRequestNotifications.markCurrentIncomingSeen(),
              );
            }
            if (_selectedIndex == index) return;
            setState(() => _selectedIndex = index);
          },'''
if text.count(hub_tap) != 1:
    raise SystemExit(f'social hub tap count={text.count(hub_tap)}')
text = text.replace(hub_tap, hub_tap_new, 1)

hub_icon = '''                Icon(
                  selected ? tab.selectedIcon : tab.icon,
                  size: 24,
                  color: selected ? _socialBlue : Colors.white,
                ),'''
hub_icon_new = '''                SizedBox(
                  width: 34,
                  height: 28,
                  child: Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.center,
                    children: <Widget>[
                      Icon(
                        selected ? tab.selectedIcon : tab.icon,
                        size: 24,
                        color: selected ? _socialBlue : Colors.white,
                      ),
                      if (index == 2)
                        ValueListenableBuilder<int>(
                          valueListenable:
                              DedaIncomingRequestNotifications.unseenNotifier,
                          builder: (context, unseen, _) {
                            if (unseen <= 0) return const SizedBox.shrink();
                            return PositionedDirectional(
                              top: -3,
                              end: -5,
                              child: Container(
                                constraints: const BoxConstraints(
                                  minWidth: 18,
                                  minHeight: 18,
                                ),
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 4),
                                decoration: const BoxDecoration(
                                  color: Color(0xFFD92D20),
                                  shape: BoxShape.circle,
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  unseen > 99 ? '99+' : '$unseen',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),'''
if text.count(hub_icon) != 1:
    raise SystemExit(f'social hub icon count={text.count(hub_icon)}')
text = text.replace(hub_icon, hub_icon_new, 1)

# Never hide a Firestore query failure behind fake zero counters.
requests_builder = '''              builder: (context, snapshot) {
                final all = snapshot.data ?? const <DedaFriendshipRecord>[];
                final incoming = all
                    .where((item) => item.status == 'pending' &&
                        item.recipientUid == session.uid)
                    .toList();'''
requests_builder_new = '''              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(22),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          const Icon(Icons.cloud_off_rounded,
                              size: 42, color: Color(0xFF9A6700)),
                          const SizedBox(height: 10),
                          Text(
                            dedaText(
                              'تعذر قراءة طلبات الصداقة الآن. أعد فتح الصفحة بعد التأكد من الاتصال.',
                              'Friend requests could not be read. Reopen this page after checking your connection.',
                            ),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Color(0xFF6F5A24),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                final all = snapshot.data ?? const <DedaFriendshipRecord>[];
                final incoming = all
                    .where((item) => item.status == 'pending' &&
                        item.recipientUid == session.uid)
                    .toList();'''
if text.count(requests_builder) != 1:
    raise SystemExit(f'requests builder count={text.count(requests_builder)}')
text = text.replace(requests_builder, requests_builder_new, 1)

# Make opening the page itself authoritative for "seen" even if navigation is
# reached by another future entry point.
requests_init = '''  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {'''
requests_init_new = '''  void initState() {
    super.initState();
    unawaited(DedaIncomingRequestNotifications.markCurrentIncomingSeen());
    _prepare();
  }

  Future<void> _prepare() async {'''
# There can be other identical init blocks; constrain within requests class.
req_start = text.index('class _DedaFriendRequestsPageState')
req_end = text.index('class DedaFriendPublicProfilePage', req_start)
req_scope = text[req_start:req_end]
if req_scope.count(requests_init) != 1:
    raise SystemExit(f'requests init count={req_scope.count(requests_init)}')
req_scope = req_scope.replace(requests_init, requests_init_new, 1)
text = text[:req_start] + req_scope + text[req_end:]

text = text.replace('// DEDA_SOCIAL_SYSTEM_100269',
                    '// DEDA_SOCIAL_SYSTEM_100269\n' + marker, 1)
path.write_text(text, encoding='utf-8')
print('applied consolidated 100270 social UI/wallet fixes')
