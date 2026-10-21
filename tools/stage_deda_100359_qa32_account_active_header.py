#!/usr/bin/env python3
"""QA32: display the VERIFIED active alias in the existing top Account Info card.

Apply only AFTER true 100359 reconstruction, Stage71 and Stage75. Preserve
canonical original account ID, buttons and original-ID routing. No Firebase
writes, new account, new card, changes to wallets, places, rules, or gifts.
"""
from pathlib import Path

MAIN = Path("lib/main.dart")
MARKER = "// DEDA_QA32_ACCOUNT_ACTIVE_ALIAS_READONLY_DISPLAY_NO_DEPLOY"
IMPORT = "import 'deda_qa32_active_account_scope.dart';\n"
MATERIAL = "import 'package:flutter/material.dart';\n"
ACCOUNT = "class _DedaAccountInfoPageState extends State<DedaAccountInfoPage> {"
END = "class DedaDiamondsState {"
START = "Widget _ownedIdsCompactCard() {"

def apply(source: str) -> str:
    if MARKER in source:
        if source.count(MARKER) != 1 or source.count(IMPORT) != 1 or \
           source.count("DedaQa32ActiveAccountScope(") != 1:
            raise ValueError("SAFE_STOP_QA32_PARTIAL_ACCOUNT_ALIAS")
        return source
    if source.count(ACCOUNT) != 1 or source.count(END) != 1:
        raise ValueError("SAFE_STOP_QA32_ACCOUNT_BOUNDARIES")
    a=source.index(ACCOUNT)
    b=source.index(END,a)
    section=source[a:b]
    if section.count(START)!=1 or section.count("_ownedIdsCompactCard(),")!=1:
        raise ValueError("SAFE_STOP_QA32_COMPACT_HEADER_NOT_UNIQUE")
    start=section.index(START)
    finish=section.find("\n  @override",start)
    if finish<start or finish-start>12500:
        raise ValueError("SAFE_STOP_QA32_COMPACT_HEADER_END")
    old=section[start:finish]
    status="dedaText('الأصلي • فعّال', 'Original • active'),"
    chip="child: Text(\n                      displayId,"
    controls=(
        "deda_point7_switch_opens_id_manager",
        "deda_point7_edit_identifier_action",
        "if (_showIdentifierManagement) _identifierManagementPanel(displayId)",
    )
    if old.count(status)!=1 or old.count(chip)!=1 or any(
            old.count(item)!=1 for item in controls):
        raise ValueError("SAFE_STOP_QA32_ORIGINAL_ACCOUNT_ARTWORK_CHANGED")
    modified=old.replace(START,
        "Widget _ownedIdsCompactCardBody({String? visibleAlias, "
        "bool premiumActive = false}) {",1)
    modified=modified.replace(status,
        "premiumActive\n"
        "                      ? dedaText('المميز • فعّال', 'Premium • active')\n"
        "                      : dedaText('الأصلي • فعّال', 'Original • active'),",1)
    modified=modified.replace(chip,
        "child: Text(\n                      visibleAlias ?? displayId,",1)
    wrapper="""// DEDA_QA32_ACCOUNT_ACTIVE_ALIAS_READONLY_DISPLAY_NO_DEPLOY
  // Use one verified snapshot for status and visible name. The original ID
  // remains the target for Edit/Switch routing, owned rows, friends and GPS.
  Widget _ownedIdsCompactCard() {
    final original = DedaBackend.personalShareIdForPhone(
      DedaPreferences.phone,
    ).trim();
    return DedaQa32ActiveAccountScope(
      originalId: original,
      builder: (context, proof) => _ownedIdsCompactCardBody(
        visibleAlias: proof?.isPremium == true ? proof!.displayId : null,
        premiumActive: proof?.isPremium == true,
      ),
    );
  }

  """
    section=section[:start]+wrapper+modified+section[finish:]
    if section.count("deda_point7_switch_opens_id_manager")!=1 or \
       section.count("deda_point7_edit_identifier_action")!=1 or \
       section.count("if (_showIdentifierManagement) _identifierManagementPanel(displayId)")!=1:
        raise ValueError("SAFE_STOP_QA32_ORIGINAL_ACCOUNT_ACTIONS_CHANGED")
    result=source[:a]+section+source[b:]
    if result.count(MATERIAL)!=1 or IMPORT in result:
        raise ValueError("SAFE_STOP_QA32_IMPORT_AMBIGUOUS")
    result=result.replace(MATERIAL,MATERIAL+IMPORT,1)
    if result.count("DedaQa32ActiveAccountScope(")!=1:
        raise ValueError("SAFE_STOP_QA32_ACTIVE_SCOPE_MISSING")
    # Only the original method and exactly one import may change.
    if result.replace(MATERIAL+IMPORT,MATERIAL,1).replace(
            wrapper+modified,old,1)!=source:
        raise ValueError("SAFE_STOP_QA32_OUTSIDE_HEADER_CHANGE")
    return result

if __name__ == "__main__":
    before=MAIN.read_text()
    updated=apply(before)
    if updated!=before: MAIN.write_text(updated)
    print("PASS_QA32_ACCOUNT_TOP_ID_VERIFIED_ALIAS_AND_STATUS")
    print("PASS_QA32_SAME_BUTTONS_ORIGINAL_ROUTING_NO_LIVE_WRITES")
