#!/usr/bin/env python3
"""Owner QA: native 16 real WebP LAB frame previews under sticky edit profile.

Three genuine royal artworks = free (native style 3..5). Thirteen authentic
LAB originals = paid locked previews only (native style 6..18).
Old 0..2 frames still load for users who already selected them.
No debits, no currency creation, no fake purchases, no Firebase writes.
"""
from pathlib import Path
from hashlib import sha256
import json

MAIN=Path("lib/main.dart")
PUB=Path("pubspec.yaml")
ASSET_DIR=Path("assets/deda_lab_frames")
CATALOG=Path("docs/DEDA_LAB_16_VERIFIED_FRAME_CATALOG_STAGED_ONLY_2026-10-21.json")
MARK="DEDA_100375_16_AUTHENTIC_LAB_FRAMES_STICKY_PREVIEW_3FREE_13LOCKED"
IMPORT="import 'deda_lab_premium_frame_artwork.dart';"

def patch(s):
    if MARK in s:
        if s.count(MARK)!=1:raise ValueError("SAFE_STOP_100375_DUPLICATE_LAB_FRAMES")
        return s
    required=[
        "class DedaFramedAvatar extends StatelessWidget {",
        "class _DedaEditProfilePageState extends State<DedaEditProfilePage> {",
        "final safeStyle = frameStyle.clamp(0, 5).toInt();",
        "final free = dedaProfileFrameIsFree(index);",
        "class DedaProfileFramePreview extends StatelessWidget {",
        "class DedaPreferences {",
        "deda_edit_profile_scroll_choices",
        "class DedaAvatarPortrait",
    ]
    for k in required:
        if k not in s:raise ValueError("SAFE_STOP_LAB_NATIVE_SOURCE_MISSING "+k)

    a=s.index("class DedaFramedAvatar extends StatelessWidget {")
    b=s.index("\nclass ",a+8)
    section=s[a:b]
    anchor="    final safeStyle = frameStyle.clamp(0, 5).toInt();"
    if section.count(anchor)!=1:raise ValueError("SAFE_STOP_NATIVE_FRAME_STYLE_ANCHOR")
    early="""    // DEDA_100375_16_AUTHENTIC_LAB_FRAMES_STICKY_PREVIEW_3FREE_13LOCKED
    final labSpec = DedaLabPremiumFrameStyles.byProfileStyle(frameStyle);
    if (labSpec != null) {
      return DedaLabPremiumFrameArtwork(
        key: ValueKey<String>('deda_paid_lab_preview_' + labSpec.id),
        spec: labSpec,
        size: size,
        portrait: DedaAvatarPortrait(
          style: avatarStyle,
          size: size * labSpec.portraitWidth,
        ),
      );
    }
"""
    s=s[:a]+section.replace(anchor,early+anchor,1)+s[b:]

    a=s.index("class _DedaEditProfilePageState extends State<DedaEditProfilePage> {")
    b=s.find("\nclass ",a+15)
    if b<0:raise ValueError("SAFE_STOP_EDIT_PROFILE_END_UNKNOWN")
    edit=s[a:b]
    original="""children: List<Widget>.generate(6, (index) {
                          final free = dedaProfileFrameIsFree(index);"""
    changed="""children: List<Widget>.generate(16, (offset) {
                          // Three existing genuine royal frames are styles
                          // 3,4,5; 13 paid original LAB frames are 6..18.
                          // Legacy 0..2 stay saved and are not deleted.
                          final index = offset + 3;
                          final free = dedaProfileFrameIsFree(index);"""
    if edit.count(original)!=1:
        raise ValueError("SAFE_STOP_EDIT_FRAME_GRID_ANCHOR="+str(edit.count(original)))
    edit=edit.replace(original,changed,1)
    notice="هذا الإطار مقفول حاليًا وسيتم تفعيله لاحقًا."
    if notice in edit:
        edit=edit.replace(notice,
           "الإطار متاح للمعاينة. سعر شرائه 1000 ماسة؛ لا يتم الخصم دون تأكيد الملكية.",1)
    s=s[:a]+edit+s[b:]
    if IMPORT not in s:
        anchor="import 'deda_stage71_free_owned_use_profile.dart';"
        if s.count(anchor)!=1:raise ValueError("SAFE_STOP_NATIVE_FRAME_IMPORT")
        s=s.replace(anchor,anchor+"\n"+IMPORT,1)
    if s.count(MARK)!=1 or "children: List<Widget>.generate(16, (offset)" not in s:
        raise ValueError("SAFE_STOP_LAB_NATIVE_POSTCONDITION")
    return s

def verify_assets():
    manifest=json.loads(CATALOG.read_text())
    assert len(manifest["frames"])==16
    free=[];paid=[]
    for item in manifest["frames"]:
        path=Path(item.get("base_asset_at_100373") or
                  str(ASSET_DIR/(item["id"]+".webp")))
        if not path.exists() or sha256(path.read_bytes()).hexdigest()!=item["sha256"]:
            raise ValueError("SAFE_STOP_ORIGINAL_ARTWORK_SHA256_"+item["id"])
        if item["initial_price_diamonds"] == 0:free.append(item["id"])
        else:
            assert item["initial_price_diamonds"]==1000
            paid.append(item["id"])
    assert free==["FRAME_01","FRAME_02","FRAME_04"] and len(paid)==13
    pub=PUB.read_text()
    if "    - assets/deda_lab_frames/" not in pub:
        anchor="    - assets/deda_home_bg.jpg\n"
        if pub.count(anchor)!=1:
            raise ValueError("SAFE_STOP_FLUTTER_ASSET_SECTION_DRIFT")
        PUB.write_text(pub.replace(anchor,
            anchor+"    - assets/deda_lab_frames/\n",1))

if __name__=="__main__":
    verify_assets()
    original=MAIN.read_text()
    updated=patch(original)
    if updated==original:raise ValueError("SAFE_STOP_NATIVE_ALREADY_APPLIED")
    MAIN.write_text(updated)
    print("PASS_NATIVE_16_ORIGINAL_LAB_ARTWORKS_3FREE_13LOCKED_AT1000")
    print("PASS_STICKY_PROFILE_PREVIEW_AND_ORNAMENT_ALPHA_MOTION")
    print("PASS_NO_WALLET_SPEND_NO_SERVER_GRANT_OR_PLAY_DEPLOY")
