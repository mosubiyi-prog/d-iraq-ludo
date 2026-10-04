from pathlib import Path

path = Path('lib/deda_social_service.dart')
text = path.read_text(encoding='utf-8')
marker = '// DEDA_SOCIAL_SERVICE_TYPES_100269'
if marker in text:
    print('DEDA social service type fix already applied')
    raise SystemExit(0)

count_style = text.count('.clamp(0, 5)')
count_level = text.count('.clamp(1, 999)')
if count_style < 6:
    raise SystemExit(f'expected at least six style clamps, found {count_style}')
if count_level < 2:
    raise SystemExit(f'expected at least two level clamps, found {count_level}')

text = text.replace('.clamp(0, 5)', '.clamp(0, 5).toInt()')
text = text.replace('.clamp(1, 999)', '.clamp(1, 999).toInt()')
text = marker + '\n' + text
path.write_text(text, encoding='utf-8')
print('applied DEDA social service integer type fix 100269')
