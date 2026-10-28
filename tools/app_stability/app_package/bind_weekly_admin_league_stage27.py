"""Stage27: integrate Stage26 GM-only league card in a TEMPORARY verified
original DEDA 100394 Android QA workspace, never in production source.

Requires Stage13+14+16+17+18+19 original bind chain and its known hashes.
Touches just workspace/lib/admin_pages.dart plus one new QA UI source file;
the accepted DEDA 100387 and owner-tested 100394 are protected unchanged.
No Firebase writes, league activation, admin grants, prizes or Play delivery.
"""
import argparse
import hashlib
import json
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
META = 'internal-build-inputs.json'
NEW_PAGE = 'lib/deda_admin_league_page.dart'
PACKAGE = 'com.diraq.ludo.d_iraq_ludo'
PRIOR = 100394
NEXT = 100395

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def once(src, before, after, label):
    count = src.count(before)
    if count != 1:
        raise ValueError(f'Unsafe Stage27 original anchor {label}: {count}')
    return src.replace(before, after, 1)

def bind(project):
    project = Path(project).resolve()
    if project == ROOT or project in ROOT.parents or ROOT in project.parents:
        raise ValueError('No editing the original repository')
    metafile = project / META
    if not metafile.is_file():
        raise ValueError('Prepare and bind verified 100394 original first')
    data = json.loads(metafile.read_text())
    if (data.get('package') != PACKAGE or
        data.get('versionCode') != PRIOR or
        data.get('variant') != 'candidate' or
        data.get('completeOwnerDelivery') is not False or
        data.get('financialRestoreEnabled') is not False or
        data.get('productionExecutionPerformed') is not False or
        data.get('weeklyStage18', {}).get('writesRealWallet') is not False or
        data.get('weeklyStage18', {}).get('writesRealXp') is not False or
        data.get('weeklyStage18', {}).get('writesFirestore') is not False or
        data.get('weeklyStage19', {}).get('walletOrXpModified') is not False):
        raise ValueError('Unverified prior original app or financial flags')

    earlier = dict(data['sourceHashes'])
    for relative, digest in earlier.items():
        p = project / relative
        if not p.is_file() or sha(p) != digest:
            raise ValueError('Previously signed-source bind drift: ' + relative)

    new_page = project / NEW_PAGE
    if new_page.exists():
        raise ValueError('No overriding existing administration league source')
    expected_page = ROOT / NEW_PAGE
    if not expected_page.is_file():
        raise ValueError('Expected Stage26 GM page not found')
    original = project / 'lib/admin_pages.dart'
    src = original.read_text()
    if ('DedaAdminDashboardPage' not in src or
        'DedaAdminCompactCard' not in src or
        "currentAdminProfile(" not in src or
        "if (DedaBackend.adminHasPermission(\n                          profile, 'supportRead'))" not in src):
        raise ValueError('Unexpected original administration: refuse patch')
    if ('deda_admin_league_dashboard_tile' in src or
        'deda_admin_league_page.dart' in src):
        raise ValueError('Original already has stage26 admin card: do not duplicate')

    src = once(src,
        "import 'deda_admin_task_management_page.dart';",
        "import 'deda_admin_task_management_page.dart';\n"
        "import 'deda_admin_league_page.dart';",
        "original admin import")
    # The SHA-verified ORIGINAL 100380 administration uses a multiline
    # supportRead gate; Stage26 repository code is formatted differently.
    # Never replace the full admin page with the repository copy.
    anchor = ("                      if (DedaBackend.adminHasPermission(\n"
              "                          profile, 'supportRead'))")
    tile = """                      // Safe original DEDA Stage27 private manager QA.
                      // The page revalidates role; this is NOT a live league.
                      if (DedaBackend.normalizeAdminRole(profile['role']) ==
                              'general_manager' &&
                          DedaBackend.normalizeAdminStatus(profile) == 'active')
                        DedaAdminCompactCard(
                          key: const Key('deda_admin_league_dashboard_tile'),
                          icon: Icons.leaderboard_outlined,
                          title: t('إدارة الدوري', 'League management'),
                          subtitle: t(
                            'المتصدرون • السجل الشهري • الجوائز',
                            'Standings • monthly history • prizes',
                          ),
                          accentColor: const Color(0xFF133F65),
                          backgroundColor: const Color(0xDCE7EEF7),
                          onTap: () => _open(
                            DedaAdminLeaguePage(isArabic: ar),
                          ),
                        ),
"""
    src = once(src, anchor, tile + anchor, 'original card grid')
    if src.count('deda_admin_league_dashboard_tile') != 1:
        raise ValueError('Duplicate private manager tile')
    page_source = expected_page.read_text()
    if not all(item in page_source for item in (
            'currentAdminProfile(', 'forceRefresh: true',
            'DedaBackend.normalizeAdminRole', 'DedaBackend.normalizeAdminStatus',
            "key: const Key('deda_league_admin_start_disabled')",
            "key: const Key('deda_league_admin_stop_disabled')",
            "onPressed: null")):
        raise ValueError('Safe manager access and no-live-controls gate missing')
    if any(item in page_source for item in (
            'FirebaseFirestore', 'SharedPreferences', 'FieldValue.increment',
            'grantDiamonds(', 'awardTaskClaim(')):
        raise ValueError('This stage cannot write user balance/task data')

    # All checks above finish BEFORE any temporary workspace modifications.
    original.write_text(src)
    shutil.copy2(expected_page, new_page)
    changed = {p for p, before in earlier.items() if sha(project / p) != before}
    if changed != {'lib/admin_pages.dart'}:
        raise ValueError('Protected original files mutated: ' + repr(changed))
    for protected in ('lib/main.dart', 'lib/deda_backend.dart',
                      'lib/deda_social_service.dart', 'lib/traffic_quiz_page.dart',
                      'pubspec.yaml', 'pubspec.lock'):
        if sha(project / protected) != earlier[protected]:
            raise ValueError('Original owner/wallet changed: ' + protected)

    data['sourceHashes'] = {
        str(p.relative_to(project)): sha(p)
        for p in sorted((project / 'lib').rglob('*.dart'))
    }
    data['sourceHashes'].update({
        'pubspec.yaml': sha(project / 'pubspec.yaml'),
        'pubspec.lock': sha(project / 'pubspec.lock'),
    })
    data['versionCode'] = NEXT
    data['weeklyStage27'] = {
        'sameOfficialPackage': True,
        'adminLeagueTileInOriginal': True,
        'adminGeneralManagerOnly': True,
        'rechecksActiveOriginalAdmin': True,
        'liveLeagueControlsEnabled': False,
        'realVerifiedRankingsAvailable': False,
        'actualPrizePayoutEnabled': False,
        'monthlyArchiveLiveEnabled': False,
        'writesRealXP': False,
        'writesRealDiamonds': False,
        'writesFirestore': False,
        'privateQaOnly': True,
    }
    data['purpose'] = 'ORIGINAL 100395 GM LEAGUE ADMIN TILE PRIVATE QA ONLY - NO LIVE PAYOUT'
    metafile.write_text(json.dumps(data, indent=2, ensure_ascii=False) + '\n')
    return data['weeklyStage27']

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('project', type=Path)
    print(json.dumps(bind(parser.parse_args().project), ensure_ascii=False))
