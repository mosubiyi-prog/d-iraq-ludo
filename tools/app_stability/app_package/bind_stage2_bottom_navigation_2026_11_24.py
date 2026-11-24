"""Bind the original five home-bottom destinations and the existing gift badges.
Only the temporary assembled app; no change to gifts, account roles or balances.
"""
import argparse
import importlib.util
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location('home_binder', ROOT/'tools/app_stability/app_package/bind_stage2_home_2026_11_24.py')
home = importlib.util.module_from_spec(spec)
spec.loader.exec_module(home)
MARK = 'DEDA_STAGE2_BOTTOM_ORIGINAL_FIVE_ROUTES'
GIFT_MARK = 'DEDA_STAGE2_GIFT_BADGE_ACCOUNT_GENERATION'


def one(s, old, new, label):
    if s.count(old) != 1:
        raise ValueError('BOTTOM_SOURCE_STOP:' + label + ':' + str(s.count(old)))
    return s.replace(old, new, 1)


def patch_home(body):
    if home.MARK not in body or MARK in body:
        raise ValueError('BOTTOM_SOURCE_STOP:previous-home-required')
    before = body
    routes, item, bar = home.bottom_parts(body)
    for marker in ('case 0:', 'const DedaSocialHubPage()', 'case 1:', 'openSettings();',
                   'case 2:', 'case 3:', 'const DedaMyGiftsPage()', 'case 4:', 'const DedaMakaniPage()'):
        if routes.count(marker) != 1:
            raise ValueError('BOTTOM_SOURCE_STOP:original-route:' + marker)
    new = '''    // ''' + MARK + '''
    Future<void> openBottomDestination(int index) async {
      if (!dedaSectionCurrent || !DedaPreferences.isLoggedIn ||
          _bottomRouteOpening || index == 2 || index < 0 || index > 4) return;
      final epoch = DedaPreferences.stabilityAccountEpoch;
      final account = DedaBackend.accountKeyForPhone(DedaPreferences.phone);
      DedaAuthSnapshot? principal;
      try { principal = DedaAuthRuntime.capture(); } catch (_) { return; }
      bool current() {
        if (!dedaSectionCurrent || !DedaPreferences.isLoggedIn ||
            epoch != DedaPreferences.stabilityAccountEpoch ||
            account != DedaBackend.accountKeyForPhone(DedaPreferences.phone)) return false;
        try { DedaAuthRuntime.checkSnapshot(principal); return true; }
        catch (_) { return false; }
      }
      if (!current()) return;
      _bottomRouteOpening = true;
      try {
        switch (index) {
          case 0:
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => current()
                  ? const DedaSocialHubPage() : dedaSectionExpiredView()),
            );
            if (current()) setState(() {});
            break;
          case 1:
            await openSettings();
            break;
          case 2:
            break;
          case 3:
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => current()
                  ? const DedaMyGiftsPage() : dedaSectionExpiredView()),
            );
            break;
          case 4:
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => current()
                  ? const DedaMakaniPage() : dedaSectionExpiredView()),
            );
            if (current()) setState(() {});
            break;
        }
      } finally {
        _bottomRouteOpening = false;
      }
    }

'''
    body = one(body, routes, new, 'existing-bottom-switch')
    body = one(body, '  bool _homePreparingShareIdentity = false;',
        '  bool _homePreparingShareIdentity = false;\n  bool _bottomRouteOpening = false;',
        'single-navigation-lane')
    body = one(body, 'onTap: () => openBottomDestination(index),',
        'onTap: _homeAction(() => openBottomDestination(index)),', 'ordinary-bottom-tap')
    body = one(body, 'onTap: () => openBottomDestination(3),',
        'onTap: _homeAction(() => openBottomDestination(3)),', 'gift-bottom-tap')
    _, new_item, new_bar = home.bottom_parts(body)
    if new_item != item.replace('onTap: () => openBottomDestination(index),',
                               'onTap: _homeAction(() => openBottomDestination(index)),'):
        raise ValueError('BOTTOM_SOURCE_STOP:ordinary-item-appearance')
    if new_bar != bar.replace('onTap: () => openBottomDestination(3),',
                             'onTap: _homeAction(() => openBottomDestination(3)),'):
        raise ValueError('BOTTOM_SOURCE_STOP:bar-appearance')
    if home.visual_signature(before) != home.visual_signature(body):
        raise ValueError('BOTTOM_SOURCE_STOP:home-visual-change')
    # All other home content is exactly unchanged.
    restored = body.replace(new, routes).replace(
        '  bool _homePreparingShareIdentity = false;\n  bool _bottomRouteOpening = false;',
        '  bool _homePreparingShareIdentity = false;').replace(new_item, item).replace(new_bar, bar)
    if restored != before:
        raise ValueError('BOTTOM_SOURCE_STOP:unrelated-home-change')
    verify_home(body)
    return body


def verify_home(body):
    routes, item, bar = home.bottom_parts(body)
    for marker in (MARK, 'if (!current()) return;', '_bottomRouteOpening = true;',
                   '_bottomRouteOpening = false;', 'finally {',
                   'DedaAuthRuntime.checkSnapshot(principal)', 'index == 2',
                   'case 0:', 'const DedaSocialHubPage()', 'case 1:', 'await openSettings();',
                   'case 2:', 'case 3:', 'const DedaMyGiftsPage()', 'case 4:', 'const DedaMakaniPage()'):
        if routes.count(marker) != 1:
            raise ValueError('BOTTOM_VERIFY_ROUTE:' + marker)
    if routes.count('await Navigator.push(') != 3 or routes.count('dedaSectionExpiredView()') != 3:
        raise ValueError('BOTTOM_VERIFY:guarded-route-count')
    if item.count('onTap: _homeAction(() => openBottomDestination(index)),') != 1 or \
       bar.count('onTap: _homeAction(() => openBottomDestination(3)),') != 1:
        raise ValueError('BOTTOM_VERIFY:existing-account-fence')
    labels = re.findall(r"label: dedaText\('([^']+)', '([^']+)'\)", bar)
    if labels != [('حسابي','Account'), ('الإعدادات','Settings'), ('الرئيسية','Home'),
                  ('هداياي','My gifts'), ('مكاني','My place')]:
        raise ValueError('BOTTOM_VERIFY:original-order')
    if bar.count('selected: true,') != 1 or 'height: isLandscape ? 58 : 80,' not in bar:
        raise ValueError('BOTTOM_VERIFY:original-selected-home')
    for marker in ('index: 0,', 'index: 1,', 'index: 2,', 'index: 4,',
                   'Icons.person_outline', 'Icons.settings_outlined', 'Icons.home_outlined',
                   'Icons.storefront_outlined', 'DedaGiftNavBadge(',
                   'Color(0xFF0B3B6F)', 'Color(0xFF061F3E)', 'Color(0xFFE8C56C)'):
        if marker not in bar:
            raise ValueError('BOTTOM_VERIFY:original-bar:' + marker)


def patch_inbox(body):
    if GIFT_MARK in body:
        raise ValueError('BOTTOM_SOURCE_STOP:duplicate-gift-badge')
    body = one(body, '  static int _generation = 0;',
        '  static int _generation = 0;\n'
        '  static int? _accountEpoch;\n'
        '  // ' + GIFT_MARK + '\n'
        '  static Future<void> stop() async {\n'
        '    ++_generation;\n'
        '    final previous = _subscription;\n'
        '    _subscription = null;\n'
        "    _publicId = '';\n"
        '    _accountUid = null;\n'
        '    _accountEpoch = null;\n'
        '    pendingNotifier.value = 0;\n'
        '    try { await previous?.cancel(); } catch (_) {}\n'
        '  }\n\n'
        '  static void accountChanged() {\n'
        '    unawaited(stop());\n'
        '    unawaited(DedaStage75UnreadGiftBadge.stop().catchError((Object _) {}));\n'
        '  }\n', 'existing-generation')
    body = one(body, "    if (uid == null || !RegExp(r'^@DEDA-[A-Z0-9]{6}$').hasMatch(publicId)) {",
        "    if (!DedaPreferences.isLoggedIn || uid == null || !RegExp(r'^@DEDA-[A-Z0-9]{6}$').hasMatch(publicId)) {",
        'logged-in-diamond-reader')
    body = one(body, '''      ++_generation;
      await _subscription?.cancel();
      _subscription = null;
      _publicId = '';
      _accountUid = null;
      pendingNotifier.value = 0;
      return;''', '''      await stop();
      return;''', 'invalidate-before-cancel')
    body = one(body, '''    if (_subscription != null && _publicId == publicId && _accountUid == uid)
      return;
    final generation = ++_generation;
    await _subscription?.cancel();
    _subscription = null;
    if (generation != _generation ||
        FirebaseAuth.instance.currentUser?.uid != uid) {
      return; // an overlapping login/account switch superseded this refresh
    }
    _publicId = publicId;
    _accountUid = uid;
    pendingNotifier.value = 0;''', '''    final accountEpoch = DedaPreferences.stabilityAccountEpoch;
    final account = DedaBackend.accountKeyForPhone(DedaPreferences.phone);
    DedaAuthSnapshot? principal;
    try { principal = DedaAuthRuntime.capture(); } catch (_) { await stop(); return; }
    if (_subscription != null && _publicId == publicId && _accountUid == uid &&
        _accountEpoch == accountEpoch) return;
    final generation = ++_generation;
    final previous = _subscription;
    _subscription = null;
    _publicId = publicId;
    _accountUid = uid;
    _accountEpoch = accountEpoch;
    pendingNotifier.value = 0;
    bool current() {
      if (_generation != generation || _publicId != publicId ||
          _accountUid != uid || _accountEpoch != accountEpoch ||
          !DedaPreferences.isLoggedIn ||
          DedaPreferences.stabilityAccountEpoch != accountEpoch ||
          account != DedaBackend.accountKeyForPhone(DedaPreferences.phone) ||
          FirebaseAuth.instance.currentUser?.uid != uid) return false;
      try { DedaAuthRuntime.checkSnapshot(principal); return true; }
      catch (_) { return false; }
    }
    try { await previous?.cancel(); } catch (_) {}
    if (!current()) return;''', 'detach-and-snapshot-before-await')
    body = one(body, '''        if (_generation != generation ||
            _publicId != publicId ||
            _accountUid != uid ||
            FirebaseAuth.instance.currentUser?.uid != uid) {
          return; // old account cannot display its gifts in a new session
        }''', '''        if (!current()) return; // old account cannot publish a badge.''',
        'same-generation-diamond-result')
    verify_inbox(body)
    return body


def verify_inbox(body):
    for marker in (GIFT_MARK, '_accountEpoch == accountEpoch', 'DedaAuthRuntime.checkSnapshot(principal)',
                   'DedaPreferences.stabilityAccountEpoch != accountEpoch',
                   'if (!current()) return; // old account cannot publish a badge.',
                   'DedaBackend.watchPersonalDiamondGifts(publicId).listen(',
                   ".where((gift) => (gift['status'] ?? '').toString() == 'pending')",
                   'DedaStage75UnreadGiftBadge.stop().catchError'):
        if marker not in body:
            raise ValueError('BOTTOM_VERIFY_INBOX:' + marker)
    if body.count('DedaBackend.watchPersonalDiamondGifts(publicId).listen(') != 1:
        raise ValueError('BOTTOM_VERIFY:duplicate-diamond-reader')
    if 'await _subscription?.cancel();' in body:
        raise ValueError('BOTTOM_VERIFY:old-cancellation-race')


def patch_id_badge(s):
    # Use exact original generation/UID+ID semantics. Detach old handle before
    # awaiting cancel, so a superseded start cannot null a newer subscription.
    pattern = r'    await (?:DedaSectionOperationContext\.wait\(\(\) => )?_listener\?\.cancel\(\)(?:\))?;\n    _listener = null;'
    s, count = re.subn(pattern,
        '    final previous = _listener;\n    _listener = null;\n'
        '    await previous?.cancel();\n'
        '    if (!_stillCurrent(generation, uid, originalId)) return;', s)
    if count != 1:
        raise ValueError('BOTTOM_SOURCE_STOP:identifier-badge-cancellation:' + str(count))
    # Preserve all verified service loads, original local seen key and writes.
    return s


def verify(main, badge, reference):
    a,z = home.home_span(main)
    body = main[a:z]
    home.verify_home(body)
    verify_home(body)
    a,z = home.home_span(reference)
    old = reference[a:z]
    _,old_item,old_bar = home.bottom_parts(old)
    _,item,bar = home.bottom_parts(body)
    if home.visual_signature(old_item) != home.visual_signature(item) or \
       home.visual_signature(old_bar) != home.visual_signature(bar):
        raise ValueError('BOTTOM_VERIFY:reference-colors-and-icons')
    a,z = home.span(main,'class DedaGiftInbox ')
    verify_inbox(main[a:z])
    if main.count('DedaGiftInbox.accountChanged();') != 3:
        raise ValueError('BOTTOM_VERIFY:all-existing-account-transitions')
    a,z = home.span(main,'class _DedaGiftNavBadgeState ')
    nav = main[a:z]
    for marker in ('final pending = diamondPending + idPending;', 'DedaGiftInbox.pendingNotifier',
                   'DedaStage75UnreadGiftBadge.pendingNotifier', "pending > 99 ? '99+'",
                   'onTap: widget.onTap', 'DedaGiftInbox.start()', 'DedaStage75UnreadGiftBadge.start('):
        if marker not in nav:
            raise ValueError('BOTTOM_VERIFY:original-combined-gift-badge:' + marker)
    for marker in ('DedaStage74IdGiftService.load(originalId)', '_seenPreference(uid, originalId)',
                   'await previous?.cancel();', 'if (!_stillCurrent(generation, uid, originalId)) return;',
                   "recipientOriginalId", 'awaitingIdentifiers(originalId, gifts)', 'markViewed('):
        if marker not in badge:
            raise ValueError('BOTTOM_VERIFY:identifier-badge:' + marker)
    # Destinations are the existing protected pages, not substitute pages.
    for name, needles in (
        ('class _DedaSocialHubPageState ', ('DedaProfilePhase2Page()', 'DedaFriendsPage(',
                 'DedaFriendRequestsPage()', 'DedaAddFriendPage()', 'DedaStylePage()',
                 'DedaIncomingRequestNotifications.markCurrentIncomingSeen()')),
        ('class _DedaMakaniPageState ', ('DedaPreferences.setAccountType(DedaAccountType.placeOwner)',
                 'const OwnerPlacePage()', 'Color(0xFF087650)', '_ownerPlaceCard()')),
        ('class _DedaMyGiftsPageState ', ('DedaStage74IdGiftsSection(originalId: _publicId)',
                 'DedaBackend.watchPersonalDiamondGifts(_publicId)', '_claim(gift)')),
        ('class _DedaSettingsPageState ', ('DedaAdminLoginPage(',)),
    ):
        a,z = home.span(main, name)
        for needle in needles:
            if needle not in main[a:z]:
                raise ValueError('BOTTOM_VERIFY:destination:' + name + ':' + needle)


def bind(project, verify_only=False):
    project = Path(project).resolve()
    if project == ROOT or ROOT in project.parents or project in ROOT.parents:
        raise ValueError('BOTTOM_DO_NOT_MODIFY_REPOSITORY')
    m, g = project/'lib/main.dart', project/'lib/deda_stage75_unread_gift_badge.dart'
    main, badge = m.read_text(), g.read_text()
    if not verify_only:
        a,z = home.home_span(main)
        main = main[:a] + patch_home(main[a:z]) + main[z:]
        a,z = home.span(main, 'class DedaGiftInbox ')
        main = main[:a] + patch_inbox(main[a:z]) + main[z:]
        hook = '      DedaSectionAccountChanges.changed();'
        if main.count(hook) != 3:
            raise ValueError('BOTTOM_SOURCE_STOP:existing-account-hooks')
        main = main.replace(hook, '      DedaGiftInbox.accountChanged();\n' + hook)
        badge = patch_id_badge(badge)
    verify(main, badge, home.archive_reference())
    if not verify_only:
        m.write_text(main)
        g.write_text(badge)
    print('PASS_STAGE2_BOTTOM_FIVE_ORIGINAL_ROUTES_GIFT_BADGES_ACCOUNT_GUARD_NO_PAYOUT')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('project', type=Path)
    parser.add_argument('--verify-only', action='store_true')
    args = parser.parse_args()
    bind(args.project, args.verify_only)
