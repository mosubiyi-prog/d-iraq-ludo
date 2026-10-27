"""Isolated stage-2 DEDA leaderboard UI integration. No release/QA APK.

Run ONLY on a restored, task-integrated workspace, never on the repository
itself and never on the 100387 stable release branch. This intentionally
does not configure any client-side Firebase rank/award write.
"""
from pathlib import Path
import shutil

REPO = Path(__file__).resolve().parents[2]

def _once(value, old, new, what):
    count = value.count(old)
    if count != 1:
        raise ValueError(f'Weekly UI: expected one {what}, got {count}')
    return value.replace(old, new, 1)

def bind(root):
    root = Path(root).resolve()
    if root == REPO or REPO in root.parents or root in REPO.parents:
        raise ValueError('Must be an isolated staged source, never repo')
    main = root/'lib/main.dart'
    quiz = root/'lib/traffic_quiz_page.dart'
    backend = root/'lib/deda_backend.dart'
    if not (main.is_file() and quiz.is_file() and backend.is_file()):
        raise FileNotFoundError('Verified restored app source is required')
    if (root/'lib/deda_weekly_leaderboard_page.dart').exists():
        raise ValueError('Weekly UI already integrated; do not reapply')

    before_quiz = quiz.read_bytes()
    before_backend = backend.read_bytes()
    before_main = main.read_text()
    s = before_main

    s = _once(s, "import 'deda_task_signal_bridge.dart';",
              "import 'deda_task_signal_bridge.dart';\n"
              "import 'deda_weekly_leaderboard_page.dart';",
              'main import')
    # Removing only the obsolete home restaurant quick-launch; restaurant
    # discovery stays available from the Map. There are TWO home layouts:
    # compact/landscape and portrait.
    s = _once(s, "    final restaurant = category('مطاعم');\n",
              "", 'retired home-only restaurant variable')

    landscape_old = "                                Expanded(child: categoryCard(restaurant)),"
    landscape_new = """                                Expanded(child: DedaLeaderboardHomeCard(
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute<void>(
                                      builder: (_) => const DedaWeeklyLeaderboardPage(),
                                    ),
                                  ),
                                )),"""
    s = _once(s, landscape_old, landscape_new,
              'landscape leaderboard tile')

    portrait_old = "                                            child: categoryCard(restaurant),"
    portrait_new = """                                            child: DedaLeaderboardHomeCard(
                                              onTap: () => Navigator.push(
                                                context,
                                                MaterialPageRoute<void>(
                                                  builder: (_) => const DedaWeeklyLeaderboardPage(),
                                                ),
                                              ),
                                            ),"""
    s = _once(s, portrait_old, portrait_new,
              'portrait leaderboard tile')

    if 'categoryCard(restaurant)' in s or "final restaurant = category('مطاعم');" in s:
        raise ValueError('Retired restaurant home tile remains')
    if s.count('DedaLeaderboardHomeCard(') != 2:
        raise ValueError('Not all home layouts bound')
    if s.count('const DedaWeeklyLeaderboardPage()') != 2:
        raise ValueError('Each home layout must open leaderboard')

    # Everything else in the restored app remains byte-identical.
    if quiz.read_bytes() != before_quiz or backend.read_bytes() != before_backend:
        raise ValueError('Unexpected change to core gameplay or accounts')
    shutil.copy2(
        REPO/'lib/deda_weekly_leaderboard_policy.dart',
        root/'lib/deda_weekly_leaderboard_policy.dart')
    shutil.copy2(
        REPO/'lib/deda_weekly_leaderboard_page.dart',
        root/'lib/deda_weekly_leaderboard_page.dart')
    main.write_text(s)
    return {
        'homeLayouts': 2,
        'restaurantsHomeRemoved': True,
        'restaurantsRemainInMap': True,
        'fixedSingleViewportNoScrolling': True,
        'serverAwardsConnected': False,
        'productionEdited': False,
    }
