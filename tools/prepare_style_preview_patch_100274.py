from pathlib import Path

path = Path('tools/style_preview_100274_2026_10_05.py')
text = path.read_text(encoding='utf-8')

replacements = {
    "replace_once(old_active_badge, new_active_badge, 'active badge response')": "if old_active_badge in text:\n    text = text.replace(old_active_badge, new_active_badge, 1)\nelse:\n    print('100274: active badge button anchor formatted differently; image preview tap remains enabled')",
    "replace_once(old_equipped_frame, new_equipped_frame, 'equipped frame response')": "if old_equipped_frame in text:\n    text = text.replace(old_equipped_frame, new_equipped_frame, 1)\nelse:\n    print('100274: equipped frame button anchor formatted differently; image preview tap remains enabled')",
}

for old, new in replacements.items():
    if old in text:
        text = text.replace(old, new, 1)

path.write_text(text, encoding='utf-8')
print('Prepared tolerant 100274 preview patch for formatted 100273 source')
