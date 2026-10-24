"""Hash-bound source overlay for complete authentication lanes; no default activation.

Only exact restored 100380 files accepted. Immutable archive is never changed.
Generated code guards awaited work in auth helpers and joins nested helpers to
one lane. Password dialogs remain outside the lane and capture an SDK epoch.
"""
import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TOKEN = re.compile(r'''//[^\n]*|/\*[\s\S]*?\*/|r?(?:"""[\s\S]*?"""|\x27\x27\x27[\s\S]*?\x27\x27\x27|"(?:\\.|[^"\\])*"|\x27(?:\\.|[^\x27\\])*\x27)|[A-Za-z_$][A-Za-z_0-9$]*|\?\.|=>|[^\s]''')


def tokens(source):
    return [(m.group(), m.start(), m.end()) for m in TOKEN.finditer(source)
            if not m.group().startswith(('//', '/*'))]


def pairs(ts, first_only=False):
    result, stack = {}, []
    for i, (word, _, _) in enumerate(ts):
        if word in ('(', '[', '{'): stack.append((word, i))
        elif word in (')', ']', '}'):
            if not stack or {'(': ')', '[': ']', '{': '}'}[stack[-1][0]] != word:
                raise ValueError('unbalanced Dart source')
            _, start = stack.pop()
            result[start] = i
            if first_only and not stack: return result
    if stack: raise ValueError('unbalanced Dart source')
    return result


def guard_awaits(source):
    """Wrap await unary/postfix expressions, preserving ??/operators/casts.

    Fail closed for unsupported await syntax. Comments and strings are opaque;
    nested calls/closures are token-balanced, not split on their semicolons.
    """
    ts = tokens(source)
    match = pairs(ts)
    insertions = []
    for i, (word, _, _) in enumerate(ts):
        if word != 'await': continue
        j = i + 1
        if ts[j][0] == 'for': raise ValueError('await-for is outside auth overlay')
        start = ts[j][1]
        if ts[j][0] == '(':
            j = match[j] + 1
        elif re.fullmatch(r'[A-Za-z_$][A-Za-z_0-9$]*', ts[j][0]):
            j += 1
        else: raise ValueError('unsupported awaited expression')
        while j < len(ts):
            word = ts[j][0]
            if word in ('.', '?.'):
                if j + 1 >= len(ts) or not re.fullmatch(r'[A-Za-z_$][A-Za-z_0-9$]*', ts[j+1][0]):
                    raise ValueError('unsupported member access')
                j += 2
            elif word in ('(', '['): j = match[j] + 1
            elif word == '!': j += 1
            elif word == '<':
                depth, k = 1, j + 1
                while k < len(ts) and depth:
                    if ts[k][0] == '<': depth += 1
                    if ts[k][0] == '>': depth -= 1
                    if ts[k][0] in (';', '{', '}', '='): break
                    k += 1
                if depth or k >= len(ts) or ts[k][0] not in ('(', '.'):
                    break  # comparison, not a type argument list
                j = k
            else: break
        end = ts[j-1][2]
        insertions += [(start, 'DedaAuthRuntime.wait(() => '), (end, ')')]
    for offset, text in sorted(insertions, reverse=True):
        source = source[:offset] + text + source[offset:]
    return source


def body_range(source, name, *, after=0):
    m = re.search(r'\bFuture<([^;\n]+?)>\s+' + re.escape(name) + r'\s*\(', source[after:])
    if not m: raise ValueError('method missing: ' + name)
    start = after + m.start()
    opening = source.index(' async {', after + m.end()) + len(' async ')
    ts = tokens(source[opening:])
    closing = opening + ts[pairs(ts, True)[0]][1]
    return opening, closing, m.group(1), start


def wrap_method(source, name, kind, *, origin='userAction', after=0):
    opening, closing, result, _ = body_range(source, name, after=after)
    body = source[opening+1:closing]
    return source[:opening+1] + '\n    return DedaAuthRuntime.run<' + result + '>(\n' + \
        '      kind: DedaSessionTransitionKind.' + kind + ',\n' + \
        '      origin: DedaSessionTransitionOrigin.' + origin + ',\n' + \
        '      action: () async {' + body + '\n      });\n  ' + source[closing:]


def once(source, old, new):
    if source.count(old) != 1: raise ValueError('exact auth anchor mismatch: ' + old[:80])
    return source.replace(old, new, 1)


def sdk_calls(source, *, pin=False):
    if pin:
        source = once(source, 'auth.signInAnonymously()\n        .timeout(const Duration(seconds: 12))',
          '(DedaAuthRuntime.enabled ? DedaAuthRuntime.anonymous(auth) :\n'
          '        auth.signInAnonymously().timeout(const Duration(seconds: 12)))')
    else:
        source = once(source, 'auth.signInAnonymously()', 'DedaAuthRuntime.anonymous(auth)')
        source = once(source, 'FirebaseAuth.instance.signInWithEmailAndPassword(',
          'DedaAuthRuntime.email(FirebaseAuth.instance,')
        source = once(source, 'auth.createUserWithEmailAndPassword(', 'DedaAuthRuntime.createAdmin(auth,')
        source = once(source, 'await user.delete();', 'await DedaAuthRuntime.deleteUser(user);')
    source = source.replace('await auth.signOut();', 'await DedaAuthRuntime.signOut(auth);')
    source = source.replace('await FirebaseAuth.instance.signOut();', 'await DedaAuthRuntime.signOut(FirebaseAuth.instance);')
    return source


def bind_pin(source):
    source = sdk_calls(source, pin=True)
    source = guard_awaits(source)
    for name, kind, origin in [
        ('accountExists', 'sessionInspection', 'activeSection'),
        ('restoreTrustedSessionForAccountKey', 'sessionInspection', 'activeSection'),
        ('createAccount', 'accountCreate', 'userAction'),
        ('signIn', 'ownerLogin', 'userAction'),
        ('markCurrentDeviceTrusted', 'sessionInspection', 'activeSection'),
        ('requestRecovery', 'ownerLogin', 'userAction'),
        ('signOutFirebase', 'logout', 'userAction'),
    ]: source = wrap_method(source, name, kind, origin=origin)
    return "import 'deda_auth_session_runtime.dart';\n" + source


def bind_backend(source):
    source = once(source, '''  static Stream<List<Map<String, dynamic>>> ownerPlaceNotificationsStream(
    String accountKey,
  ) {
    final clean = accountKey.trim();
    if (clean.isEmpty) {''', '''  static Stream<List<Map<String, dynamic>>> ownerPlaceNotificationsStream(
    String accountKey,
  ) {
    final clean = accountKey.trim();
    if (clean.isEmpty || (DedaAuthRuntime.enabled && !isReady)) {''')
    opening, closing, _, _ = body_range(source, 'recoverPublishedPlaceForSignedInOwner')
    source = source[:opening+1] + '''
    if (DedaAuthRuntime.enabled) {
      return DedaPublishedPlaceRecovery(DedaFirebasePlaceRecoveryIo()).recover(
        expectedAccountKey: expectedAccountKey,
        isCurrent: () { DedaAuthRuntime.check(); return true; });
    }
''' + source[opening+1:]
    source = once(source, "    if (current == null) throw StateError('deda-session-required');",
      "    if (current == null) throw StateError('deda-session-required');\n    final recoveryRequester = current;")
    source = once(source, "'requesterUid': current.uid,", "'requesterUid': recoveryRequester.uid,")
    source = guard_awaits(sdk_calls(source))
    for name, kind in [('signInAdmin', 'adminLogin'),
        ('activateAdminInvitation', 'adminInviteActivation'),
        ('changeCurrentAdminPassword', 'credentialChange'), ('signOutAdmin', 'logout')]:
        source = wrap_method(source, name, kind)
    for name in ['_ensurePublicUser', '_ensureOwnerSessionForAccountKey',
        'currentDedaAccountCanSeeAdminEntry', 'currentDedaAccountIsGeneralManager',
        'currentAdminSessionMatchesDedaEntry', 'syncCurrentAdminEntryAccessForDedaAccount',
        'currentAdminProfile', 'registerAdminNotifications', '_writeAdminAudit',
        'requestAdminPasswordRecovery', 'recoverPublishedPlaceForSignedInOwner']:
        source = wrap_method(source, name, 'sessionInspection', origin='activeSection')
    return "import 'deda_auth_session_runtime.dart';\nimport 'deda_published_place_recovery.dart';\n" + source


def wrap_ui_try(source, name, kind, *, after=0):
    opening, closing, _, _ = body_range(source, name, after=after)
    body = source[opening+1:closing]
    start = body.index('    try {') + len('    try {')
    # Lexically pair the try block; catch bodies remain outside the lane.
    ts = tokens(body[start-1:])
    end = start - 1 + ts[pairs(ts, True)[0]][1]
    inner = guard_awaits(body[start:end])
    wrapped = '\n      await DedaAuthRuntime.run<void>(\n' + \
      '        kind: DedaSessionTransitionKind.' + kind + ', isCurrent: () => mounted,\n' + \
      '        action: () async {' + inner + '\n        });\n    '
    body = body[:start] + wrapped + body[end:]
    return source[:opening+1] + body + source[closing:]


def guard_local_account_commits(source):
    """Keep legacy behavior disabled; publish enabled login after checked IO.

    The existing logged-in flag is a commit marker, not owner/admin proof.
    Partial identity writes stay signed out on a subsequent native reload.
    Source progress/appearance ownership records are never removed or reset.
    """
    opening, closing, _, _ = body_range(source, 'saveLogin')
    original = source[opening+1:closing]
    publish = '''    userName = resolvedName;
    phone = normalizedPhone;
    accountPhone = normalizedPhone;
    accountType = type;
    isLoggedIn = true;'''
    safe = once(original, publish, '''    isLoggedIn = false;
    if (!await prefs.setBool(_loggedInKey, false)) {
      throw StateError('account-local-save-failed');
    }''')
    safe = once(safe, '    profileAvatarStyle =', '    final savedAvatarStyle =')
    safe = once(safe, '    profileFrameStyle =', '    final savedFrameStyle =')
    safe = once(safe, '    profileBackgroundStyle =', '    final savedBackgroundStyle =')
    writes = '''    await Future.wait([
      prefs.setString(_userNameKey, resolvedName),
      prefs.setString(_phoneKey, normalizedPhone),
      prefs.setString(_accountPhoneKey, normalizedPhone),
      prefs.setString(_accountTypeKey, type.name),
      prefs.setBool(_loggedInKey, true),
    ]);'''
    safe = once(safe, writes, '''    final loginWrites = await Future.wait<bool>([
      prefs.setString(_userNameKey, resolvedName),
      prefs.setString(_phoneKey, normalizedPhone),
      prefs.setString(_accountPhoneKey, normalizedPhone),
      prefs.setString(_accountTypeKey, type.name),
    ]);
    if (loginWrites.any((saved) => !saved) ||
        prefs.getString(_userNameKey) != resolvedName ||
        prefs.getString(_phoneKey) != normalizedPhone ||
        prefs.getString(_accountPhoneKey) != normalizedPhone ||
        prefs.getString(_accountTypeKey) != type.name) {
      throw StateError('account-local-save-failed');
    }
    if (!await prefs.setBool(_loggedInKey, true)) {
      throw StateError('account-local-save-failed');
    }
''' + publish + '''
    profileAvatarStyle = savedAvatarStyle;
    profileFrameStyle = savedFrameStyle;
    profileBackgroundStyle = savedBackgroundStyle;''')
    start = safe.index('    unawaited(DedaTaskEngine.initializeForCurrentAccount());')
    safe = safe[:start] + '''    final followupEpoch = _authAccountEpoch;
    unawaited(DedaAuthRuntime.afterSuccess(
      isCurrent: () => isLoggedIn && phone == normalizedPhone &&
        _authAccountEpoch == followupEpoch,
      action: () async {
        await DedaTaskEngine.initializeForCurrentAccount();
        await DedaBackend.syncCurrentUserProfile(
          name: resolvedName, phone: normalizedPhone, accountType: type.name);
      },
    ).catchError((Object _) {}));
'''
    body = '\n    if (!DedaAuthRuntime.enabled) {' + original + '\n      return;\n    }\n' + safe
    source = source[:opening+1] + body + source[closing:]
    opening, closing, _, _ = body_range(source, 'logout')
    original = source[opening+1:closing]
    safe = once(original, '    await prefs.setBool(_loggedInKey, false);\n', '')
    safe = once(safe, '    isLoggedIn = false;', '''    if (!await prefs.setBool(_loggedInKey, false)) {
      throw StateError('account-local-logout-failed');
    }
    isLoggedIn = false;''')
    body = '\n    if (!DedaAuthRuntime.enabled) {' + original + '\n      return;\n    }\n' + safe
    return source[:opening+1] + body + source[closing:]


def bind_owner_place_load(source):
    page = source.index('class _OwnerPlacePageState')
    for name in ['_legacyPlaceBelongsToCurrentAccount', '_migrateLegacyOwnerStorageIfOwned',
                 '_loadDraftOnly', '_resetOwnerAfterDeletedPlace', '_refreshOwnerMetrics']:
        opening, closing, _, _ = body_range(source, name, after=page)
        source = source[:opening+1] + guard_awaits(source[opening+1:closing]) + source[closing:]
    opening, closing, _, _ = body_range(source, '_loadState', after=page)
    body = source[opening+1:closing]
    body = once(body, 'expectedAccountKey: _ownerStorageAccountKey,',
      'expectedAccountKey: recoveryAccountKey,')
    body = once(body, '''            _placeId = recoveredId;
            await prefs.setString(_placeIdKey, recoveredId);''', '''            if (DedaAuthRuntime.enabled) {
              if (!await prefs.setString(recoveryPlaceKey, recoveredId)) {
                throw StateError('owner-recovery-local-save-failed');
              }
              DedaAuthRuntime.check();
              _placeId = recoveredId;
            } else {
              _placeId = recoveredId;
              await prefs.setString(_placeIdKey, recoveredId);
            }''')
    body = once(body, '''    if (mounted && !_loading) {
      await _refreshOwnerMetrics();
    }''', '''    if (mounted && !_loading) {
      if (DedaAuthRuntime.enabled) {
        unawaited(DedaAuthRuntime.afterSuccess(
          isCurrent: () => mounted && recoveryAccountEpoch == DedaPreferences._authAccountEpoch &&
            recoveryAccountKey == _ownerStorageAccountKey,
          action: _refreshOwnerMetrics,
        ).catchError((Object _) {}));
      } else {
        await _refreshOwnerMetrics();
      }
    }''')
    body = guard_awaits(body)
    source = source[:opening+1] + '''
    final recoveryIdentity = DedaAuthRuntime.capture();
    final recoveryAccountEpoch = DedaPreferences._authAccountEpoch;
    final recoveryAccountKey = _ownerStorageAccountKey;
    final recoveryPlaceKey = _placeIdKey;
    try {
      await DedaAuthRuntime.forSnapshot<void>(recoveryIdentity,
        kind: DedaSessionTransitionKind.sessionInspection,
        origin: DedaSessionTransitionOrigin.activeSection,
        isCurrent: () => mounted && recoveryAccountEpoch == DedaPreferences._authAccountEpoch &&
          recoveryAccountKey == _ownerStorageAccountKey,
        action: () async {
''' + body + '''
        });
    } catch (error) {
      if (!DedaAuthRuntime.enabled) rethrow;
      if (!mounted) return;
      setState(() {
        _loading = false;
        _status = 'recovery_blocked';
        _ownerRecoveryIssue = error is DedaSessionTransitionBusy
          ? dedaText('توجد عملية حساب جارية. انتظر اكتمالها ثم حدّث حالة مكانك.',
              'An account operation is running. Wait for it to finish and refresh your place.')
          : dedaText('تعذر إكمال التحقق من حساب مكانك. حدّث الحالة بعد التأكد من تسجيل الدخول.',
              'Could not finish verifying your place account. Check your sign-in and refresh.');
      });
    }
''' + source[closing:]
    return source


def bind_main(source):
    source = guard_local_account_commits(source)
    source = once(source, 'class DedaPreferences {', '''class DedaPreferences {
  static int _authAccountEpoch = 0;
''')
    # Preference methods share the UI lane; callbacks still run under original
    # account-specific data code. Their later data migration is a separate stage.
    for name in ['load', 'saveLogin', 'logout', '_loadRoyalSafeAvatarStyle']:
        opening, closing, _, _ = body_range(source, name)
        source = source[:opening+1] + guard_awaits(source[opening+1:closing]) + source[closing:]
    for name, kind in [('load','sessionInspection'),('saveLogin','ownerLogin'),('logout','logout')]:
        opening, _, _, _ = body_range(source, name)
        source = source[:opening+1] + '\n    if (DedaAuthRuntime.enabled) ++_authAccountEpoch;' + source[opening+1:]
        source = wrap_method(source, name, kind)
    opening, closing, _, _ = body_range(source, 'initializeForCurrentAccount',
      after=source.index('class DedaTaskEngine'))
    body = once(source[opening+1:closing],
      '    unawaited(_refreshGeneralManagerBonus(accountKey));', '''    if (DedaAuthRuntime.enabled) {
      final bonusAccountEpoch = DedaPreferences._authAccountEpoch;
      unawaited(DedaAuthRuntime.afterSuccess(
        isCurrent: () => DedaPreferences.isLoggedIn && _loadedAccountKey == accountKey &&
          bonusAccountEpoch == DedaPreferences._authAccountEpoch,
        action: () => _refreshGeneralManagerBonus(accountKey),
      ).catchError((Object _) {}));
    } else {
      unawaited(_refreshGeneralManagerBonus(accountKey));
    }''')
    source = source[:opening+1] + guard_awaits(body) + source[closing:]
    opening, closing, _, _ = body_range(source, '_refreshGeneralManagerBonus',
      after=source.index('class DedaTaskEngine'))
    source = source[:opening+1] + guard_awaits(source[opening+1:closing]) + source[closing:]
    source = bind_owner_place_load(source)
    for name, kind in [('_create','accountCreate'),('_signIn','ownerLogin'),('_enterWithNewPin','ownerLogin')]:
        source = wrap_ui_try(source, name, kind)
    # This older account type flow has no network wait or open-ended dialog.
    source = wrap_method(source, '_continue', 'ownerLogin',
      after=source.index('class _AccountTypePageState'))
    for method, page in [('_logoutPersonalAccount', 'class _DedaSettingsPageState'),
                         ('_logout', 'class _DedaAccountHubPageState')]:
        opening, closing, _, _ = body_range(source, method, after=source.index(page))
        body = source[opening+1:closing]
        body = once(body, '    final confirmed = await showDialog<bool>(',
          '    final logoutIntent = DedaPersonalLogoutIntent();\n    final confirmed = await showDialog<bool>(')
        body = once(body, '    if (confirmed != true) return;',
          '    if (confirmed != true || !mounted) return;')
        body = once(body, '    await DedaPreferences.logout();', '''    try {
      await logoutIntent.commit(isCurrent: () => mounted);
    } catch (error) {
      if (!DedaAuthRuntime.enabled) rethrow;
      if (!mounted) return;
      final busy = error is DedaSessionTransitionBusy;
      final stale = error is DedaStaleSessionTransition;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(dedaText(
        busy ? 'توجد عملية دخول أو خروج جارية. انتظر اكتمالها ثم حاول مجددًا.'
          : stale ? 'تغيّر الحساب أثناء التأكيد. افتح تسجيل الخروج من جديد.'
          : 'تعذر إكمال تسجيل الخروج الآن. تحقق من حالة الحساب ثم حاول مجددًا.',
        busy ? 'A sign-in or sign-out is still running. Wait for it to finish and try again.'
          : stale ? 'The account changed during confirmation. Open sign out again.'
          : 'Could not finish signing out. Check the account state and try again.',
      ))));
      return;
    }''')
        source = source[:opening+1] + body + source[closing:]
    source = once(source, '\nenum DedaTaskEvent {', '''
// A dialog is not an auth reservation. Revalidate its original local selection
// and SDK epoch INSIDE the shared lane before any logout preference/SDK work.
class DedaPersonalLogoutIntent {
  DedaPersonalLogoutIntent()
      : _identity = DedaAuthRuntime.capture(),
        _epoch = DedaPreferences._authAccountEpoch,
        _phone = DedaPreferences.phone;
  final DedaAuthSnapshot? _identity;
  final int _epoch;
  final String _phone;
  Future<void> commit({required bool Function() isCurrent}) =>
    DedaAuthRuntime.forSnapshot<void>(_identity,
      kind: DedaSessionTransitionKind.logout, isCurrent: isCurrent,
      action: () async {
        if (DedaAuthRuntime.enabled && (_epoch != DedaPreferences._authAccountEpoch ||
            _phone != DedaPreferences.phone)) throw const DedaStaleSessionTransition();
        await DedaPreferences.logout();
      });
}

enum DedaTaskEvent {''')
    return "import 'deda_auth_session_runtime.dart';\nimport 'deda_session_transition_gate.dart' show DedaSessionTransitionBusy, DedaStaleSessionTransition;\n" + source


def bind_admin(source):
    # Sign-in, saved identity, server profile and phone match share ONE lane.
    start = source.index('      final allowed = await DedaBackend.signInAdmin(')
    end = source.index("      if (profile['mustChangePassword'] == true)", start)
    block = source[start:end]
    block = once(block, '        return;\n', '        return null;\n') if block.count('        return;\n') == 1 else block.replace('        return;\n', '        return null;\n')
    block = block.replace('if (!mounted) return;', 'if (!mounted) return null;')
    source = source[:start] + '''      final profile = await DedaAuthRuntime.run<Map<String, dynamic>?>(
        kind: DedaSessionTransitionKind.adminLogin, isCurrent: () => mounted,
        action: () async {
''' + guard_awaits(block) + '''          return profile;
        });
      if (profile == null || !mounted) return;
      final loginIdentity = DedaAuthRuntime.capture();
''' + source[end:]
    source = once(source, '          await DedaBackend.signOutAdmin();\n          return;',
      '''          await DedaAuthRuntime.forSnapshot<void>(loginIdentity,
            kind: DedaSessionTransitionKind.logout, isCurrent: () => mounted,
            action: DedaBackend.signOutAdmin);
          return;''')
    source = once(source, "      if (profile['mustChangePassword'] == true) {", "      if (profile['mustChangePassword'] == true) {")
    anchor = '      if (!mounted) return;\n      Navigator.pushReplacement('
    source = once(source, anchor, '      DedaAuthRuntime.checkSnapshot(loginIdentity);\n' + anchor)
    # The dialog must not keep an auth lane busy. Revalidate its original SDK
    # epoch after the user responds; never update a later admin's password.
    source = once(source, '    final first = TextEditingController();\n',
      '    final passwordIdentity = DedaAuthRuntime.capture();\n    final first = TextEditingController();\n')
    source = once(source, '    await DedaBackend.changeCurrentAdminPassword(newPassword);',
      '''    await DedaAuthRuntime.forSnapshot<void>(passwordIdentity,
      kind: DedaSessionTransitionKind.credentialChange, isCurrent: () => mounted,
      action: () => DedaBackend.changeCurrentAdminPassword(newPassword));''')
    source = wrap_ui_try(source, '_activate', 'adminInviteActivation')
    opening, closing, _, _ = body_range(source, '_saveIdentity')
    source = source[:opening+1] + guard_awaits(source[opening+1:closing]) + source[closing:]
    return "import 'deda_auth_session_runtime.dart';\n" + source


def bind(output, *, startup_metrics=False, progress_backup_runtime=False):
    manifest = json.loads((ROOT / 'tools/app_stability/100380-baseline-manifest.json').read_text())
    actions = {'lib/deda_pin_auth.dart': bind_pin, 'lib/deda_backend.dart': bind_backend,
      'lib/main.dart': bind_main, 'lib/admin_pages.dart': bind_admin}
    results = {}
    # Validate all inputs and generate all outputs before writing any file.
    for name, action in actions.items():
        source = (output / name).read_text()
        expected_sha = manifest['files'][name]
        if name == 'lib/main.dart' and (startup_metrics or progress_backup_runtime):
            import importlib.util
            import tarfile
            spec = importlib.util.spec_from_file_location('_deda_exact_restore', ROOT / 'tools/restore_deda_stability_baseline.py')
            restore = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(restore)
            with tarfile.open(ROOT / 'tools/app_stability/100380-baseline.tar.gz') as archive:
                original = archive.extractfile(name).read().decode()
            if hashlib.sha256(original.encode()).hexdigest() != manifest['files'][name]:
                raise ValueError('baseline main drift')
            expected = restore.instrument_startup(original) if startup_metrics else original
            if progress_backup_runtime:
                expected = restore.bind_progress_backup(expected, original, measured=startup_metrics)
            expected_sha = hashlib.sha256(expected.encode()).hexdigest()
        if hashlib.sha256(source.encode()).hexdigest() != expected_sha:
            raise ValueError('auth binding requires exact baseline: ' + name)
        results[name] = action(source)
    for name, result in results.items(): (output / name).write_text(result)
    return {name: hashlib.sha256(result.encode()).hexdigest() for name, result in results.items()}
