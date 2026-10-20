#!/usr/bin/env python3
"""Stage67: bind the REAL reconstructed 100359 compact card row to Spark.

The new authenticated Firestore adapter is dead OFF unless exact audited
Stage66 rules have been deployed separately, so this script cannot make a
false checkout appear to work. Original Stage17 checkout and foil remain
the unchanged fallback. Does not edit raw unreconstructed app baseline.
"""
from pathlib import Path

MAIN = Path('lib/main.dart')
A = 'class _DedaIdentifierStorePageState extends State<DedaIdentifierStorePage> {'
B = 'class _DedaProfilePhase2PageState extends State<DedaProfilePhase2Page> {'
IMPORT = "import 'deda_stage67_spark_card_action.dart';\n"
MARKER = "// DEDA_STAGE67_SPARK_AUTHENTICATED_CARD_PURCHASE_LINK_NO_DEPLOY"
OLD = """child: DedaPoint17ShopCardAction(
                  identifier: widget.identifier,
                  color: color,
                ),"""
NEW = """child: const bool.fromEnvironment(
                  'DEDA_STAGE67_VERIFIED_GIFT_CARD_RULES_DEPLOYED',
                  defaultValue: false,
                )
                    ? DedaStage67SparkCardAction(
                        originalId: DedaBackend.personalShareIdForPhone(
                          DedaPreferences.phone,
                        ).trim(),
                        style: color.name,
                      )
                    : DedaPoint17ShopCardAction(
                        identifier: widget.identifier,
                        color: color,
                      ),"""

def apply(src: str) -> str:
    if MARKER in src:
        if src.count(MARKER) != 1 or src.count(IMPORT) != 1 or NEW not in src:
            raise ValueError('SAFE_STOP_STAGE67_PARTIAL')
        return src
    if src.count(A) != 1 or src.count(B) != 1:
        raise ValueError('SAFE_STOP_DIFFERENT_FLUTTER_STORE')
    a, b = src.index(A), src.index(B)
    page = src[a:b]
    if page.count(OLD) != 1 or page.count('DedaPremiumIdCard(') != 1:
        raise ValueError('SAFE_STOP_COMPACT_CARD_SOURCE_CHANGED')
    if MARKER in src or IMPORT in src:
        raise ValueError('SAFE_STOP_DUPLICATE_STAGE67_LINK')
    page = page.replace(OLD, MARKER + '\n                ' + NEW, 1)
    updated = src[:a] + page + src[b:]
    anchor = "import 'package:flutter/material.dart';\n"
    if updated.count(anchor) != 1:
        raise ValueError('SAFE_STOP_IMPORTS_CHANGED')
    updated = updated.replace(anchor, anchor + IMPORT, 1)
    reconstructed = updated.replace(IMPORT, '', 1).replace(
        MARKER + '\n                ' + NEW, OLD, 1)
    if reconstructed != src:
        raise ValueError('SAFE_STOP_UNRELATED_UI_CHANGED')
    return updated

if __name__ == '__main__':
    old = MAIN.read_text()
    new = apply(old)
    if old != new: MAIN.write_text(new)
    print('PASS stage67 real Firestore transport applied to 100359 compact row; release flag OFF')
