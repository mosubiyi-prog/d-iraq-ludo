#!/usr/bin/env python3
"""Add the isolated social card below daily-login in accepted 100319 UI.

Run ONLY inside CI after the complete accepted navigation reconstruction.
No edits to daily task engine, reward logic, Firestore or user credentials.
"""
from pathlib import Path

file = Path("lib/main.dart")
src = file.read_text(encoding="utf-8")
anchor_import = "import 'deda_backend.dart';"
anchor_card = "_dailyLoginCard(),\n                    const SizedBox(height: 7),"
assert src.count(anchor_import) == 1, "Missing golden import"
assert src.count(anchor_card) == 1, "Missing golden daily login"
assert "DedaSocialTaskCompactCard(" not in src
assert src.count("final taskId = DedaTaskIds.weekly[index];") == 1
src = src.replace(
    anchor_import,
    anchor_import + "\nimport 'deda_social_task_preview.dart';",
    1,
)
src = src.replace(
    anchor_card,
    """_dailyLoginCard(),
                    if (DedaSocialTaskPreview.visible) ...[
                      const SizedBox(height: 6),
                      DedaSocialTaskCompactCard(
                        isArabic: DedaLanguageState.isArabic,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => DedaSocialTaskUserPreviewPage(
                              isArabic: DedaLanguageState.isArabic,
                              onDiamondsGranted: () async {
                                await DedaDiamondsWallet.load();
                              },
                            ),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 7),""",
    1,
)
assert src.count("DedaSocialTaskCompactCard(") == 1
assert src.index("DedaSocialTaskCompactCard(") < src.index(
    "final taskId = DedaTaskIds.weekly[index];"
)
assert src.count("final taskId = DedaTaskIds.weekly[index];") == 1
file.write_text(src, encoding="utf-8")
print("SOCIAL_GOLDEN_UI: compact card only after login; eight tasks untouched")
