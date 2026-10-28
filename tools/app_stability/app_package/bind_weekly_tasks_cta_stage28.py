"""Stage28: wire league's Continue Daily Tasks to original daily tasks route.

Only edits main.dart in a TEMP verified Stage27 100395 private app workspace.
No production source, Firebase, XP or wallets are changed. Fail closed if
original navigation/task class/home routes do not match exactly.
"""
from pathlib import Path
import argparse
import hashlib
import json

ROOT = Path(__file__).resolve().parents[3]
PRIOR = 100395
VERSION = 100396
ORIGINAL_ROUTE = 'const DedaWeeklyLeaderboardSafeScreen()'
TARGET_ROUTE = """DedaWeeklyLeaderboardSafeScreen(
                                      onOpenDailyTasks: () =>
                                          Navigator.of(context).push(
                                        MaterialPageRoute<void>(
                                          builder: (_) =>
                                              const DedaDailyTasksPage(),
                                        ),
                                      ),
                                    )"""

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def bind(project):
    project = Path(project).resolve()
    if project == ROOT or project in ROOT.parents or ROOT in project.parents:
        raise ValueError('No original repo modification')
    manifest = project / 'internal-build-inputs.json'
    if not manifest.is_file():
        raise ValueError('Original signed-source Stage27 restore needed')
    data = json.loads(manifest.read_text())
    if (data.get('package') != 'com.diraq.ludo.d_iraq_ludo'
        or data.get('versionCode') != PRIOR
        or data.get('variant') != 'candidate'
        or data.get('completeOwnerDelivery') is not False
        or data.get('financialRestoreEnabled') is not False
        or data.get('productionExecutionPerformed') is not False
        or data.get('weeklyStage27', {}).get('adminLeagueTileInOriginal') is not True
        or data.get('weeklyStage27', {}).get('writesRealXP') is not False
        or data.get('weeklyStage27', {}).get('writesRealDiamonds') is not False
        or data.get('weeklyStage27', {}).get('writesFirestore') is not False):
        raise ValueError('Untrusted original baseline; stop before any edits')

    previous = dict(data['sourceHashes'])
    if any(not (project / name).is_file() or sha(project / name) != digest
           for name,digest in previous.items()):
        raise ValueError('Prior SHA-verified Stage27 workspace changed')

    main = project / 'lib/main.dart'
    page = project / 'lib/deda_weekly_leaderboard_page.dart'
    screen = project / 'lib/deda_weekly_leaderboard_safe_screen.dart'
    code = main.read_text()
    ui = page.read_text()
    secure = screen.read_text()
    if (code.count(ORIGINAL_ROUTE) != 2
        or code.count('DedaLeaderboardHomeCard(') != 2
        or code.count('class DedaDailyTasksPage extends StatefulWidget') != 1
        or 'categoryCard(restaurant)' in code
        or ui.count("key: const Key('deda_weekly_continue_daily_tasks')") != 1
        or 'onTap: widget.onOpenDailyTasks' not in ui
        or secure.count('onOpenDailyTasks: widget.onOpenDailyTasks') != 1):
        raise ValueError('Original home/task/CTA anchors changed; stop')
    result = code.replace(ORIGINAL_ROUTE, TARGET_ROUTE)
    if (result.count(TARGET_ROUTE) != 2
        or result.count(ORIGINAL_ROUTE) != 0
        or result.count('const DedaDailyTasksPage()') !=
               code.count('const DedaDailyTasksPage()') + 2):
        raise ValueError('Navigation patch not exactly two official routes')
    # No other app source or mutable user data is changed.
    main.write_text(result)
    if {p for p,h in previous.items() if sha(project/p) != h} != {'lib/main.dart'}:
        raise ValueError('Unexpected original source changes')
    for name in ('lib/admin_pages.dart', 'lib/deda_backend.dart',
                 'lib/deda_social_service.dart', 'lib/traffic_quiz_page.dart',
                 'pubspec.yaml', 'pubspec.lock'):
        if sha(project/name) != previous[name]:
            raise ValueError('Protected original modified: ' + name)

    data['sourceHashes'] = {
        str(p.relative_to(project)): sha(p)
        for p in sorted((project/'lib').rglob('*.dart'))
    }
    data['sourceHashes'].update({
        'pubspec.yaml': sha(project/'pubspec.yaml'),
        'pubspec.lock': sha(project/'pubspec.lock'),
    })
    data['versionCode'] = VERSION
    data['weeklyStage28'] = {
        'originalDailyTasksNavigation': True,
        'bothOfficialHomeLayouts': True,
        'currentAndPreviousLeagueViews': True,
        'userXPChanged': False,
        'taskClaimChanged': False,
        'walletChanged': False,
        'adminChanged': False,
        'firestoreChanged': False,
        'privateQaOnly': True,
    }
    data['purpose'] = 'ORIGINAL 100396 PRIVATE DAILY TASKS BUTTON FIX; NO LIVE LEAGUE'
    manifest.write_text(json.dumps(data, ensure_ascii=False, indent=2)+'\n')
    return data['weeklyStage28']

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('project', type=Path)
    print(json.dumps(bind(parser.parse_args().project), ensure_ascii=False))
