#!/usr/bin/env python3
"""Stage48: wire server-verified ACTIVE ID + immutable ink into real profile.

Run ONLY after exact signed-100359 source reconstruction (stages14–17), then
the Stage35/38/39/42 source-only shop patches. Changes solely the approved
profile hero ID slot and one import. No Firebase deploy, APK, wallet or grant.
Both client read/live flags remain OFF unless separately owner-authorized.
"""
from pathlib import Path

MAIN = Path("lib/main.dart")
IMPORT = "import 'deda_stage48_verified_active_profile_ink.dart';\n"
MARKER = "// DEDA_OWNER19_STAGE48_PROFILE_ACTIVE_ID_FIXED_INK_NO_DEPLOY"
ORIGINAL = """                    DedaPoint14VerifiedProfileSlot(
                      identifier: id,
                      onCopy: _copyDedaId,
                      width: (width - (compact ? 34.0 : 44.0)).clamp(0.0, 320.0).toDouble(),
                      compact: compact,
                    ),
"""
REPLACEMENT = """                    // DEDA_OWNER19_STAGE48_PROFILE_ACTIVE_ID_FIXED_INK_NO_DEPLOY
                    DedaStage48ActiveInkProfileSlot(
                      originalId: id,
                      width: (width - (compact ? 34.0 : 44.0)).clamp(0.0, 320.0).toDouble(),
                      compact: compact,
                      // The old slot (including its copy action and owned-card
                      // preference) is untouched until BOTH server gates
                      // are approved and a same-account read succeeds.
                      fallback: DedaPoint14VerifiedProfileSlot(
                        identifier: id,
                        onCopy: _copyDedaId,
                        width: (width - (compact ? 34.0 : 44.0)).clamp(0.0, 320.0).toDouble(),
                        compact: compact,
                      ),
                      // Preserve EXACT original crown/jewel/foil art. No
                      // second mock color-border widget is permitted.
                      premiumFoil: (verifiedId, lockedColor, copyVerifiedId) {
                        final originalFoil = DedaPremiumIdCardColor.values
                            .firstWhere((variant) => variant.name == lockedColor);
                        return DedaPremiumIdCard(
                          identifier: verifiedId,
                          color: originalFoil,
                          onTap: copyVerifiedId,
                          height: 50,
                        );
                      },
                    ),
"""


def apply(source: str) -> str:
    if MARKER in source:
        if (source.count(MARKER) != 1 or source.count(IMPORT) != 1 or
                REPLACEMENT not in source):
            raise ValueError("SAFE_STOP: partial Stage48 active ID profile")
        return source
    required = (
        "class DedaPoint14VerifiedProfileSlot extends StatefulWidget",
        "class DedaPremiumIdCard extends StatelessWidget",
        "enum DedaPremiumIdCardColor",
        "DEDA_STAGE17_STORE_CARDS_BLUE_OWNED_IDS_2026_10_19",
        "DEDA_100360_COMPACT_REAL_FOILS_MERGED_PRICE_AND_ACTION",
        "DEDA_100360_SERVER_VERIFIED_GROUP002_INSTEAD_OF_MOCK_CANDIDATES",
    )
    for token in required:
        if source.count(token) != 1:
            raise ValueError("SAFE_STOP: prior accepted stage missing/duplicate: " + token)
    if source.count(ORIGINAL) != 1 or source.count(IMPORT) != 0:
        raise ValueError("SAFE_STOP: exact original profile ID chip not found")
    mat = "import 'package:flutter/material.dart';\n"
    if source.count(mat) != 1:
        raise ValueError("SAFE_STOP: material import unexpectedly different")
    result = source.replace(ORIGINAL, REPLACEMENT, 1)
    result = result.replace(mat, mat + IMPORT, 1)
    if result.replace(REPLACEMENT, ORIGINAL, 1).replace(IMPORT, "", 1) != source:
        raise ValueError("SAFE_STOP: unrelated source would be changed")
    # The only place promoted to active ID is the account-authenticated hero.
    # The original 50px premium art, sign-in, wallet and share routes stay in place.
    return result


if __name__ == "__main__":
    before = MAIN.read_text(encoding="utf-8")
    after = apply(before)
    if after != before:
        MAIN.write_text(after, encoding="utf-8")
    print("PASS: actual 100359 profile now has verified active-ID read-only slot")
    print("PASS: fallback remains original; original four foils/copy retained")
    print("PASS: server/client switches OFF, no APK or Firebase deployment")
