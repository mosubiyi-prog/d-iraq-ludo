#!/usr/bin/env python3
"""Read-only parity audit for the actual reconstructed DEDA profile.

Runs AFTER protected source reconstruction + existing single-owner binder.
Never edits a source file, app data, Firebase, a wallet or a profile renderer.
Reports deliberately deferred functions instead of manufacturing completion.
"""
import argparse
import json
import re
from pathlib import Path

STATE = "class _DedaProfilePhase2PageState"
EXPECTED = (
    "تعديل الملف", "متجري", "الشارات",
    "المفضلة", "نشاطاتي", "عرض الملف العام",
)

def unique_span(source, start, end, label):
    if source.count(start) != 1:
        raise ValueError("PROFILE_PARITY_STOP:" + label + ":start_count=" + str(source.count(start)))
    a = source.index(start)
    b = source.find(end, a + len(start))
    if b < a:
        raise ValueError("PROFILE_PARITY_STOP:" + label + ":boundary")
    return source[a:b]

def audit(main, files=None):
    files = files or {}
    section = unique_span(main, STATE, "\nclass ", "original-profile")
    grid = unique_span(section, "  Widget _featureGrid() {",
                       "  Widget _featureCard(", "original-card-grid")
    titles = re.findall(r"(?<![A-Za-z])title:\s*dedaText\(\s*'([^']+)'", grid)
    print("PROFILE_CARD_GRID_TITLES=" + json.dumps(titles, ensure_ascii=False))
    if set(EXPECTED) - set(titles):
        anchors = re.findall(r".{0,90}title:.{0,180}", grid.replace("\n", " "))
        print("PROFILE_CARD_TITLE_EXCERPTS=" +
              json.dumps(anchors[:18], ensure_ascii=False))
    for name in EXPECTED:
        if titles.count(name) != 1:
            raise ValueError("PROFILE_PARITY_STOP:card:" + name + ":count=" + str(titles.count(name)))
    if titles.count("متجر المعرّفات") != 0:
        raise ValueError("PROFILE_PARITY_STOP:duplicate-identifier-store-tile")
    # Each old card is kept in place. No extra renderer, hidden arbitrary new card
    # or reordered existing card. The approved single-store grid has SIX tiles.
    if tuple(titles) != EXPECTED:
        raise ValueError("PROFILE_PARITY_STOP:card-order-or-unapproved-extra:" + repr(titles))
    badge_at = grid.find("title: dedaText('الشارات'")
    print("PROFILE_BADGE_ROUTE_EXCERPT=" +
          json.dumps(grid[badge_at:badge_at + 1350], ensure_ascii=False))
    print("PROFILE_BADGE_GLOBAL_PAGE_IMPORT=" +
          str("deda_100377_level_achievements_page_staged.dart" in main))
    print("PROFILE_BADGE_GLOBAL_PAGE_ROUTE=" +
          str("DedaLevelAchievementsPage(" in section))
    route_proofs = {
        "original-account-info": "DedaAccountInfoPage(" in grid,
        "original-favorites-route": "SavedPlacesPage(showFavorites: true)" in grid,
        "original-activity-route": "SavedPlacesPage(showFavorites: false)" in grid,
        "public-profile-preview-route": "DedaPublicProfilePreviewPage(" in grid,
        "level-achievement-preview-route": "DedaLevelAchievementsPage(" in grid,
        "level-achievement-does-not-forge-proof": (
            "verifiedServerLevel: null" in grid and
            "hasVerifiedAccountAndLevel: false" in grid),
        "single-original-store-entry": (
            section.count("  Future<void> _openDedaMyStore() async {") == 1 and
            section.count("DedaStage2ProfileOwnerBoundMyStore(") == 1),
        "profile-editor-original-entry": "  Future<void> _openEditProfile() async {" in section,
        "copy-original-id": "  Future<void> _copyDedaId() async {" in section,
    }
    for label, passed in route_proofs.items():
        if not passed:
            raise ValueError("PROFILE_PARITY_STOP:missing-existing-route:" + label)

    stats = unique_span(section, "  Widget _statsRow() {",
                        "  Widget _statCard(", "original-stats")
    progress = unique_span(section, "  Widget _profileLevelProgressCard() {",
                           "  Widget _statsRow() {", "separate-level-progress")
    points_cards = "_pointsCardsPanel(totalPoints)" in section
    info = {
        "cards_in_order": titles,
        "route_proofs": route_proofs,
        "original_profile_state_count": main.count(STATE),
        "points_reward_cards_present": points_cards,
        "level_xp_from_separate_notifier": "DedaSocialProgressWallet.xpNotifier" in progress,
        "task_points_from_original_engine": "DedaTaskEngine.totalPointsNotifier" in stats,
        "visible_diamonds_source_used": "dedaProfileVisibleDiamonds(" in stats,
        "friends_stat_has_literal_zero": bool(re.search(
            r"value:\s*'0'\s*,\s*label:\s*dedaText\('الأصدقاء'", stats)),
        "separate_photos_tile_absent_by_approved_single_store_design": "الصور" not in titles,
        "achievement_release_deliberately_locked": (
            "verifiedServerLevel: null" in grid and
            "hasVerifiedAccountAndLevel: false" in grid),
    }
    return info

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("project", type=Path)
    options = parser.parse_args()
    file = options.project / "lib" / "main.dart"
    if not file.is_file():
        raise SystemExit("PROFILE_PARITY_STOP:assembled-main-required")
    result = audit(file.read_text(encoding="utf-8"))
    print("PASS_STAGE2_ORIGINAL_PROFILE_6_APPROVED_TILES_ROUTES_ORDER_NO_DUPLICATE")
    print("PROFILE_ASSEMBLED_PARITY=" + json.dumps(result, ensure_ascii=False, sort_keys=True))
    if result["friends_stat_has_literal_zero"]:
        print("PROFILE_DEFERRED:friends-count-is-literal-zero-needs-existing-social-bridge")
    print("PROFILE_RELEASE_HOLD_NO_FIREBASE_WRITE_NO_APK_NO_PLAY")

if __name__ == "__main__":
    main()
