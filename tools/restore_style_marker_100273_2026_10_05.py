from pathlib import Path

main = Path('lib/main.dart')
text = main.read_text(encoding='utf-8')
old_marker = '// DEDA_STYLE_PURCHASE_SEPARATION_100272'
new_marker = '// DEDA_STYLE_BADGES_FRAMES_100273'

if old_marker not in text:
    if new_marker not in text:
        raise SystemExit('100273 style marker missing; refusing to alter source')
    text = text.replace(new_marker, old_marker + '\n' + new_marker, 1)
    main.write_text(text, encoding='utf-8')
    print('Restored preserved DEDA 100272 marker after 100273 style replacement')
else:
    print('DEDA 100272 marker already preserved')
