"""Integrate the owner-approved fixed leaderboard with a safe data shell.

Requires the tested stage2 home tile replacement in a TEMPORARY verified
100387 restore. Does NOT change GitHub's original lib/main.dart, the
published APK, task/XP/diamonds, Firebase rules or Cloud Functions.
No live results until the future approved authenticated reader is injected.
"""
from pathlib import Path
import shutil

REPO = Path(__file__).resolve().parents[2]


def bind(root):
    root = Path(root).resolve()
    if root == REPO or root in REPO.parents or REPO in root.parents:
        raise ValueError('Not allowed to change the repository')
    main = root / 'lib/main.dart'
    if not main.is_file():
        raise FileNotFoundError('Restore/bind tested DEDA 100387 first')
    original = main.read_text()
    if not (root / 'lib/deda_weekly_leaderboard_page.dart').is_file():
        raise ValueError('Stage2 home UI is missing')
    if (root / 'lib/deda_weekly_leaderboard_safe_screen.dart').exists():
        raise ValueError('Stage8 screen already integrated')

    import_marker = "import 'deda_weekly_leaderboard_page.dart';"
    if original.count(import_marker) != 1:
        raise ValueError('Leaderboard import did not match expected restore')
    old_route = 'const DedaWeeklyLeaderboardPage()'
    if original.count(old_route) != 2:
        raise ValueError('Must find exactly TWO home leaderboard routes')

    updated = original.replace(
        import_marker,
        import_marker + "\nimport 'deda_weekly_leaderboard_safe_screen.dart';",
        1,
    ).replace(old_route, 'const DedaWeeklyLeaderboardSafeScreen()')
    if updated.count('DedaLeaderboardHomeCard(') != 2:
        raise ValueError('Unexpected home layout changes')
    if 'categoryCard(restaurant)' in updated or (
            "final restaurant = category('مطاعم');" in updated):
        raise ValueError('Restaurant home quick tile was not removed')
    if updated.count('const DedaWeeklyLeaderboardSafeScreen()') != 2:
        raise ValueError('Safe screen must cover both launch routes')
    if old_route in updated:
        raise ValueError('Legacy unprotected route still present')

    # Copy only new UI/adapters; no original task, XP, quiz or account files.
    for name in ('deda_weekly_snapshot_decode.dart',
                 'deda_weekly_leaderboard_safe_screen.dart'):
        shutil.copy2(REPO / 'lib' / name, root / 'lib' / name)
    main.write_text(updated)

    return {
        'homeLeaderboardRoutes': 2,
        'restaurantsHomeRemoved': True,
        'fixedViewportNoScroll': True,
        'unverifiedResultsStayPending': True,
        'serverBackendConnected': False,
        'walletWrites': 0,
        'publishedReleaseModified': False,
    }
