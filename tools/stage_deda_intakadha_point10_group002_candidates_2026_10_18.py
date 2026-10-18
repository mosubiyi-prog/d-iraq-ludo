#!/usr/bin/env python3
"""«إنت كدها» stage 10/16 — read-only 100 six-character candidate IDs.

Group 001 = owner's original 100 admin-exclusive identifiers in PRIVATE
ChatGPT Library; never upload/disclose them into this public repository.
Group 002 = 100 proposed new six-character identifiers. Proposals are
NOT stock, NOT verified available in Firebase, and NOT for sale until
owner-approved prices and transactional server-side uniqueness checks.

Apply on reconstructed source AFTER approved stages 2-9, before dart format.
Does not modify Firestore, real user IDs, wallets, subscriptions or Play.
"""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MAIN = Path("lib/main.dart")
CATALOG = ROOT / "catalogs/DEDA_ID_GROUP_002_CANDIDATES_100_NO_SALES_2026-10-18.json"
MARKER = "// DEDA_INTAKADHA_POINT10_GROUP002_100_UNVERIFIED_IDS_2026_10_18"
PAGE = "class DedaIdentifierStorePage extends StatelessWidget {"
PROFILE = "class _DedaProfilePhase2PageState extends State<DedaProfilePhase2Page> {"
POINT9 = "// DEDA_INTAKADHA_POINT9_STICKY_FOUR_ID_CARDS_STORE_2026_10_18"
ROUTE = "                        identifier: activeId.isEmpty ? '@DEDA' : activeId,\n"
GROUP_ROUTE = (
    ROUTE
    + "                        readOnlyCatalog: DedaPoint10CandidateGroup002.identifiers,\n"
)
OLD_HEADING = """dedaText(
                            'المعرّفات المعروضة للبيع',
                            'Identifiers offered for sale',
                          )"""
NEW_HEADING = """dedaText(
                            'مرشحات المجموعة 002 — للمعاينة فقط',
                            'Group 002 candidates — preview only',
                          )"""
OLD_SUBTITLE = """dedaText(
                            'عرض فقط — الشراء والتفعيل غير متاحين',
                            'Preview only — purchases and activation are disabled',
                          )"""
NEW_SUBTITLE = """dedaText(
                            'مرشح غير متحقق من توفره — لا شراء ولا تفعيل',
                            'Unverified candidate — purchasing and activation disabled',
                          )"""

def expected_group002():
    letters = "ABCDEFGHIJKLMNOPQRST"
    out = [x * 6 for x in letters]
    out += [x + chr(ord(x) + 1) * 5 for x in letters]
    out += [(x + chr(ord(x) + 1)) * 3 for x in letters]
    out += [x * 2 + chr(ord(x) + 1) * 2 + chr(ord(x) + 2) * 2 for x in letters]
    out += [x * 6 for x in "0123456789"]
    out += "123123 212121 343434 434343 565656 656565 787878 878787 909090 101010".split()
    return out

def validate_catalog(document):
    if type(document) is not dict:
        raise ValueError("SAFE_STOP: group002 catalog is not a JSON object")
    required = {
        "format": "DEDA_ID_CANDIDATE_GROUP",
        "version": 1,
        "group": "002",
        "exclusive": False,
        "status": "proposal_only_not_for_sale",
        "prefix": "@DEDA-",
        "formatSuffix": "^[A-Z0-9]{6}$",
        "groupSize": 100,
    }
    for key, wanted in required.items():
        if type(document.get(key)) is not type(wanted) or document[key] != wanted:
            raise ValueError("SAFE_STOP: group002 metadata incorrect: " + key)
    values = document.get("identifiers")
    if not isinstance(values, list) or len(values) != 100:
        raise ValueError("SAFE_STOP: group002 must contain exactly 100 proposals")
    if any(not isinstance(v, str) or re.fullmatch("[A-Z0-9]{6}", v) is None for v in values):
        raise ValueError("SAFE_STOP: invalid six-character uppercase suffix")
    if len(set(values)) != 100 or len(set(x.casefold() for x in values)) != 100:
        raise ValueError("SAFE_STOP: duplicate group002 proposal")
    if values != expected_group002():
        raise ValueError("SAFE_STOP: proposed IDs changed from privately cross-checked 100")
    return ["@DEDA-" + v for v in values]

def dart_block(identifiers):
    lines = [
        MARKER,
        "// Group 002 proposals only; NOT verified against existing users in Firestore.",
        "// Never interpret this list as available stock or exclusive ownership.",
        "class DedaPoint10CandidateGroup002 {",
        "  static const List<String> identifiers = <String>[",
    ]
    lines += ["    '" + value + "'," for value in identifiers]
    lines += ["  ];", "}", ""]
    return "\n".join(lines) + "\n"

def apply(source, catalog):
    if source.count(PAGE) != 1 or source.count(PROFILE) != 1 or source.count(POINT9) != 1:
        raise ValueError("SAFE_STOP: point9 storefront/protected profile missing")
    identifiers = validate_catalog(catalog)
    block = dart_block(identifiers)
    if MARKER in source:
        if source.count(MARKER) != 1 or block not in source:
            raise ValueError("SAFE_STOP: group002 embedded catalog mismatch")
        if source.count(GROUP_ROUTE) != 1:
            raise ValueError("SAFE_STOP: group002 candidate route missing")
        if source.count(NEW_HEADING) != 1 or source.count(NEW_SUBTITLE) != 1:
            raise ValueError("SAFE_STOP: group002 candidate warning missing")
        return source
    if "class DedaPoint10CandidateGroup002" in source:
        raise ValueError("SAFE_STOP: another group002 catalog class exists")
    for text in (ROUTE, OLD_HEADING, OLD_SUBTITLE):
        if source.count(text) != 1:
            raise ValueError("SAFE_STOP: expected exact point9 source token: " + text[:50])
    result = source.replace(PAGE, block + PAGE, 1)
    for old, new in ((ROUTE, GROUP_ROUTE), (OLD_HEADING, NEW_HEADING),
                     (OLD_SUBTITLE, NEW_SUBTITLE)):
        result = result.replace(old, new, 1)
    reverted = result
    for old, new in reversed(((ROUTE, GROUP_ROUTE), (OLD_HEADING, NEW_HEADING),
                              (OLD_SUBTITLE, NEW_SUBTITLE))):
        reverted = reverted.replace(new, old, 1)
    reverted = reverted.replace(block, "", 1)
    if reverted != source:
        raise ValueError("SAFE_STOP: unexpected profile/catalog change outside point10")
    return result

if __name__ == "__main__":
    if not MAIN.is_file():
        raise SystemExit("SAFE_STOP: reconstructed lib/main.dart missing")
    try:
        catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
        old = MAIN.read_text(encoding="utf-8")
        new = apply(old, catalog)
    except (ValueError, OSError) as exc:
        raise SystemExit(str(exc))
    if new != old:
        MAIN.write_text(new, encoding="utf-8")
        print("PASS: Group 002 has exactly 100 six-character read-only preview proposals")
    else:
        print("PASS: stage10 already applied without duplicate candidates")
    print("PASS: group 001 private admin reserved IDs never uploaded; no purchase/ownership enabled")
