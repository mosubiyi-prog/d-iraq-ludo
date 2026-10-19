#!/usr/bin/env python3
"""Stage31: link owner-only RAM sandbox to existing stage17 ID store.

Runs against CI reconstructed 100358 source AFTER point17. Does not modify
repository main.dart, server functions, Firestore, user diamonds or real
rewarded ads. Strict anchors; abort on any change to proven store structure.
"""
from pathlib import Path

MAIN = Path("lib/main.dart")
MARKER = "// DEDA_STAGE31_OWNER_QA_LAUNCH_SANDBOX_ONLY_2026_10_19"
BEGIN = "class _DedaIdentifierStorePageState extends State<DedaIdentifierStorePage> {"
END = "class _DedaProfilePhase2PageState extends State<DedaProfilePhase2Page> {"
ANCHOR = "              const SizedBox(height: 7),\n              Expanded("
ADDITION = """              // DEDA_STAGE31_OWNER_QA_LAUNCH_SANDBOX_ONLY_2026_10_19
              if (const bool.fromEnvironment(
                'DEDA_OWNER_PRIVATE_SANDBOX', defaultValue: false))
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: OutlinedButton.icon(
                    key: const Key('deda_stage31_open_private_sandbox'),
                    icon: const Icon(Icons.science_outlined),
                    onPressed: () => Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => const DedaOwnerQaSandboxPage())),
                    label: const Text('مختبر تجربة الشراء والمنح — بدون خصم حقيقي'),
                  ),
                ),
              const SizedBox(height: 7),
              Expanded("""
IMPORT = "import 'deda_owner_review_sandbox_stage31.dart';\n"

def apply(source: str) -> str:
    if MARKER in source:
        if source.count(MARKER) != 1 or source.count(IMPORT) != 1:
            raise ValueError("SAFE_STOP: partial or duplicated owner QA launcher")
        return source
    if source.count(BEGIN) != 1 or source.count(END) != 1:
        raise ValueError("SAFE_STOP: stage17 store class boundaries changed")
    if "DEDA_STAGE17_STORE_CARDS_BLUE_OWNED_IDS_2026_10_19" not in source:
        raise ValueError("SAFE_STOP: proven 100358 shop stage missing")
    if "DedaPoint15OwnedIdsBridge.grantReservedRemote = null;" not in source:
        raise ValueError("SAFE_STOP: exclusive admin grant backend unexpectedly active")
    if "DEDA_PREMIUM_IDS_SERVER_LIVE" not in source:
        raise ValueError("SAFE_STOP: real purchase gate missing")
    begin,end = source.index(BEGIN), source.index(END)
    store = source[begin:end]
    if store.count(ANCHOR) != 1:
        raise ValueError("SAFE_STOP: fixed-card shop header layout not recognized")
    if 'DedaPoint17ShopCardAction(' not in store:
        raise ValueError("SAFE_STOP: genuine verified-card widget missing")
    store = store.replace(ANCHOR, ADDITION, 1)
    changed = source[:begin] + store + source[end:]
    if IMPORT in changed:
        raise ValueError("SAFE_STOP: duplicate QA import")
    changed = IMPORT + changed
    if changed.replace(IMPORT, "", 1).replace(ADDITION, ANCHOR, 1) != source:
        raise ValueError("SAFE_STOP: unauthorized modification to reconstructed app")
    return changed

def main():
    if not Path("lib/deda_owner_review_sandbox_stage31.dart").exists():
        raise ValueError("SAFE_STOP: owner sandbox source file absent")
    before = MAIN.read_text(encoding="utf-8")
    after = apply(before)
    if after != before:
        MAIN.write_text(after, encoding="utf-8")
    print("PASS: 100358 untouched, owner-only QA simulator reached from store")
    print("PASS: all production diamond purchases, grants, aliases remain OFF")

if __name__ == "__main__":
    main()
