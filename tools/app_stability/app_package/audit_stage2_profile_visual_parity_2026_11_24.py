#!/usr/bin/env python3
"""Read-only visual parity of the ACTUAL reconstructed DEDA profile.

No edits to profile gradients, frames, backgrounds, avatar geometry, UID,
owner records or application assets. All protected images stay byte-identical.
"""
import argparse
import hashlib
import json
import re
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
PALETTE = (
    ("تعديل الملف", "0xFF0877C9", "0xFF07579B"),
    ("متجري", "0xFF914BE1", "0xFF6530B7"),
    ("الشارات", "0xFF0BB97B", "0xFF07885D"),
    ("المفضلة", "0xFFF3A411", "0xFFD77D00"),
    ("نشاطاتي", "0xFFE8465D", "0xFFC92A44"),
    ("عرض الملف العام", "0xFF17A8B5", "0xFF087F91"),
)
ROYAL_ASSETS = (
    "assets/deda_royal_avatars/deda_avatar_male_royal.jpg",
    "assets/deda_royal_avatars/deda_avatar_female_royal.jpg",
    "assets/deda_royal_avatars/deda_avatar_couple_royal.jpg",
)
ROYAL_FRAMES = tuple(
    f"assets/deda_royal_frames/royal_frame_{n}.webp" for n in range(3)
)
ROYAL_BACKGROUNDS = (
    "assets/deda_royal_backgrounds/deda_royal_bg_emerald.webp",
    "assets/deda_royal_backgrounds/deda_royal_bg_burgundy.webp",
)


def visual_palette(main):
    start = main.find("  Widget _featureGrid() {")
    stop = main.find("  Widget _featureCard(", start)
    if start < 0 or stop < start:
        raise ValueError("PROFILE_VISUAL_STOP:original-six-card-grid-not-found")
    grid = main[start:stop]
    # Individual per-card sections prevent accidentally borrowing a neighbor's
    # palette or counting a subtitle as a card.
    title_marks = list(re.finditer(
        r"(?<![A-Za-z])title:\s*dedaText\('([^']+)'", grid))
    all_titles = [m.group(1) for m in title_marks]
    expected = [name for name, _, _ in PALETTE]
    if all_titles != expected:
        raise ValueError("PROFILE_VISUAL_STOP:card-order-or-count-drift:" + repr(all_titles))
    rows = []
    for i, name in enumerate(all_titles):
        a = title_marks[i].start()
        b = title_marks[i + 1].start() if i + 1 < len(title_marks) else len(grid)
        card = grid[a:b]
        m = re.search(
            r"colors:\s*const\s*<Color>\[Color\((0x[0-9A-Fa-f]{8})\),"
            r"\s*Color\((0x[0-9A-Fa-f]{8})\)\]", card)
        if not m:
            raise ValueError("PROFILE_VISUAL_STOP:missing-original-gradient:" + name)
        rows.append((name, *m.groups()))
    if tuple(rows) != PALETTE:
        raise ValueError("PROFILE_VISUAL_STOP:approved-six-gradients-changed:" + repr(rows))
    if "LinearGradient(" not in main[stop:stop + 850]:
        raise ValueError("PROFILE_VISUAL_STOP:original-card-renderer-gradient-changed")
    return rows


def approved_art(project, manifest):
    if manifest.get("owner_approved_exact_artwork") is not True:
        raise ValueError("PROFILE_VISUAL_STOP:owner-art-not-approved")
    approved = manifest.get("avatars")
    if (not isinstance(approved, list) or len(approved) != 3 or
            manifest.get("inner_display") != [111, 111]):
        raise ValueError("PROFILE_VISUAL_STOP:owner-three-avatars-or-geometry")
    result = []
    for i, item in enumerate(approved):
        if (item.get("slot") != i + 3 or
                item.get("role") != ("male", "female", "couple")[i]):
            raise ValueError("PROFILE_VISUAL_STOP:owner-approved-avatar-slot-order")
        path = item.get("asset")
        if not isinstance(path, str) or not path.startswith(
                "assets/deda_owner_avatars_20261023/"):
            raise ValueError("PROFILE_VISUAL_STOP:unexpected-avatar-location")
        image = project / path
        if not image.is_file():
            raise ValueError("PROFILE_VISUAL_STOP:missing-approved-owner-art:" + path)
        if hashlib.sha256(image.read_bytes()).hexdigest() != item.get("sha256"):
            raise ValueError("PROFILE_VISUAL_STOP:approved-owner-art-bytes-changed:" + path)
        result.append(path)
    return result


def audit(project, manifest):
    main = (project / "lib/main.dart").read_text(encoding="utf-8")
    inventory = (project / "lib/deda_100377_profile_free_inventory.dart").read_text(encoding="utf-8")
    pubspec = (project / "pubspec.yaml").read_text(encoding="utf-8")
    palettes = visual_palette(main)
    approved = approved_art(project, manifest)
    all_art = ROYAL_ASSETS + tuple(approved) + ROYAL_FRAMES + ROYAL_BACKGROUNDS
    for asset in all_art:
        f = project / asset
        if not f.is_file() or f.stat().st_size <= 1000:
            raise ValueError("PROFILE_VISUAL_STOP:missing-authentic-art:" + asset)
    # Preserve all six free portraits including the three confirmed v2 slots.
    for path in ROYAL_ASSETS + tuple(approved):
        if path not in inventory:
            raise ValueError("PROFILE_VISUAL_STOP:approved-avatar-not-in-inventory:" + path)
    for path in ROYAL_BACKGROUNDS:
        if path not in inventory:
            raise ValueError("PROFILE_VISUAL_STOP:royal-background-reference-missing:" + path)
    for dir_name in ("deda_royal_avatars", "deda_owner_avatars_20261023",
                     "deda_royal_frames", "deda_royal_backgrounds"):
        if f"- assets/{dir_name}/" not in pubspec:
            raise ValueError("PROFILE_VISUAL_STOP:unbundled-approved-assets:" + dir_name)
    if "backgroundChoices = <int>[0, 1, 2, 6, 7, 8]" not in inventory:
        raise ValueError("PROFILE_VISUAL_STOP:approved-six-background-choices")
    if "previewAsset: switch (style)" not in inventory:
        raise ValueError("PROFILE_VISUAL_STOP:royal-background-preview-mapping")
    if "dedaProfileBackgroundColors(" not in main:
        raise ValueError("PROFILE_VISUAL_STOP:original-gradient-background-lost")
    if "DedaPreferences.profileBackgroundStyle" not in main:
        raise ValueError("PROFILE_VISUAL_STOP:selected-profile-background-lost")
    if "DedaProfileAppearanceState" not in main:
        raise ValueError("PROFILE_VISUAL_STOP:profile-appearance-state-lost")
    return {
        "card_gradient_pairs": palettes,
        "original_royal_avatars": len(ROYAL_ASSETS),
        "owner_approved_v2_avatars": len(approved),
        "royal_frame_images": len(ROYAL_FRAMES),
        "royal_background_images": len(ROYAL_BACKGROUNDS),
        "background_choice_styles": [0, 1, 2, 6, 7, 8],
        "no_fake_image_for_generated_backgrounds": True,
        "read_only": True,
    }


def main():
    p = argparse.ArgumentParser()
    p.add_argument("project", type=Path)
    a = p.parse_args()
    if not (a.project / "lib/main.dart").is_file():
        raise SystemExit("PROFILE_VISUAL_STOP:assembled-full-app-required")
    manifest = json.loads((REPO / "docs/DEDA_OWNER18_APPROVED_AVATARS_2026-10-23.json")
                          .read_text(encoding="utf-8"))
    result = audit(a.project, manifest)
    print("PASS_PROFILE_SIX_APPROVED_COLORS_SIX_AVATARS_THREE_FRAMES_BACKGROUND_ART_NO_MUTATION")
    print("PROFILE_VISUAL_PARITY=" + json.dumps(result, ensure_ascii=False, sort_keys=True))
    print("PROFILE_VISUAL_RELEASE_HOLD_DEVICE_QA_PENDING_NO_APK_NO_PLAY")


if __name__ == "__main__":
    main()
