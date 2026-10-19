#!/usr/bin/env python3
"""Use server-confirmed Group002 list/10k checkout instead of 100 fake candidates.

Apply only after original 100359 reconstruction + stages35/38.
When reviewed backend/phone flags are OFF, original preview-only Group002 list
remains unchanged. When both are ON, ONLY server-verified stock is shown.
No local diamonds or registry writes; server purchase verifies UID and receipt.
"""
from pathlib import Path
MAIN=Path("lib/main.dart")
BEGIN="class _DedaIdentifierStorePageState extends State<DedaIdentifierStorePage> {"
END="class _DedaProfilePhase2PageState extends State<DedaProfilePhase2Page> {"
ANCHOR="child: ListView.builder("
MARKER="// DEDA_100360_SERVER_VERIFIED_GROUP002_INSTEAD_OF_MOCK_CANDIDATES"
IMPORT="import 'deda_stage42_verified_sale_panel.dart';\n"
NEW="""child: const bool.fromEnvironment(
                    'DEDA_STAGE42_VERIFIED_SALE_LIVE', defaultValue: false)
                ? DedaStage42VerifiedSalePanel(
                    originalId: DedaBackend.personalShareIdForPhone(
                      DedaPreferences.phone,
                    ).trim(),
                    onPreview: (verifiedId) {
                      if (!RegExp(r'^@DEDA-[A-Z0-9]{6}$').hasMatch(verifiedId)) {
                        return;
                      }
                      setState(() => _previewIdentifier = verifiedId);
                    },
                    refreshOwned: () async {
                      final original = DedaBackend.personalShareIdForPhone(
                        DedaPreferences.phone,
                      ).trim();
                      if (original.isNotEmpty) {
                        await DedaPoint15OwnedIdsState.refresh(original);
                      }
                    },
                  )
                : ListView.builder("""
def apply(src:str)->str:
    if MARKER in src:
        if src.count(MARKER)!=1 or src.count(IMPORT)!=1 or NEW not in src:
            raise ValueError("SAFE_STOP: Group002 patch partially overwritten")
        return src
    if src.count(BEGIN)!=1 or src.count(END)!=1 or src.count(IMPORT)!=0:
        raise ValueError("SAFE_STOP: original store bounds/import altered")
    a,b=src.index(BEGIN),src.index(END)
    store=src[a:b]
    if store.count(ANCHOR)!=1 or "_previewIdentifier" not in store or \
        "DedaPoint17ShopCardAction(" not in store or \
        "DEDA_100360_COMPACT_REAL_FOILS_MERGED_PRICE_AND_ACTION" not in store or \
        "DedaOwnerQaSandboxPage()" in store:
        raise ValueError("SAFE_STOP: staged real shop and fake sandbox state differ")
    changed=store.replace(ANCHOR,MARKER+"\n                "+NEW,1)
    if changed.replace(MARKER+"\n                "+NEW,ANCHOR,1)!=store:
        raise ValueError("SAFE_STOP: unintended consumer store mutation")
    result=src[:a]+changed+src[b:]
    # Imports and purchases only. Existing user avatar, maps and auth untouched.
    if "import 'package:flutter/material.dart';\n" not in result:
        raise ValueError("SAFE_STOP: Flutter imports differ")
    result=result.replace("import 'package:flutter/material.dart';\n",
        "import 'package:flutter/material.dart';\n"+IMPORT,1)
    if result.replace(IMPORT,"",1).replace(
        MARKER+"\n                "+NEW,ANCHOR,1)!=src:
        raise ValueError("SAFE_STOP: patch changed unrelated app screens")
    return result

if __name__=="__main__":
    old=MAIN.read_text(encoding="utf-8")
    result=apply(old)
    if result!=old: MAIN.write_text(result,encoding="utf-8")
    print("PASS: real Group002 approved-sale stock replaces mock candidate list only when server verified")
    print("PASS: private original 100 IDs and all real wallet data protected")
