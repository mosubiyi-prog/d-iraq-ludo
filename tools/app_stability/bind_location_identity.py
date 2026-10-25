"""Bind location page continuations to their original account and auth lane."""
from bind_auth_runtime import body_range


def once(source, before, after):
    if source.count(before) != 1:
        raise ValueError('Location identity source anchor changed')
    return source.replace(before, after, 1)


def bind(source):
    if '_authAccountEpoch' not in source or '_locationAccountCurrent' in source:
        raise ValueError('Location identity requires auth binding, exactly once')
    for name in ('_DedaShareLocationPageState', '_DedaReceivedLocationsPageState'):
        start = source.index('class ' + name + ' ')
        # Scope to a complete State class, not the similarly named backend APIs.
        from bind_auth_runtime import tokens, pairs
        opening = source.index('{', start)
        ts = tokens(source[opening:])
        end = opening + ts[pairs(ts, True)[0]][2]
        body = source[start:end]
        fields = '''
  final _locationAccount = DedaBackend.accountKeyForPhone(DedaPreferences.phone);
  final _locationEpoch = DedaPreferences._authAccountEpoch;
  bool _locationAccountCurrent() => mounted &&
      (!dedaProtectedSectionEntryEnabled ||
        (DedaPreferences.isLoggedIn && _locationAccount.isNotEmpty &&
         _locationEpoch == DedaPreferences._authAccountEpoch &&
         _locationAccount == DedaBackend.accountKeyForPhone(DedaPreferences.phone)));
  Future<T> _locationEntry<T>(Future<T> Function() action) {
    if (!dedaProtectedSectionEntryEnabled) return action();
    if (!DedaAuthRuntime.enabled) throw StateError('section-entry-requires-auth-runtime');
    return runDedaProtectedSectionEntry<T>(
      controller: DedaAuthRuntime.controller,
      accountKey: () => DedaBackend.accountKeyForPhone(DedaPreferences.phone),
      accountEpoch: () => DedaPreferences._authAccountEpoch,
      isMounted: _locationAccountCurrent, prepare: action,
    );
  }
'''
        body = body[:body.index('{') + 1] + fields + body[body.index('{') + 1:]
        left, right, _, _ = body_range(body, '_loadIdentity')
        method = body[left + 1:right]
        # Capture all profile inputs before the first asynchronous operation.
        method = method.replace('DedaPreferences.phone', 'phone')
        method = method.replace('DedaPreferences.userName', 'name')
        method = method.replace('DedaPreferences.accountType', 'accountType')
        first = method.index('      Map<String, dynamic>? place;')
        last = method.index('      if (!mounted) return;', first)
        preparation = method[first:last]
        # The result stays within the original UI assignment; complete identity
        # preparation, including owner-session restoration, shares one permit.
        preparation = preparation.replace('      final ids = await ', '      return await ')
        preparation = preparation.rstrip().removesuffix(';') + ';\n'
        method = method[:first] + '''      Map<String, dynamic>? place;
      final ids = await _locationEntry<Map<String, String>>(() async {
''' + preparation.replace('      Map<String, dynamic>? place;\n', '') + '''      });
''' + method[last:]
        method = '''
    if (!_locationAccountCurrent()) return;
    final phone = DedaPreferences.phone;
    final name = DedaPreferences.userName;
    final accountType = DedaPreferences.accountType;
''' + method
        method = method.replace('if (!mounted) return;', 'if (!_locationAccountCurrent()) return;')
        method = method.replace('if (mounted) setState', 'if (_locationAccountCurrent()) setState')
        body = body[:left + 1] + method + body[right:]
        if name == '_DedaShareLocationPageState':
            # Capture the request before GPS. A changed account, closed page or
            # changed SDK principal must not send or award a subsequent account.
            body = once(body, '    if (_sending) return;', '''    if (_sending || !_locationAccountCurrent()) return;
    final requestPrincipal = DedaAuthRuntime.capture();
    final shareType = _shareType;
    final durationMinutes = _durationMinutes;
    final approvedPlace = _approvedPlace;
    final personalId = _personalId;
    final placeId = _placeId;
    final senderName = DedaPreferences.userName;''')
            left, right, _, _ = body_range(body, '_send')
            send = body[left + 1:right]
            # Only request use changes; assignment to the busy flag is retained.
            after = send.index('    setState(() => _sending = true);')
            request = send[after:]
            for old, new in [('_shareType', 'shareType'), ('_durationMinutes', 'durationMinutes'),
                             ('_approvedPlace', 'approvedPlace'), ('_personalId', 'personalId'),
                             ('_placeId', 'placeId'), ('DedaPreferences.userName', 'senderName')]:
                request = request.replace(old, new)
            request = once(request, '        if (position == null) return;',
                '        if (!_locationAccountCurrent() || position == null) return;\n        DedaAuthRuntime.checkSnapshot(requestPrincipal);')
            first = request.index('      await DedaBackend.createLocationShare(')
            last = request.index('\n      if (!mounted) return;', first)
            operation = request[first:last]
            operation = once(operation, "      if (shareType == 'current') {",
                "      if (!_locationAccountCurrent()) return;\n      DedaAuthRuntime.check();\n      if (shareType == 'current') {")
            request = request[:first] + '''      await _locationEntry<void>(() async {
        DedaAuthRuntime.checkSnapshot(requestPrincipal);
''' + operation + '\n      });\n' + request[last:]
            send = send[:after] + request
            send = send.replace('if (!mounted) return;', 'if (!_locationAccountCurrent()) return;')
            send = send.replace('if (mounted) setState', 'if (_locationAccountCurrent()) setState')
            body = body[:left + 1] + send + body[right:]
            # Permission prompts stay outside the auth lane and preserve their
            # original behavior, but cannot report into a different account.
            left, right, _, _ = body_range(body, '_currentPosition')
            position = body[left + 1:right].replace('if (mounted)', 'if (_locationAccountCurrent())')
            body = body[:left + 1] + position + body[right:]
        source = source[:start] + body + source[end:]
    return source
