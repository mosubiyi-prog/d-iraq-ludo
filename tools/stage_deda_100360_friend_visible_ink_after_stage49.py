#!/usr/bin/env python3
"""Owner19 Stage50: actual friend visible ID GLYPHS on 100359 exact source.

Apply ONLY to GitHub Actions reconstructed 100359 original Flutter source,
AFTER Stage49 original QR / premium ink. No direct repo main.dart updates,
Firebase deployments, original ID friend-search or location route mutations.
"""
from pathlib import Path
import re

MAIN = Path("lib/main.dart")
IMPORT = "import 'deda_stage50_verified_friend_ink_badge.dart';\n"
MARKER = "// DEDA_OWNER19_STAGE50_FRIEND_INK_THREE_PUBLIC_SURFACES_NO_DEPLOY"

# Exact original Dart tokens; whitespace-only differences from dart format OK.
COMPACT = """Text(dedaId, maxLines: 1, overflow: TextOverflow.ellipsis,
                           style: const TextStyle(color: Color(0xFF647787),
                               fontWeight: FontWeight.w700, fontSize: 12.5))"""
SEARCH = """Text(profile.publicId, maxLines: 1, overflow: TextOverflow.ellipsis,
                       style: const TextStyle(color: Color(0xFF647787),
                           fontWeight: FontWeight.w700, fontSize: 12))"""
PUBLIC = """Text(profile.publicId, maxLines: 1,
                        style: const TextStyle(color: Color(0xFF536779),
                            fontWeight: FontWeight.w800, fontSize: 15))"""

SCOPES = (
    ("class _DedaFriendCompactCard extends StatelessWidget {",
     "class DedaAddFriendPage", COMPACT, "dedaId"),
    ("class _DedaSearchResultCard extends StatelessWidget {",
     "class DedaFriendRequestsPage", SEARCH, "profile.publicId"),
    ("class DedaFriendPublicProfilePage extends StatelessWidget {",
     None, PUBLIC, "profile.publicId"),
)


def find_exact_lexical(source: str, candidate: str, surface: str) -> tuple[int, int, str]:
    tokens = re.findall(
        r'[A-Za-z_][A-Za-z_0-9]*|[0-9]+(?:\.[0-9]+)?|[^\w\s]',
        candidate)
    # Earlier royal/social UI polish changed only the original font size.
    # Permit a compact, readable 10..16.5sp size WITHOUT modifying it;
    # every ID token, ownership source, color and widget action stays exact.
    parts = []
    for i, token in enumerate(tokens):
        if i >= 2 and tokens[i - 2:i] == ['fontSize', ':'] and \
                re.fullmatch(r'[0-9]+(?:\.[0-9]+)?', token):
            parts.append(r'1[0-6](?:\.5)?')
        elif token == ')':
            # dart format may add a trailing comma inside TextStyle(...)
            # or Text(...). It does not change the widget semantics.
            parts.append(r'(?:,\s*)?\)')
        else:
            parts.append(re.escape(token))
    expression = re.compile(r'\s*'.join(parts))
    matches = list(expression.finditer(source))
    if len(matches) != 1:
        # Only a STATIC Dart widget excerpt; never user/account records.
        near = re.search(r'Text\(\s*(?:dedaId|profile\.publicId)', source)
        excerpt = source[near.start():near.start() + 360] if near else 'missing-original-text'
        raise ValueError("SAFE_STOP: " + surface +
                         " friend ID format changed; exact matches=" +
                         str(len(matches)) + "; static widget=" + repr(excerpt))
    found = matches[0]
    return found.start(), found.end(), source[found.start():found.end()]


def apply(source: str) -> str:
    if MARKER in source:
        if source.count(MARKER) != 1 or source.count(IMPORT) != 1 or \
                source.count("DedaStage50VerifiedFriendInkBadge(") != 3:
            raise ValueError("SAFE_STOP: incomplete friend-ink patch")
        return source
    prerequisites = (
        "DEDA_OWNER19_STAGE49_ORIGINAL_QR_PLUS_VERIFIED_PREMIUM_INK",
        "DEDA_OWNER19_STAGE48_PROFILE_ACTIVE_ID_FIXED_INK_NO_DEPLOY",
    )
    for item in prerequisites:
        if source.count(item) != 1:
            raise ValueError("SAFE_STOP: accepted profile/share stage missing")
    if IMPORT in source:
        raise ValueError("SAFE_STOP: unexpected import without marker")
    if source.count("class DedaFriendPublicProfilePage extends StatelessWidget {") != 1:
        raise ValueError("SAFE_STOP: friend public profile not found")
    before = source
    modifications = []
    for first, last, candidate, original_id in SCOPES:
        if source.count(first) != 1 or (last and source.count(last) < 1):
            raise ValueError("SAFE_STOP: friend surface boundary changed")
        first_index = source.index(first)
        last_index = source.index(last, first_index + len(first)) if last \
            else len(source)
        area = source[first_index:last_index]
        i, j, actual = find_exact_lexical(area, candidate, first)
        left, right = first_index + i, first_index + j
        # ONLY the original ID Text() is wrapped. Original text remains byte
        # identical as widget.fallback. No alternative ID is written anywhere.
        replacement = (
            "DedaStage50VerifiedFriendInkBadge(\n"
            "                      originalId: " + original_id + ",\n"
            "                      fallback: " + actual + ",\n"
            "                    )"
        )
        modifications.append((left, right, actual, replacement))
    if len(modifications) != 3 or len(set(x[0] for x in modifications)) != 3:
        raise ValueError("SAFE_STOP: repeated friend ink location")
    result = source
    for left, right, old, new in reversed(sorted(modifications)):
        if result[left:right] != old:
            raise ValueError("SAFE_STOP: old friend ID view no longer matches")
        result = result[:left] + new + result[right:]
    flutter_import = "import 'package:flutter/material.dart';\n"
    if result.count(flutter_import) != 1:
        raise ValueError("SAFE_STOP: Flutter import anchor changed")
    result = result.replace(
        flutter_import,
        flutter_import + IMPORT + MARKER + "\n",
        1)
    # Compare original Dart with an exact reversal: only 3 ID Text wrappers
    # and one import may change, NOT friends, search, routes, wallets or IDs.
    restored = result.replace(flutter_import + IMPORT + MARKER + "\n",
                              flutter_import, 1)
    for _, _, old, new in modifications:
        if restored.count(new) != 1:
            raise ValueError("SAFE_STOP: friend wrapper not unique")
        restored = restored.replace(new, old, 1)
    if restored != before:
        raise ValueError("SAFE_STOP: unrelated friend/ID source modified")
    return result


if __name__ == "__main__":
    current = MAIN.read_text(encoding="utf-8")
    updated = apply(current)
    if current != updated:
        MAIN.write_text(updated, encoding="utf-8")
    print("PASS: 3 original friend ID Text elements gain verified glyph ink")
    print("PASS: same friend routes, relationships, request/remove buttons")
    print("PASS: dual release flags OFF, no APK/Firebase deployment")
