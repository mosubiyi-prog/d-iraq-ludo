from pathlib import Path

main_path = Path('lib/main.dart')
backend_path = Path('lib/deda_backend.dart')
main = main_path.read_text(encoding='utf-8')
backend = backend_path.read_text(encoding='utf-8')

# 1) Backend: resolve the role from the protected per-account admin gateway.
backend_marker = """  // After an admin signs in, verify that the DEDA phone which opened the
  // gateway is allowed to use this specific admin identity.
"""
backend_method = """  /// Returns true only when the current DEDA phone is explicitly tied to
  /// an active general-manager gateway/member record. This intentionally
  /// fails closed; profile names or local UI state never grant the privilege.
  static Future<bool> currentDedaAccountIsGeneralManager({
    required String phone,
  }) async {
    if (!isReady) return false;
    final accountKey = _adminEntryAccountKeyForPhone(phone);
    if (accountKey.isEmpty) return false;

    try {
      final authUser = FirebaseAuth.instance.currentUser;
      if (authUser == null || authUser.isAnonymous) {
        await DedaPinAuth.restoreTrustedSessionForAccountKey(accountKey);
      } else if (!await currentUserIsAdmin()) {
        return false;
      }

      final access = await FirebaseFirestore.instance
          .collection('admin_entry_access')
          .doc(accountKey)
          .get();
      final data = access.data();
      if (!access.exists ||
          data == null ||
          data['accountKey'] != accountKey ||
          !_adminEntryAccessVisible(data)) {
        return false;
      }

      final accessType =
          (data['accessType'] ?? '').toString().trim().toLowerCase();
      final allowedRole = normalizeAdminRole(
        data['allowedRole'] ?? data['role'],
      );
      return accessType == 'general_manager_gateway' ||
          allowedRole == 'general_manager';
    } catch (_) {
      return false;
    }
  }

""" + backend_marker
if backend.count(backend_marker) != 1:
    raise SystemExit(f'Expected backend admin-session marker once, found {backend.count(backend_marker)}')
backend = backend.replace(backend_marker, backend_method, 1)

# 2) Point engine: keep earned points untouched, and add a session-only
# 1,000,000-point general-manager bonus after protected role verification.
constants_old = """  static const int pointsPerDailyLogin = 10;
  static const int _storeVersion = 1;
  static const int _maxLedgerEntries = 600;
"""
constants_new = """  static const int pointsPerDailyLogin = 10;
  static const int generalManagerBonusPoints = 1000000;
  static const int _storeVersion = 1;
  static const int _maxLedgerEntries = 600;
"""
if main.count(constants_old) != 1:
    raise SystemExit(f'Expected task constants block once, found {main.count(constants_old)}')
main = main.replace(constants_old, constants_new, 1)

loaded_old = """  static String _loadedAccountKey = '';

  static String _accountKey() =>
"""
loaded_new = """  static String _loadedAccountKey = '';
  static bool _generalManagerBonusActive = false;

  static String _accountKey() =>
"""
if main.count(loaded_old) != 1:
    raise SystemExit(f'Expected loaded-account block once, found {main.count(loaded_old)}')
main = main.replace(loaded_old, loaded_new, 1)

# All six existing balance reads should now include the verified manager bonus.
raw_total_expr = '_totalFromState(state)'
raw_count = main.count(raw_total_expr)
if raw_count != 6:
    raise SystemExit(f'Expected 6 task balance reads before helper insertion, found {raw_count}')
main = main.replace(raw_total_expr, '_effectiveTotalFromState(state)')

total_method_marker = """  /// Development cycle id. Weekly definitions will later supply their own
"""
total_helper = """  static int _effectiveTotalFromState(Map<String, dynamic> state) {
    final earned = _totalFromState(state);
    return earned +
        (_generalManagerBonusActive ? generalManagerBonusPoints : 0);
  }

  static Future<void> _refreshGeneralManagerBonus(String accountKey) async {
    final isGeneralManager =
        await DedaBackend.currentDedaAccountIsGeneralManager(
      phone: DedaPreferences.phone,
    );
    if (_loadedAccountKey != accountKey) return;

    _generalManagerBonusActive = isGeneralManager;
    final prefs = await SharedPreferences.getInstance();
    final state = await _readState(prefs, accountKey);
    if (_loadedAccountKey != accountKey) return;
    totalPointsNotifier.value = _effectiveTotalFromState(state);
    revisionNotifier.value++;
  }

""" + total_method_marker
if main.count(total_method_marker) != 1:
    raise SystemExit(f'Expected cycle marker once, found {main.count(total_method_marker)}')
main = main.replace(total_method_marker, total_helper, 1)

init_old = """  static Future<void> initializeForCurrentAccount() async {
    final accountKey = _accountKey();
    _loadedAccountKey = accountKey;
    if (accountKey.isEmpty) {
      totalPointsNotifier.value = 0;
      revisionNotifier.value++;
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final state = await _readState(prefs, accountKey);
    if (_loadedAccountKey != accountKey) return;
    totalPointsNotifier.value = _effectiveTotalFromState(state);
    revisionNotifier.value++;
  }

  static void clearSessionView() {
    _loadedAccountKey = '';
    totalPointsNotifier.value = 0;
    revisionNotifier.value++;
  }
"""
init_new = """  static Future<void> initializeForCurrentAccount() async {
    final accountKey = _accountKey();
    _loadedAccountKey = accountKey;
    _generalManagerBonusActive = false;
    if (accountKey.isEmpty) {
      totalPointsNotifier.value = 0;
      revisionNotifier.value++;
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final state = await _readState(prefs, accountKey);
    if (_loadedAccountKey != accountKey) return;
    totalPointsNotifier.value = _effectiveTotalFromState(state);
    revisionNotifier.value++;

    // Do not hold app startup on a network role lookup. The protected admin
    // gateway is checked immediately after the local balance is available,
    // then the notifier refreshes to include the manager-only 1,000,000 bonus.
    unawaited(_refreshGeneralManagerBonus(accountKey));
  }

  static void clearSessionView() {
    _loadedAccountKey = '';
    _generalManagerBonusActive = false;
    totalPointsNotifier.value = 0;
    revisionNotifier.value++;
  }
"""
if main.count(init_old) != 1:
    raise SystemExit(f'Expected task initialization block once, found {main.count(init_old)}')
main = main.replace(init_old, init_new, 1)

main_path.write_text(main, encoding='utf-8')
backend_path.write_text(backend, encoding='utf-8')
print('Applied protected general-manager 1,000,000-point bonus successfully.')
