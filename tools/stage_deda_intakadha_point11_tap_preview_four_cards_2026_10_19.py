#!/usr/bin/env python3
"""DEDA «إنت كدها» stage 11/16: one catalog tap previews an ID on all four foils.

Only the read-only store screen's local UI state changes.
Run after the original 100356 reconstruction and approved stages 2-10.
DO NOT change persisted account ID, inventory, diamonds, pricing or Firebase.
Candidate ID selection is visual ONLY; buying and claiming IDs remain disabled.
"""
from pathlib import Path

MAIN = Path("lib/main.dart")
STAGE9 = "// DEDA_INTAKADHA_POINT9_STICKY_FOUR_ID_CARDS_STORE_2026_10_18"
STAGE10 = "// DEDA_INTAKADHA_POINT10_GROUP002_100_UNVERIFIED_IDS_2026_10_18"
PAGE = "class DedaIdentifierStorePage extends StatelessWidget {"
PROFILE = "class _DedaProfilePhase2PageState extends State<DedaProfilePhase2Page> {"
MARKER = "// DEDA_INTAKADHA_POINT11_FOUR_CARDS_LIVE_ID_PREVIEW_2026_10_19"

# The original catalog is read-only. A selection is allowed for visual
# preview only if it is in the current list and passes the 6-char pattern.
# The original actual user identifier stays in widget.identifier.
HEADER_OLD = """class DedaIdentifierStorePage extends StatelessWidget {"""
HEADER_NEW = """// DEDA_INTAKADHA_POINT11_FOUR_CARDS_LIVE_ID_PREVIEW_2026_10_19
class DedaIdentifierStorePage extends StatefulWidget {"""

AFTER_CONSTRUCTOR_OLD = """  String _cardName(DedaPremiumIdCardColor color) {"""
AFTER_CONSTRUCTOR_NEW = """  @override
  State<DedaIdentifierStorePage> createState() => _DedaIdentifierStorePageState();
}

class _DedaIdentifierStorePageState extends State<DedaIdentifierStorePage> {
  // Ephemeral preview. Never writes to account, preferences, ownership or wallet.
  String? _previewIdentifier;

  String get _shownIdentifier => _previewIdentifier ?? widget.identifier;

  void _previewCandidate(String candidate) {
    // Only show actual read-only proposal rows. No purchase or ID activation.
    if (!widget.readOnlyCatalog.contains(candidate)) return;
    if (!RegExp(r'^@DEDA-[A-Z0-9]{6}$').hasMatch(candidate)) return;
    if (_previewIdentifier == candidate) return;
    setState(() {
      _previewIdentifier = candidate;
    });
  }

  String _cardName(DedaPremiumIdCardColor color) {"""

REPLACEMENTS = (
    (HEADER_OLD, HEADER_NEW, 1, "convert store-only page to StatefulWidget"),
    (AFTER_CONSTRUCTOR_OLD, AFTER_CONSTRUCTOR_NEW, 1,
     "add ephemeral selected ID and guarded preview callback"),
    ("            identifier: identifier,\n            color: color,",
     "            identifier: _shownIdentifier,\n            color: color,",
     1, "all 4 foils read one local selected ID"),
    ("itemCount: readOnlyCatalog.isEmpty",
     "itemCount: widget.readOnlyCatalog.isEmpty",
     1, "catalog size in StatefulWidget"),
    (": readOnlyCatalog.length + 1,",
     ": widget.readOnlyCatalog.length + 1,",
     1, "catalog list length in StatefulWidget"),
    ("if (readOnlyCatalog.isEmpty) {",
     "if (widget.readOnlyCatalog.isEmpty) {",
     1, "empty catalog guard in StatefulWidget"),
    ("final candidate = readOnlyCatalog[index - 1];",
     "final candidate = widget.readOnlyCatalog[index - 1];",
     1, "candidate list source in StatefulWidget"),
    ("""                        leading: const Icon(Icons.badge_outlined),
                        // No onTap. Point 11 will add a guarded selection.""",
     """                        leading: const Icon(Icons.badge_outlined),
                        selected: _previewIdentifier == candidate,
                        selectedTileColor: const Color(0xFFEDE5F6),
                        trailing: Icon(
                          _previewIdentifier == candidate
                              ? Icons.visibility_rounded
                              : Icons.visibility_outlined,
                          color: const Color(0xFF7643A5),
                        ),
                        // Free local preview ONLY. No purchase or activation.
                        onTap: () => _previewCandidate(candidate),""",
     1, "read-only catalog selection changes local foil text only"),
)

def apply(source: str) -> str:
    if source.count(STAGE9) != 1 or source.count(STAGE10) != 1:
        raise ValueError("SAFE_STOP: approved point9/point10 stages missing")
    if source.count(PROFILE) != 1:
        raise ValueError("SAFE_STOP: missing/duplicate original profile anchor")
    if MARKER in source:
        if source.count(MARKER) != 1 or HEADER_NEW not in source or \
                AFTER_CONSTRUCTOR_NEW not in source:
            raise ValueError("SAFE_STOP: inconsistent partial point11 stage")
        if "onTap: () => _previewCandidate(candidate)," not in source:
            raise ValueError("SAFE_STOP: stage11 catalog preview callback removed")
        if "identifier: _shownIdentifier," not in source:
            raise ValueError("SAFE_STOP: four foils no longer bound to preview")
        return source
    if source.count(PAGE) != 1:
        raise ValueError("SAFE_STOP: expected one point9 stateless store page")
    a = source.index(PAGE)
    b = source.index(PROFILE, a)
    page = source[a:b]
    if page.count("key: const Key('deda_point9_fixed_four_cards')") != 1 or \
       page.count("key: const Key('deda_point9_scrollable_identifiers_below_cards')") != 1:
        raise ValueError("SAFE_STOP: pinned header and independently scrollable list missing")
    if page.count("مرشحات المجموعة 002 — للمعاينة فقط") != 1 or \
       page.count("مرشح غير متحقق من توفره — لا شراء ولا تفعيل") != 1:
        raise ValueError("SAFE_STOP: catalog must remain unverified and not for sale")
    updated = page
    for original, replacement, occurrences, description in REPLACEMENTS:
        if updated.count(original) != occurrences:
            raise ValueError("SAFE_STOP: modified original stage: " + description)
        updated = updated.replace(original, replacement, occurrences)
    # Check only the whitelisted changes and preserve 100356 account logic bytewise.
    restored = updated
    for original, replacement, occurrences, _ in reversed(REPLACEMENTS):
        if restored.count(replacement) != occurrences:
            raise ValueError("SAFE_STOP: conflicting stage11 transformation")
        restored = restored.replace(replacement, original, occurrences)
    if restored != page:
        raise ValueError("SAFE_STOP: unrelated changes inside store")
    result = source[:a] + updated + source[b:]
    if result[:a] != source[:a] or result[a + len(updated):] != source[b:]:
        raise ValueError("SAFE_STOP: account or other Flutter code changed")
    return result

if __name__ == "__main__":
    if not MAIN.is_file():
        raise SystemExit("SAFE_STOP: reconstructed Flutter lib/main.dart missing")
    previous = MAIN.read_text(encoding="utf-8")
    try:
        result = apply(previous)
    except ValueError as exc:
        raise SystemExit(str(exc))
    if result == previous:
        print("PASS: point11 already applied exactly once")
    else:
        MAIN.write_text(result, encoding="utf-8")
        print("PASS: catalog tap previews selected six-character ID on all four pinned cards")
    print("PASS: original ID, ownership, prices, diamonds, Firebase and purchases unchanged")
