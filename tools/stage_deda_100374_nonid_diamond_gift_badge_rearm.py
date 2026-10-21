#!/usr/bin/env python3
"""DEDA 100374: repair old diamond-gift nav badge lifecycle ONLY.

Run on exact reconstructed 100373 final Flutter source AFTER Stage75.
- Same server diamond gift stream and already-defined status='pending'.
- Original canonical personal ID remains internal, never change sender/receiver.
- Restart read-only badge after Firebase auth becomes ready, UID change, resume.
- Drop stale old-account stream callbacks. No Firestore writes, notifications
  fabricated from local device or wallet/gift/identifier mutation.
"""
from pathlib import Path

MAIN = Path('lib/main.dart')
MARK = '// DEDA_100374_DIAMOND_GIFT_BADGE_AUTH_RESUME_REARM_NO_DEPLOY'
INBOX_START = 'class DedaGiftInbox {'
INBOX_END = '// DEDA_GIFT_NAV_BADGE_FIX_100271'
NAV_START = 'class _DedaGiftNavBadgeState extends State<DedaGiftNavBadge> {'
NAV_END = 'class DedaMyGiftsPage extends StatefulWidget {'

NEW_INBOX = r"""class DedaGiftInbox {
  static final ValueNotifier<int> pendingNotifier = ValueNotifier<int>(0);
  static StreamSubscription<List<Map<String, dynamic>>>? _subscription;
  static String _publicId = '';
  static String? _accountUid;
  static int _generation = 0;

  // This is the existing read-only canonical original-ID gift query. Never
  // accept a display alias as a routing ID or manufacture a pending receipt.
  static Future<void> start() async {
    String? uid;
    try {
      if (Firebase.apps.isNotEmpty) {
        uid = FirebaseAuth.instance.currentUser?.uid;
      }
    } catch (_) {
      uid = null; // widget tests and incomplete Firebase startup
    }
    final publicId =
        DedaBackend.personalShareIdForPhone(DedaPreferences.phone).trim();
    if (uid == null ||
        !RegExp(r'^@DEDA-[A-Z0-9]{6}$').hasMatch(publicId)) {
      ++_generation;
      await _subscription?.cancel();
      _subscription = null;
      _publicId = '';
      _accountUid = null;
      pendingNotifier.value = 0;
      return;
    }
    if (_subscription != null && _publicId == publicId &&
        _accountUid == uid) return;
    final generation = ++_generation;
    await _subscription?.cancel();
    _subscription = null;
    if (generation != _generation ||
        FirebaseAuth.instance.currentUser?.uid != uid) {
      return; // an overlapping login/account switch superseded this refresh
    }
    _publicId = publicId;
    _accountUid = uid;
    pendingNotifier.value = 0;
    _subscription = DedaBackend.watchPersonalDiamondGifts(publicId).listen(
      (gifts) {
        if (_generation != generation || _publicId != publicId ||
            _accountUid != uid ||
            FirebaseAuth.instance.currentUser?.uid != uid) {
          return; // old account cannot display its gifts in a new session
        }
        pendingNotifier.value = gifts
            .where((gift) => (gift['status'] ?? '').toString() == 'pending')
            .length;
      },
      onError: (_) {
        // No fabricated badge on network/rules errors; preserve last verified.
      },
    );
  }
}

"""
NEW_NAV_HEAD = r"""class _DedaGiftNavBadgeState extends State<DedaGiftNavBadge>
    with WidgetsBindingObserver {
  // DEDA_100374_DIAMOND_GIFT_BADGE_AUTH_RESUME_REARM_NO_DEPLOY
  StreamSubscription<User?>? _accountAuth;

  bool get _firebaseReady {
    try {
      return Firebase.apps.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  void _rearmGiftBadges() {
    if (!mounted || !_firebaseReady) return;
    unawaited(DedaGiftInbox.start());
    unawaited(DedaStage75UnreadGiftBadge.start(
      DedaBackend.personalShareIdForPhone(DedaPreferences.phone).trim(),
    ));
  }

  void _watchAccountIfReady() {
    if (!mounted || _accountAuth != null || !_firebaseReady) return;
    _accountAuth = FirebaseAuth.instance.authStateChanges().listen((_) {
      _rearmGiftBadges();
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _watchAccountIfReady();
    _rearmGiftBadges();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _watchAccountIfReady();
      _rearmGiftBadges();
    });
    // A one-time delayed rearm covers late asynchronous profile/phone startup.
    // Do NOT poll, auto-claim, or send notifications for historical receipts.
    unawaited(Future<void>.delayed(
      const Duration(milliseconds: 1500), () {
        if (!mounted) return;
        _watchAccountIfReady();
        _rearmGiftBadges();
      },
    ));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _watchAccountIfReady();
      _rearmGiftBadges();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _accountAuth?.cancel();
    super.dispose();
  }

"""
def apply(source: str) -> str:
    if MARK in source:
        if source.count(MARK) != 1 or source.count("_rearmGiftBadges()") < 3:
            raise ValueError('SAFE_STOP_100374_BADGE_PARTIAL')
        return source
    if source.count(INBOX_START) != 1 or source.count(INBOX_END) != 1 or \
       source.count(NAV_START) != 1 or source.count(NAV_END) != 1:
        raise ValueError('SAFE_STOP_100374_REAL_SOURCE_ANCHORS')
    if "final pending = diamondPending + idPending;" not in source or \
       source.count("DedaBackend.watchPersonalDiamondGifts(publicId).listen(") != 1:
        raise ValueError('SAFE_STOP_100374_STAGE75_PENDING_WATCHER_MISSING')
    a = source.index(INBOX_START)
    b = source.index(INBOX_END, a)
    old_inbox = source[a:b]
    for required in ("static Future<void> start() async {",
                     "pendingNotifier.value = 0;",
                     "((gift['status'] ?? '').toString() == 'pending')"):
        if required not in old_inbox and required != "((gift['status'] ?? '').toString() == 'pending')":
            raise ValueError('SAFE_STOP_100374_DIAMOND_WATCHER_DRIFT')
    if "DedaBackend.watchPersonalDiamondGifts(publicId).listen(" not in old_inbox:
        raise ValueError('SAFE_STOP_100374_SERVER_QUERY_DRIFT')
    source = source[:a] + NEW_INBOX + source[b:]
    a = source.index(NAV_START)
    b = source.index(NAV_END, a)
    nav = source[a:b]
    build_anchor = "  @override\n  Widget build(BuildContext context) {"
    if nav.count(build_anchor) != 1 or \
       nav.count("unawaited(DedaGiftInbox.start());") != 1 or \
       nav.count("DedaStage75UnreadGiftBadge.start(") != 1 or \
       nav.count("final pending = diamondPending + idPending;") != 1:
        raise ValueError('SAFE_STOP_100374_NAV_STRUCTURE_DRIFT')
    nav = NEW_NAV_HEAD + nav[nav.index(build_anchor):]
    result = source[:a] + nav + source[b:]
    if result.count(MARK) != 1 or \
       result.count("final pending = diamondPending + idPending;") != 1 or \
       result.count("DedaBackend.watchPersonalDiamondGifts(publicId).listen(") != 1:
        raise ValueError('SAFE_STOP_100374_WRONG_SCOPE')
    return result

if __name__ == '__main__':
    before = MAIN.read_text()
    updated = apply(before)
    if updated == before:
        raise SystemExit('SAFE_STOP_100374_NOT_APPLIED')
    MAIN.write_text(updated)
    print('PASS_100374_DIAMOND_BADGE_REARM_AUTH_AND_RESUME_ONLY')
    print('PASS_100374_NO_NEW_FIRESTORE_WRITES_NO_ID_OR_WALLET_MUTATION')
