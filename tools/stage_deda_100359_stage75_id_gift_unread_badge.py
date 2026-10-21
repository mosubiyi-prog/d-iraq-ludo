#!/usr/bin/env python3
"""Stage75 badge patch on the REAL reconstructed DEDA app, without deployment.

Combine the pre-existing diamond gift badge with verified, unseen identifier
gifts. No original diamond gift claim flow, Firebase rules or account data
is modified. Opening the ID gift inbox marks the visible IDs as *viewed*,
NOT claimed; claiming remains a separate explicit user action.
"""
from pathlib import Path

MAIN = Path("lib/main.dart")
SECTION = Path("lib/deda_stage74_hadaya_identifier_section.dart")
MARK = "// DEDA_STAGE75_UNREAD_ID_GIFTS_PLUS_LEGACY_DIAMOND_BADGE_NO_DEPLOY"
IMPORT = "import 'deda_stage75_unread_gift_badge.dart';\n"
MATERIAL = "import 'package:flutter/material.dart';\n"

def once(source, original, updated):
    count = source.count(original)
    if count != 1:
        raise ValueError("SAFE_STOP_STAGE75_EXPECTED_ONE_MATCH count=" + str(count)
                         + " match=" + repr(original[:100]))
    return source.replace(original, updated, 1)

def patch_main(source):
    if MARK in source:
        if source.count(MARK) != 1 or source.count(IMPORT) != 1:
            raise ValueError("SAFE_STOP_STAGE75_PARTIAL_MAIN")
        return source
    begin = "class _DedaGiftNavBadgeState extends State<DedaGiftNavBadge> {"
    end = "class DedaMyGiftsPage extends StatefulWidget {"
    if source.count(begin) != 1 or source.count(end) != 1:
        raise ValueError("SAFE_STOP_STAGE75_OLD_NAV_MISSING")
    a, b = source.index(begin), source.index(end)
    section = source[a:b]
    section = once(
        section,
        "    unawaited(DedaGiftInbox.start());\n",
        "    unawaited(DedaGiftInbox.start());\n"
        "    unawaited(DedaStage75UnreadGiftBadge.start(\n"
        "      DedaBackend.personalShareIdForPhone(DedaPreferences.phone).trim(),\n"
        "    ));\n",
    )
    section = once(
        section,
        "        builder: (context, pending, _) => Stack(\n",
        "        builder: (context, diamondPending, _) => ValueListenableBuilder<int>(\n"
        "          valueListenable: DedaStage75UnreadGiftBadge.pendingNotifier,\n"
        "          builder: (context, idPending, __) {\n"
        "            final pending = diamondPending + idPending;\n"
        "            return Stack(\n",
    )
    section = once(
        section,
        "          ],\n        ),\n      ),\n    );\n",
        "          ],\n            );\n          },\n        ),\n      ),\n    );\n",
    )
    if section.count("final pending = diamondPending + idPending;") != 1:
        raise ValueError("SAFE_STOP_STAGE75_NO_COMBINED_COUNTER")
    source = source[:a] + section + source[b:]
    source = once(source, MATERIAL, MATERIAL + IMPORT + MARK + "\n")
    return source

def patch_section(source):
    if "DEDA_STAGE75_GIFT_SEEN_ON_INBOX_VIEW" in source:
        if source.count("DedaStage75UnreadGiftBadge.markViewed(") != 1:
            raise ValueError("SAFE_STOP_STAGE75_PARTIAL_SECTION")
        return source
    source = once(source, "import 'package:flutter/material.dart';\n",
        "import 'dart:async';\n\nimport 'package:flutter/material.dart';\n")
    source = once(source, "import 'deda_stage74_id_gift_service.dart';\n",
        "import 'deda_stage74_id_gift_service.dart';\n" + IMPORT)
    source = once(source, "    _refresh();\n  }\n\n  @override\n  void didUpdateWidget",
        "    unawaited(DedaStage75UnreadGiftBadge.start(widget.originalId));\n"
        "    _refresh();\n  }\n\n  @override\n  void didUpdateWidget")
    source = once(source,
        "    if (oldWidget.originalId != widget.originalId) _refresh();",
        "    if (oldWidget.originalId != widget.originalId) {\n"
        "      unawaited(DedaStage75UnreadGiftBadge.start(widget.originalId));\n"
        "      _refresh();\n    }")
    source = once(source,
        "      setState(() => _gifts = gifts);\n",
        "      setState(() => _gifts = gifts);\n"
        "      // DEDA_STAGE75_GIFT_SEEN_ON_INBOX_VIEW\n"
        "      // This is a read marker ONLY, never an ownership/claim mutation.\n"
        "      unawaited(DedaStage75UnreadGiftBadge.markViewed(originalId, gifts));\n")
    return source

if __name__ == "__main__":
    orig_main = MAIN.read_text()
    orig_section = SECTION.read_text()
    patched_main = patch_main(orig_main)
    patched_section = patch_section(orig_section)
    if patched_main == orig_main or patched_section == orig_section:
        raise ValueError("SAFE_STOP_STAGE75_NO_COMPLETE_DUAL_PATCH")
    MAIN.write_text(patched_main)
    SECTION.write_text(patched_section)
    print("PASS_STAGE75_BADGE_ID_GIFT_UNREAD_PLUS_DIAMOND_PENDING_COUNTER")
    print("PASS_STAGE75_RECEIPT_AND_CLAIM_NOT_TOUCHED_NO_FIREBASE_WRITE_NO_DEPLOY")
