"""Bind original social entry preparations to the EXISTING auth runtime."""
from pathlib import Path


def once(source, before, after):
    if source.count(before) != 1:
        raise ValueError('Section entry source anchor changed')
    return source.replace(before, after, 1)


def bind(source):
    if 'static int _authAccountEpoch = 0;' not in source:
        raise ValueError('Section entry requires complete auth runtime binding')
    if 'dedaPrepareSocialSectionEntry' in source:
        raise ValueError('Section entry already bound')
    header = 'Future<DedaSocialSession> dedaEnsurePersonalSocialSession() async {'
    start = source.index(header)
    end = source.index('\nFuture<void> dedaRefreshFriendCount()', start)
    body = source[start:end]
    for old, new in [
        ('await DedaPreferences.restoreProfileAppearanceFromAccount();',
         'await DedaAuthRuntime.wait(DedaPreferences.restoreProfileAppearanceFromAccount);'),
        ('await DedaSocialProgressWallet.load();',
         'await DedaAuthRuntime.wait(DedaSocialProgressWallet.load);'),
        ('await DedaStyleInventory.load();',
         'await DedaAuthRuntime.wait(DedaStyleInventory.load);'),
        ('return DedaSocialService.ensurePersonalSession(',
         'return DedaAuthRuntime.wait(() => DedaSocialService.ensurePersonalSession('),
        ('badges: inventory.activeBadges.toList(),\n  );',
         'badges: inventory.activeBadges.toList(),\n  ));'),
    ]:
        body = once(body, old, new)
    helper = '''Future<DedaSocialSession> dedaPrepareSocialSectionEntry(
    bool Function() isMounted) {
  if (!dedaProtectedSectionEntryEnabled) return dedaEnsurePersonalSocialSession();
  if (!DedaAuthRuntime.enabled) {
    throw StateError('section-entry-requires-auth-runtime');
  }
  return runDedaProtectedSectionEntry<DedaSocialSession>(
    controller: DedaAuthRuntime.controller,
    accountKey: () => DedaBackend.accountKeyForPhone(DedaPreferences.phone),
    accountEpoch: () => DedaPreferences._authAccountEpoch,
    isMounted: () => isMounted() && DedaPreferences.isLoggedIn,
    prepare: dedaEnsurePersonalSocialSession,
  );
}

'''
    source = source[:start] + helper + body + source[end:]
    for class_name, next_class in [
        ('_DedaFriendsPageState', 'class DedaAddFriendPage'),
        ('_DedaAddFriendPageState', 'class DedaFriendRequestsPage'),
        ('_DedaFriendRequestsPageState', 'class DedaFriendPublicProfilePage'),
    ]:
        start = source.index('class ' + class_name + ' ')
        end = source.index(next_class, start)
        section = source[start:end]
        section = once(section, 'await dedaEnsurePersonalSocialSession();',
                       'await dedaPrepareSocialSectionEntry(() => mounted);')
        if class_name == '_DedaFriendRequestsPageState':
            section = once(section, '  DedaSocialSession? _session;',
                           '  DedaSocialSession? _session;\n  Object? _entryError;')
            section = once(section, '  Future<void> _prepare() async {\n    try {',
                           '  Future<void> _prepare() async {\n    if (mounted) setState(() => _entryError = null);\n    try {')
            section = once(section, '    } catch (_) {}\n  }',
                           '    } catch (error) {\n      if (mounted) setState(() => _entryError = error);\n    }\n  }')
            section = once(section,
                '          ? const Center(child: CircularProgressIndicator())',
                '''          ? Center(child: _entryError == null
              ? const CircularProgressIndicator()
              : FilledButton.icon(
                  onPressed: _prepare,
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(dedaText('إعادة المحاولة', 'Retry')),
                ))''')
        source = source[:start] + section + source[end:]
    first_import = source.index('import ')
    return source[:first_import] + "import 'deda_protected_section_entry.dart';\n" + source[first_import:]


def bind_directory(output):
    from bind_location_entries import bind as bind_location
    path = Path(output) / 'lib/main.dart'
    path.write_text(bind_location(bind(path.read_text())))
