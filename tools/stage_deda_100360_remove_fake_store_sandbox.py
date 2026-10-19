#!/usr/bin/env python3
"""Remove the temporary fake-diamond and fake-GM-grant widget from final store.

Stage after original signed 100359 source assembly, before *any* later signed
owner 19-point build. The standalone lab source may remain for test archives,
but is not imported, linked or reachable in the app store. Does not activate
any real purchase, grant, or change user data/production services.
"""
from pathlib import Path
MAIN = Path("lib/main.dart")
MARKER = "// DEDA_STAGE31_OWNER_QA_LAUNCH_SANDBOX_ONLY_2026_10_19"
IMPORT = "import 'deda_owner_review_sandbox_stage31.dart';\n"
START = "class _DedaIdentifierStorePageState extends State<DedaIdentifierStorePage> {"
END = "class _DedaProfilePhase2PageState extends State<DedaProfilePhase2Page> {"
BUTTON = "deda_stage31_open_private_sandbox"
NEXT = "const SizedBox(height: 7),"


def apply(source: str) -> str:
    if MARKER not in source:
        if IMPORT in source or BUTTON in source or "DedaOwnerQaSandboxPage()" in source:
            raise ValueError("SAFE_STOP: incomplete sandbox removal")
        return source
    if source.count(MARKER) != 1 or source.count(IMPORT) != 1:
        raise ValueError("SAFE_STOP: unexpected extra QA sandbox")
    if source.count(START) != 1 or source.count(END) != 1:
        raise ValueError("SAFE_STOP: signed store boundaries changed")
    begin, end = source.index(START), source.index(END)
    store = source[begin:end]
    if store.count(MARKER) != 1 or store.count(BUTTON) != 1:
        raise ValueError("SAFE_STOP: QA launcher not in approved shop")
    pos = store.index(MARKER)
    tail = store[pos:]
    if (
        "const bool.fromEnvironment(" not in tail[:250]
        or "DEDA_OWNER_PRIVATE_SANDBOX" not in tail[:250]
        or "DedaOwnerQaSandboxPage()" not in tail
        or "مختبر تجربة الشراء والمنح" not in tail
        or "DedaPoint17ShopCardAction(" not in store
    ):
        raise ValueError("SAFE_STOP: staging shop structure mismatch")
    next_pos = store.find(NEXT, pos)
    if next_pos < 0:
        raise ValueError("SAFE_STOP: original spacer removed")
    start_line = store.rfind("\n", 0, pos) + 1
    end_line = store.rfind("\n", 0, next_pos) + 1
    removable = store[start_line:end_line]
    for phrase in (MARKER, BUTTON, "DedaOwnerQaSandboxPage()",
                   "مختبر تجربة الشراء والمنح"):
        if phrase not in removable:
            raise ValueError("SAFE_STOP: not an exact legacy QA launcher")
    replacement = store[:start_line] + store[end_line:]
    updated = source[:begin] + replacement + source[end:]
    updated = updated.replace(IMPORT, "", 1)
    if MARKER in updated or BUTTON in updated or             "DedaOwnerQaSandboxPage()" in updated or IMPORT in updated:
        raise ValueError("SAFE_STOP: private mock remains reachable")
    # Reconstruct and confirm we modified only one old launcher and one import.
    restored = updated.replace(START,
        START, 1).replace(replacement, store, 1)
    if restored != source.replace(IMPORT, "", 1):
        raise ValueError("SAFE_STOP: unrelated user-facing behavior changed")
    return updated


if __name__ == "__main__":
    previous = MAIN.read_text(encoding="utf-8")
    result = apply(previous)
    if result != previous:
        MAIN.write_text(result, encoding="utf-8")
    print("PASS: owner QA fake purchases and grants removed from final shop routing")
    print("PASS: approved real 4-card artwork/verification flow unchanged")
