"""Preserve the existing phone/tablet home; fence original launch callbacks.
Only modify the disposable assembled main.dart. Bottom navigation is excluded.
"""
import argparse
import hashlib
import importlib.util
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT/'tools/app_stability'))
from bind_auth_runtime import tokens, pairs
MARK = 'DEDA_STAGE2_HOME_ORIGINAL_ACTION_FENCE'


def one(s, old, new, label):
    if s.count(old) != 1:
        raise ValueError('HOME_SOURCE_STOP:' + label + ':' + str(s.count(old)))
    return s.replace(old, new, 1)


def span(s, marker):
    if s.count(marker) != 1:
        raise ValueError('HOME_SOURCE_STOP:' + marker)
    a = s.index(marker)
    opening = s.index('{', a)
    ts = tokens(s[opening:])
    end = opening + ts[pairs(ts, True)[0]][2]
    return a, end


def home_span(s):
    return span(s, 'class _HomePageState ')


HELPER = '''  // ''' + MARK + '''
  // Use the section's existing account lifetime, not another login.
  VoidCallback _homeAction(VoidCallback action) {
    final epoch = DedaPreferences.stabilityAccountEpoch;
    final account = DedaBackend.accountKeyForPhone(DedaPreferences.phone);
    return () {
      if (!dedaSectionCurrent || !DedaPreferences.isLoggedIn ||
          epoch != DedaPreferences.stabilityAccountEpoch ||
          account != DedaBackend.accountKeyForPhone(DedaPreferences.phone)) return;
      action();
    };
  }

'''
FIELDS = '''  bool _shareIdentityReady = false;
  Stream<int> _homePendingShares = const Stream<int>.empty();
  bool _homePreparingShareIdentity = false;
'''


def wrap_callbacks(s):
    # Exact Dart token boundaries, including nested route builder and commas.
    # Only original tap callbacks, not search text handlers or bottom bar.
    ts = tokens(s)
    match = pairs(ts)
    changes = []
    for i, (word, _, _) in enumerate(ts):
        if word != 'onTap' or i + 2 >= len(ts) or ts[i+1][0] != ':':
            continue
        j = i + 2
        if ts[j][0] == 'onPressed':
            end = j + 1
        elif ts[j][0] == '(' and ts[j+1][0] == ')':
            k = j + 2
            if ts[k][0] == '{':
                end = match[k] + 1
            else:
                # Preserve expression callback, including Navigator generics.
                if ts[k][0] == '=>':
                    end = k + 1
                elif ts[k][0] == '=' and ts[k+1][0] == '>':
                    end = k + 2
                else:
                    raise ValueError('HOME_SOURCE_STOP:callback-form')
                while end < len(ts) and ts[end][0] not in (',', ')', '}', ';'):
                    end = match[end] + 1 if end in match else end + 1
        else:
            raise ValueError('HOME_SOURCE_STOP:unexpected-tap:' + ts[j][0])
        changes.append((ts[j][1], ts[end-1][2]))
    for a,z in reversed(changes):
        s = s[:a] + '_homeAction(' + s[a:z] + ')' + s[z:]
    return s, len(changes)


def visual_signature(s):
    # Preserve literal colors, icons and art references, including ordering.
    return re.findall(r'Color\(0x[0-9A-Fa-f]+\)|Icons\.\w+|AssetImage\([^\n]+\)', s)


def bottom_parts(s):
    return (s[s.index('    void openBottomDestination('):s.index('    Widget topAction(')],
            s[s.index('    Widget premiumBottomItem('):s.index('    final map = category(')],
            s[s.index('      bottomNavigationBar: SafeArea('):])


def patch_home(body):
    if MARK in body or 'DedaSectionState<HomePage>' not in body:
        raise ValueError('HOME_SOURCE_STOP:existing-section-guard')
    original = body
    bottom = bottom_parts(body)
    body = one(body, '  bool _shareIdentityReady = false;\n', FIELDS + '\n' + HELPER, 'existing-share-state')
    body = one(body, '  Future<void> _initializeShareIdentity() async {',
        '  Future<void> _initializeShareIdentity() async {\n'
        '    if (!dedaSectionCurrent || _homePreparingShareIdentity) return;\n'
        '    _homePreparingShareIdentity = true;\n'
        '    final accountEpoch = DedaPreferences.stabilityAccountEpoch;\n'
        '    final phone = DedaPreferences.phone;\n'
        '    final name = DedaPreferences.userName;\n'
        '    final accountType = DedaPreferences.accountType;\n'
        '    bool current() => dedaSectionCurrent && DedaPreferences.isLoggedIn &&\n'
        '        accountEpoch == DedaPreferences.stabilityAccountEpoch &&\n'
        '        phone == DedaPreferences.phone;', 'one-home-preparation')
    a,z = span(body, '  Future<void> _initializeShareIdentity() async ')
    init = body[a:z]
    # Existing async section guard remains the authority across awaits.
    # Keep local inputs fixed across owner-place and share ID preparation.
    k = init.index('Map<String, dynamic>? place;')
    init = init[:k] + init[k:].replace('DedaPreferences.accountType', 'accountType').replace(
        'DedaPreferences.phone', 'phone').replace('DedaPreferences.userName', 'name')
    init = one(init, 'setState(() => _shareIdentityReady = true);',
        '''if (!current()) return;
        // Reuse the same count stream for ordinary rebuilds and rotation.
        // A refresh after settings does not resubscribe for an unchanged owner.
        if (!_shareIdentityReady) {
          final recipient = DedaBackend.personalShareIdForPhone(phone);
          final principal = DedaAuthRuntime.capture();
          final stream = DedaBackend.pendingLocationSharesCountStream(recipient)
              .where((_) {
                if (!current()) return false;
                try { DedaAuthRuntime.checkSnapshot(principal); return true; }
                catch (_) { return false; }
              });
          setState(() {
            _homePendingShares = stream;
            _shareIdentityReady = true;
          });
        }''', 'stable-original-count')
    # The previously generated guard returns dedaRunSectionVoid. Attach
    # cleanup to the whole future, not just successful completion.
    init = one(init, 'return dedaRunSectionVoid(() async {',
        'try {\n    return await dedaRunSectionVoid(() async {', 'existing-async-guard')
    end = init.rfind('});')
    if end < 0 or init[end+3:].strip() != '}':
        raise ValueError('HOME_SOURCE_STOP:initialize-guard-end')
    init = init[:end+3] + '\n    } finally { _homePreparingShareIdentity = false; }\n  }'
    body = body[:a] + init + body[z:]
    pattern = r'stream: _shareIdentityReady\s*\?\s*DedaBackend\s*\.\s*pendingLocationSharesCountStream\(\s*DedaBackend\s*\.\s*personalShareIdForPhone\(\s*DedaPreferences\.phone,\s*\),\s*\)\s*:\s*Stream<int>\.value\(0\),'
    body, count = re.subn(pattern, 'stream: _homePendingShares,', body)
    if count != 2:
        raise ValueError('HOME_SOURCE_STOP:both-original-notification-builders:' + str(count))
    # Three reusable card builders plus the app bar and body. No bottom
    # navigation code, including its own launch/return callbacks, is touched.
    a = body.index('    Widget topAction(')
    z = body.index('    Widget premiumBottomItem(', a)
    wrapped, helper_count = wrap_callbacks(body[a:z])
    body = body[:a] + wrapped + body[z:]
    a = body.index('      appBar: AppBar(', body.index('    final map = category('))
    z = body.index('      bottomNavigationBar: SafeArea(', a)
    wrapped, body_count = wrap_callbacks(body[a:z])
    body = body[:a] + wrapped + body[z:]
    if helper_count != 3 or body_count < 6:
        raise ValueError('HOME_SOURCE_STOP:tap-coverage')
    for entry in ('void openCategory(DedaCategoryData category) {',
                  'void openPlaceSearch() {',
                  'void openSavedPlaces({required bool favorites}) {',
                  'void openDedaAssistant() {'):
        body = one(body, entry, entry + '\n    if (!dedaSectionCurrent) return;', 'direct-route:' + entry)
    if bottom_parts(body) != bottom:
        raise ValueError('HOME_SOURCE_STOP:bottom-navigation-modified')
    if visual_signature(body) != visual_signature(original):
        raise ValueError('HOME_SOURCE_STOP:visual-literals-modified')
    verify_home(body)
    return body


def verify_home(body):
    for marker, count in (
        (MARK, 1), ('DedaSectionState<HomePage>', 1),
        ('stream: _homePendingShares,', 2),
        ('DedaBackend.pendingLocationSharesCountStream(recipient)', 1),
        ('DedaLeaderboardHomeCard(', 2), ('DedaWeeklyAccountViewGate(', 2),
        ('const DedaReceivedLocationsPage()', 2), ('const DedaShareLocationPage()', 2),
        ('onPressed: openDedaAssistant', 2),
        ("AssetImage('assets/deda_home_bg.jpg')", 1),
        ('onTap: _homeAction(onPressed)', 2),
        ('onTap: _homeAction(() => openCategory(item))', 1),
    ):
        if body.count(marker) != count:
            raise ValueError('HOME_VERIFY:' + marker + ':' + str(body.count(marker)))
    for marker in ('if (!current()) return false;', 'DedaAuthRuntime.checkSnapshot(principal)',
                   '_homePreparingShareIdentity = false;', 'accountEpoch == DedaPreferences.stabilityAccountEpoch',
                   'DedaPlaceSearchPage(initialQuery: query)', 'SavedPlacesPage(showFavorites: favorites)',
                   'const OwnerPlacePage()', 'const PersonalPlacesPage()', 'const MapReadyPage()',
                   'NearbyPlacesPage(category: category)', 'const DedaTeamPage()',
                   'DedaContactPage(', 'const DedaDailyTasksPage()', 'DedaPreferences.accountType == DedaAccountType.placeOwner',
                   'MediaQuery.of(context)', 'Orientation.landscape', 'DedaCategoryData(Icons.restaurant,'):
        if marker not in body:
            raise ValueError('HOME_VERIFY:' + marker)
    if 'categoryCard(restaurant)' in body or 'stream: _shareIdentityReady' in body:
        raise ValueError('HOME_VERIFY:retired-restaurant-or-recreated-stream')
    # All tap entrypoints in the body are the same original callbacks,
    # enclosed in our account-lifetime wrapper. Bottom stays separate.
    a = body.index('      appBar: AppBar(', body.index('    final map = category('))
    z = body.index('      bottomNavigationBar: SafeArea(', a)
    ts = tokens(body[a:z])
    for i,(word,_,_) in enumerate(ts):
        if word == 'onTap' and ts[i+1][0] == ':' and ts[i+2][0] != '_homeAction':
            raise ValueError('HOME_VERIFY:unfenced-body-tap')
    return True


def archive_reference():
    path = ROOT/'tools/app_stability/app_package/bind_stage2_profile_owner_2026_11_23.py'
    spec = importlib.util.spec_from_file_location('profile_archive', path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod.archived_profile_member('lib/main.dart')


def verify_reference(body, original):
    # Compare the unchanged card helpers and original category definition
    # with the authenticated archive. The separately approved leaderboard
    # replaces only the restaurant shortcut (not the map category).
    a,z = home_span(original)
    reference = original[a:z]
    for first,last in (('  final List<DedaCategoryData> _baseCategories', '  void openCategory('),
                       ('    Widget topAction(', '    Widget categoryCard(')):
        old = reference[reference.index(first):reference.index(last)]
        new = body[body.index(first):body.index(last)]
        if visual_signature(old) != visual_signature(new):
            raise ValueError('HOME_REFERENCE:visual-parity:' + first)
    if body.count("AssetImage('assets/deda_home_bg.jpg')") != reference.count("AssetImage('assets/deda_home_bg.jpg')"):
        raise ValueError('HOME_REFERENCE:background-parity')


def bind(project, verify_only=False):
    project = Path(project).resolve()
    if project == ROOT or ROOT in project.parents or project in ROOT.parents:
        raise ValueError('HOME_DO_NOT_MODIFY_REPOSITORY')
    path = project/'lib/main.dart'
    original = path.read_text()
    a,z = home_span(original)
    body = original[a:z] if verify_only else patch_home(original[a:z])
    verify_home(body)
    verify_reference(body, archive_reference())
    if not (project/'assets/deda_home_bg.jpg').is_file():
        raise ValueError('HOME_VERIFY:background-asset-missing')
    if not verify_only:
        path.write_text(original[:a] + body + original[z:])
    print('PASS_STAGE2_HOME_BOTH_LAYOUTS_ORIGINAL_CARD_ROUTES_COLORS_BACKGROUND_SHARED_SESSION_BOTTOM_UNCHANGED')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('project', type=Path)
    parser.add_argument('--verify-only', action='store_true')
    args = parser.parse_args()
    bind(args.project, args.verify_only)
