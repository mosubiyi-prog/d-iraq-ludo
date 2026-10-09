#!/usr/bin/env python3
"""Inject ONLY the gated social UI into the accepted 100319 task list in CI.

The golden nav build reconstructs main.dart; apply this exact small additive patch
AFTER that reconstruction. Never patch Firebase/reward logic or repository sources.
"""
from pathlib import Path

file = Path('lib/main.dart')
source = file.read_text(encoding='utf-8')
before = source
import_anchor = "import 'deda_backend.dart';"
assert source.count(import_anchor) == 1, 'Unsafe: golden import marker changed'
assert "import 'deda_social_task_preview.dart';" not in source
source = source.replace(import_anchor, import_anchor + "\nimport 'deda_social_task_preview.dart';", 1)

start = "                              return FutureBuilder<List<bool>>(\n"
assert source.count(start) == 1, 'Unsafe: existing task builder changed'
assert source.count('final taskId = DedaTaskIds.weekly[index];') == 1
source = source.replace(
    start,
    "                              return Column(\n"
    "                                children: [\n"
    "                                  FutureBuilder<List<bool>>(\n",
    1,
)

end = (
    "                                },\n"
    "                              );\n"
    "                            },\n"
    "                          ),\n"
    "                        );\n"
    "                      },\n"
    "                    ),\n"
    "                    const SizedBox(height: 7),"
)
assert source.count(end) == 1, 'Unsafe: task list closing marker changed'
replacement = (
    "                                },\n"
    "                                  ),\n"
    "                                  if (index == 5 && DedaSocialTaskPreview.visible)\n"
    "                                    Padding(\n"
    "                                      padding: const EdgeInsets.only(top: 6, bottom: 6),\n"
    "                                      child: DedaSocialTaskCompactCard(\n"
    "                                        isArabic: DedaLanguageState.isArabic,\n"
    "                                        onTap: () => Navigator.push(\n"
    "                                          context,\n"
    "                                          MaterialPageRoute<void>(\n"
    "                                            builder: (_) => DedaSocialTaskUserPreviewPage(\n"
    "                                              isArabic: DedaLanguageState.isArabic,\n"
    "                                            ),\n"
    "                                          ),\n"
    "                                        ),\n"
    "                                      ),\n"
    "                                    ),\n"
    "                                ],\n"
    "                              );\n"
    "                            },\n"
    "                          ),\n"
    "                        );\n"
    "                      },\n"
    "                    ),\n"
    "                    const SizedBox(height: 7),"
)
source = source.replace(end, replacement, 1)
assert source != before
assert source.count("DedaSocialTaskCompactCard(") == 1
assert source.count("if (index == 5 && DedaSocialTaskPreview.visible)") == 1
assert source.count("final taskId = DedaTaskIds.weekly[index];") == 1
assert "DedaTaskEngine.claimTaskReward(taskId)" in source
file.write_text(source, encoding='utf-8')
print('SOCIAL_CARD_AFTER_REVIEW_ONLY: golden tasks unchanged; UI preview is gated')
