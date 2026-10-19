#!/usr/bin/env python3
"""Compact the owner-visible ID shop without replacing four ORIGINAL artworks.

Apply only AFTER full 100359 source assembly + stage17 purchase actions,
BEFORE a separately approved new APK. No wallet, Firebase, catalog or profile
data edits. Each intact 50px foil retains its original Image/Canvas renderer.
Move purchase/use under each full-width art INTO the price/label row.
"""
from pathlib import Path

MAIN = Path("lib/main.dart")
STORE_BEGIN = "class _DedaIdentifierStorePageState extends State<DedaIdentifierStorePage> {"
STORE_END = "class _DedaProfilePhase2PageState extends State<DedaProfilePhase2Page> {"
METHOD = "  Widget _fixedCard(DedaPremiumIdCardColor color) {"
METHOD_END = "  @override\n  Widget build(BuildContext context) {"
MARKER = "// DEDA_100360_COMPACT_REAL_FOILS_MERGED_PRICE_AND_ACTION"
ACTION = """          const SizedBox(height: 3),
          DedaPoint17ShopCardAction(
            identifier: widget.identifier,
            color: color,
          ),
"""
ROW_TAIL = """            ],
          ),
        ],
      ),
    );
  }

"""
ROW_TAIL_NEW = """              const SizedBox(width: 4),
              SizedBox(
                width: 125,
                child: DedaPoint17ShopCardAction(
                  identifier: widget.identifier,
                  color: color,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

"""

def apply(source: str) -> str:
    if MARKER in source:
        if source.count(MARKER) != 1 or ROW_TAIL_NEW not in source:
            raise ValueError("SAFE_STOP: compact foil marker corrupted")
        return source
    if source.count(STORE_BEGIN) != 1 or source.count(STORE_END) != 1:
        raise ValueError("SAFE_STOP: store boundaries missing or duplicated")
    a, b = source.index(STORE_BEGIN), source.index(STORE_END)
    store = source[a:b]
    if store.count(METHOD) != 1 or store.count(METHOD_END) != 1:
        raise ValueError("SAFE_STOP: approved store card method differs")
    m, e = store.index(METHOD), store.index(METHOD_END)
    card = store[m:e]
    for marker in (
        "DedaPremiumIdCard(",
        "height: 50,",
        "DedaPoint17ShopCardAction(",
        "_cardName(color)",
        "'تصميم البطاقة: 5,000 ماسة'",
    ):
        if card.count(marker) != 1:
            raise ValueError("SAFE_STOP: lost approved artwork/price/action "+marker)
    if card.count(ACTION) != 1 or card.count(ROW_TAIL) != 1:
        raise ValueError("SAFE_STOP: expected four-card label/price/action layout absent")
    changed = card.replace(ACTION, "", 1).replace(ROW_TAIL, ROW_TAIL_NEW, 1)
    # Forensic diff whitelist: stripping the moved action restores old method.
    restored = changed.replace(ROW_TAIL_NEW, ROW_TAIL, 1)
    insert_anchor = "        ],\n      ),\n    );\n  }\n\n"
    if restored != card.replace(ACTION, "", 1):
        raise ValueError("SAFE_STOP: moved unexpected store widget")
    store = store[:m] + "  " + MARKER + "\n" + changed + store[e:]
    new = source[:a] + store + source[b:]
    if source.count("class DedaPoint17ShopCardAction") != new.count(
        "class DedaPoint17ShopCardAction"):
        raise ValueError("SAFE_STOP: action widget unexpectedly changed")
    if new.count("DedaPremiumIdCard(") != source.count("DedaPremiumIdCard("):
        raise ValueError("SAFE_STOP: foil art unexpectedly changed")
    return new

if __name__ == "__main__":
    original = MAIN.read_text(encoding="utf-8")
    updated = apply(original)
    if updated != original:
        MAIN.write_text(updated, encoding="utf-8")
    print("PASS: four original 50px foils retained, no duplicate action rows")
    print("PASS: price and purchase action share compact line; no real wallet changed")
