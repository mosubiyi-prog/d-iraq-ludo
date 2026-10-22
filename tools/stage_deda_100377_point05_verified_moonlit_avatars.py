#!/usr/bin/env python3
"""Point05 — guarded ORIGINAL approved moonlit avatar assets integration.

This file is deliberately NOT executed in the 13-point build until the three
actual owner-approved photographs and their SHA256 manifest are present.
Never invent/replace artwork, touch wallets, change level or user selection.
Adds the new couple/princess/prince to FREE slots 3/4/5 only.
Keeps existing 0/1/2 royals and historical 6/7/8 classic fallbacks.
"""
from pathlib import Path
import hashlib
import json

MAIN = Path("lib/main.dart")
PUB = Path("pubspec.yaml")
MANIFEST = Path("docs/DEDA_100377_POINT05_OWNER_APPROVED_MOONLIT_ASSETS.json")
MARK = "// DEDA_100377_POINT05_VERIFIED_MOONLIT_THREE_FREE"
ASSET_ROOT = Path("assets/deda_moonlit_avatars")
ROLES = ("couple", "princess", "prince")

def _is_image(data: bytes, suffix: str) -> bool:
    if suffix in (".jpg", ".jpeg"):
        return data.startswith(b"\xff\xd8\xff") and data.endswith(b"\xff\xd9")
    if suffix == ".png":
        return data.startswith(b"\x89PNG\r\n\x1a\n")
    if suffix == ".webp":
        return data[:4] == b"RIFF" and data[8:12] == b"WEBP"
    return False

def verified_paths(manifest: Path = MANIFEST, root: Path = Path(".")) -> list[str]:
    if not (root / manifest).is_file():
        raise ValueError("SAFE_STOP_POINT05_EXACT_APPROVED_MOONLIT_FILES_NOT_SUPPLIED")
    data = json.loads((root / manifest).read_text(encoding="utf-8"))
    if data.get("owner_approved_exact_artwork") is not True:
        raise ValueError("SAFE_STOP_POINT05_NO_EXACT_OWNER_ART_CONFIRMATION")
    records = data.get("avatars")
    if not isinstance(records, list) or len(records) != 3:
        raise ValueError("SAFE_STOP_POINT05_EXPECTED_THREE_APPROVED_FILES")
    paths = []
    for n, (role, item) in enumerate(zip(ROLES, records)):
        if item.get("role") != role or item.get("slot") != n + 3:
            raise ValueError("SAFE_STOP_POINT05_ROLE_OR_SLOT_ORDER_CHANGED")
        filename = item.get("asset")
        sha = item.get("sha256")
        if not isinstance(filename, str) or not isinstance(sha, str):
            raise ValueError("SAFE_STOP_POINT05_UNVERIFIED_IMAGE_METADATA")
        p = Path(filename)
        if p.parent != ASSET_ROOT or not p.name or p.suffix.lower() not in (".jpg", ".jpeg", ".png", ".webp"):
            raise ValueError("SAFE_STOP_POINT05_UNSAFE_ASSET_PATH")
        original = root / p
        if not original.is_file():
            raise ValueError("SAFE_STOP_POINT05_MISSING_APPROVED_IMAGE:" + filename)
        raw = original.read_bytes()
        if len(raw) < 100 or not _is_image(raw, p.suffix.lower()):
            raise ValueError("SAFE_STOP_POINT05_IMAGE_NOT_ORIGINAL:" + filename)
        if hashlib.sha256(raw).hexdigest() != sha:
            raise ValueError("SAFE_STOP_POINT05_IMAGE_HASH_MISMATCH:" + filename)
        paths.append(filename)
    if len(set(paths)) != 3:
        raise ValueError("SAFE_STOP_POINT05_DUPLICATE_ART")
    return paths

def patch_source(source: str, images: list[str]) -> str:
    if MARK in source:
        raise ValueError("SAFE_STOP_POINT05_ALREADY_INSTALLED")
    if len(images) != 3 or len(set(images)) != 3:
        raise ValueError("SAFE_STOP_POINT05_THREE_DISTINCT_IMAGES_REQUIRED")
    start = "class DedaAvatarPortrait extends StatelessWidget {"
    if source.count(start) != 1:
        raise ValueError("SAFE_STOP_POINT05_WRONG_SOURCE")
    a = source.index(start)
    b = source.find("\nclass ", a + len(start))
    if b < 0:
        raise ValueError("SAFE_STOP_POINT05_PORTRAIT_BOUNDARY")
    portrait = source[a:b]
    for guard in (
        "deda_avatar_male_royal.jpg", "deda_avatar_female_royal.jpg",
        "deda_avatar_couple_royal.jpg",
        "style >= 6 && style <= 8 ? style - 6 : style",
    ):
        if guard not in portrait:
            raise ValueError("SAFE_STOP_POINT05_PROTECTED_ORIGINALS_CHANGED:" + guard)
    cursor = "  @override\n  Widget build(BuildContext context) {"
    if portrait.count(cursor) != 1:
        raise ValueError("SAFE_STOP_POINT05_RENDER_ANCHOR_DRIFT")
    block = ("  " + MARK + "\n"
             + "  static const List<String> moonlitImageAssets = <String>[\n"
             + "".join("    '" + p + "',\n" for p in images)
             + "  ];\n"
             + "  static const List<String> freeImageAssets = <String>[\n"
             + "    ...royalImageAssets,\n"
             + "    ...moonlitImageAssets,\n"
             + "  ];\n\n")
    portrait = portrait.replace(cursor, block + cursor, 1)
    old1 = "style >= 0 && style < royalImageAssets.length"
    old2 = "royalImageAssets[style]"
    if portrait.count(old1) != 1 or portrait.count(old2) != 1:
        raise ValueError("SAFE_STOP_POINT05_ONLY_OLD_ROYALS_RENDERING_DRIFT")
    portrait = portrait.replace(old1, "style >= 0 && style < freeImageAssets.length", 1)
    portrait = portrait.replace(old2, "freeImageAssets[style]", 1)
    updated = source[:a] + portrait + source[b:]
    for required in (
        "children: List<Widget>.generate(6, (index)",
        "profileAvatarStyle = avatarStyle.clamp(0, 8).toInt();",
        "oldChoice + 6",
    ):
        if required not in updated:
            raise ValueError("SAFE_STOP_POINT05_SIX_FREE_OR_MIGRATION_CHANGED")
    return updated

def patch_pubspec(text: str) -> str:
    asset = "    - assets/deda_moonlit_avatars/\n"
    if asset in text:
        raise ValueError("SAFE_STOP_POINT05_ALREADY_DECLARED_IN_PUBSPEC")
    anchor = "    - assets/deda_lab_frames/\n"
    if text.count(anchor) != 1:
        raise ValueError("SAFE_STOP_POINT05_ASSETS_SECTION_DRIFT")
    return text.replace(anchor, anchor + asset, 1)

if __name__ == "__main__":
    paths = verified_paths()  # MUST fail before any file edits if images absent.
    original_main = MAIN.read_text(encoding="utf-8")
    original_pub = PUB.read_text(encoding="utf-8")
    new_main = patch_source(original_main, paths)
    new_pub = patch_pubspec(original_pub)
    MAIN.write_text(new_main, encoding="utf-8")
    PUB.write_text(new_pub, encoding="utf-8")
    print("PASS_POINT05_THREE_EXACT_APPROVED_MOONLIT_ARTS_AT_FREE_3_4_5")
    print("PASS_POINT05_EXISTING_FREE_0_1_2_AND_LEGACY_6_7_8_UNTOUCHED")
    print("PASS_POINT05_NO_CURRENCY_POINTS_FRIENDS_OR_BACKEND_CHANGES")
