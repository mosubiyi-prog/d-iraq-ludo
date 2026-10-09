"""Next DEDA integrated release: display rewarded diamonds on GM profile.

Run AFTER the proven 100272 manager-wallet UI reconstruction and before APK
build. This does NOT modify either underlying wallet or administration gifts.
"""
from pathlib import Path
import re

main = Path("lib/main.dart")
source = main.read_text(encoding="utf-8")

marker = "// DEDA_NEXT_PROFILE_REWARDED_DIAMONDS_2026_10_10"
if marker in source:
    print("Already applied profile rewarded diamonds display correction")
    raise SystemExit(0)

old_import = "import 'admin_pages.dart';"
new_import = (
    "import 'admin_pages.dart';\n"
    "import 'deda_profile_visible_diamonds.dart';"
)
if source.count(old_import) != 1:
    raise SystemExit("Refuse patch: top-level administration import changed")

pattern = re.compile(
    r"\$\{DedaDiamondsWallet\.hasGeneralManagerPersonalWallet\s*"
    r"\?\s*managerDiamonds\s*:\s*normalDiamonds\}",
    re.MULTILINE,
)
replacement = (
    "${dedaProfileVisibleDiamonds("
    "ordinaryEarnedAndGifted: normalDiamonds, "
    "hasGeneralManagerPersonalWallet: "
    "DedaDiamondsWallet.hasGeneralManagerPersonalWallet, "
    "generalManagerPersonal: managerDiamonds)}"
)

new_source, n = pattern.subn(lambda match: replacement, source)
if n != 1:
    raise SystemExit(
        "Refuse patch: exactly one reconstructed manager-profile diamond "
        f"stat expression required, found {n}. No file changed."
    )
new_source = new_source.replace(old_import, new_import, 1)
new_source = new_source.replace(
    "class _DedaProfilePhase2PageState extends State<DedaProfilePhase2Page> {",
    marker + "\n"
    "class _DedaProfilePhase2PageState extends State<DedaProfilePhase2Page> {",
    1,
)
if new_source.count(marker) != 1:
    raise SystemExit("Refuse patch: profile widget anchor missing")
main.write_text(new_source, encoding="utf-8")
print("FIXED: manager profile now displays personal + earned-ad diamonds")
