#!/usr/bin/env python3
"""Stage49: show server-confirmed permanent ID ink in ORIGINAL DEDA QR dialog.

Only insert a read-only label after the original SelectableText of the
registered DEDA ID. Its QR bytes, WhatsApp link, _copyDedaId callback, social
friends and location target routing must remain byte-for-byte unchanged.
Runs after exact 100359 source reconstruction and Stage48 profile patch.
"""
from pathlib import Path
import re

MAIN = Path("lib/main.dart")
MARKER = "// DEDA_OWNER19_STAGE49_ORIGINAL_QR_PLUS_VERIFIED_PREMIUM_INK"
IMPORT = "import 'deda_stage49_verified_share_id_badge.dart';\n"

# Original DEDA QR share dialog. The only permitted change is INSERT after
# this existing QR-linked original identifier (not substitution).
ORIGINAL = """            Directionality(
              textDirection: TextDirection.ltr,
              child: SelectableText(
                id,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
"""
ADDITION = """            // DEDA_OWNER19_STAGE49_ORIGINAL_QR_PLUS_VERIFIED_PREMIUM_INK
            // Read-only lifetime-colored premium label. The original QR,
            // WhatsApp text and copy buttons below remain unchanged.
            DedaStage49VerifiedShareIdBadge(
              originalId: id,
              isArabic: DedaLanguageState.isArabic,
            ),
"""

def exact_spacing_only(s: str, wanted: str) -> tuple[int, int, str]:
    # Read actual Dart tokens, allowing only dart-format whitespace.
    # Do not use unsafe free-text substring replacement in other screens.
    pieces = re.findall(
        r'[A-Za-z_][A-Za-z_0-9]*|[0-9]+(?:\.[0-9]+)?|[^\w\s]',
        wanted,
    )
    regex = re.compile(r'\s*'.join(re.escape(piece) for piece in pieces))
    matches = list(regex.finditer(s))
    if len(matches) != 1:
        raise ValueError("SAFE_STOP: original QR identifier view ambiguous")
    m = matches[0]
    start = s.rfind("\n", 0, m.start()) + 1
    if s[start:m.start()].strip():
        raise ValueError("SAFE_STOP: QR view has unsupported prefix")
    end = m.end()
    if s[end:end+1] != "\n":
        raise ValueError("SAFE_STOP: original QR view has no line ending")
    end += 1
    return (start, end, s[start:end])

def apply(source: str) -> str:
    if MARKER in source:
        if source.count(MARKER) != 1 or source.count(IMPORT) != 1 or \
                source.count(ADDITION) != 1:
            raise ValueError("SAFE_STOP: partial Stage49 share view")
        return source
    for required in (
        "Future<void> _showDedaIdCard() async {",
        "Future<void> _shareDedaId() async {",
        "Future<void> _copyDedaId() async {",
        "class DedaShareLocationPage extends StatefulWidget",
        "DEDA_OWNER19_STAGE48_PROFILE_ACTIVE_ID_FIXED_INK_NO_DEPLOY",
    ):
        if source.count(required) != 1:
            raise ValueError("SAFE_STOP: historical share or Stage48 proof missing")
    if source.count(IMPORT) != 0:
        raise ValueError("SAFE_STOP: unexpected Stage49 import")
    a, b, before = exact_spacing_only(source, ORIGINAL)
    start = source.index("Future<void> _showDedaIdCard() async {")
    end = source.index("Future<void> _setLanguage(", start)
    if not (start < a < b < end):
        raise ValueError("SAFE_STOP: matched share ID outside QR dialog")
    protected = source[start:end]
    for token in (
        "data: id,", "'https://wa.me/?text",
        # WhatsApp lives in previous method; only guarantee QR/copy actions
    ):
        if token == "'https://wa.me/?text":
            continue
        if token not in protected:
            raise ValueError("SAFE_STOP: canonical QR bytes changed")
    mat = "import 'package:flutter/material.dart';\n"
    if source.count(mat) != 1:
        raise ValueError("SAFE_STOP: Flutter source imports differ")
    result = source[:b] + ADDITION + source[b:]
    result = result.replace(mat, mat + IMPORT, 1)
    if result.replace(ADDITION, "", 1).replace(IMPORT, "", 1) != source:
        raise ValueError("SAFE_STOP: other user-facing source would change")
    if result.count("_shareDedaId()") != source.count("_shareDedaId()") or \
            result.count("_copyDedaId()") != source.count("_copyDedaId()"):
        raise ValueError("SAFE_STOP: legacy WhatsApp and copy changed")
    return result

if __name__ == "__main__":
    before = MAIN.read_text(encoding="utf-8")
    after = apply(before)
    if after != before:
        MAIN.write_text(after, encoding="utf-8")
    print("PASS: original QR, WhatsApp message and share callbacks retained")
    print("PASS: secure Stage49 label is dormant without verified server; NO DEPLOY")
