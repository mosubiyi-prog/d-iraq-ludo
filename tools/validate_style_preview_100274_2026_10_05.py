from pathlib import Path

text = Path('lib/main.dart').read_text(encoding='utf-8')
required = [
    '// DEDA_STYLE_PREVIEW_100274',
    'int? _previewFrameIndex;',
    'int? _previewBadgeIndex;',
    'void _previewFrame(int index)',
    'void _previewBadge(int index)',
    'void _clearPreview()',
    'Widget _stylePreviewCard(',
    "dedaText('معاينة ملفك', 'Your profile preview')",
    "dedaText('اضغط للمعاينة', 'Tap to preview')",
    "dedaText('المعاينة مجانية ولا تخصم أي رصيد • الخصم فقط عند الضغط على زر الشراء'",
    "_miniBalanceChip('💎', _diamonds)",
    "_miniBalanceChip('🪙', progress.coins)",
    'onTap: () => _previewBadge(index)',
    'onTap: () => _previewFrame(index)',
]
missing = [item for item in required if item not in text]
if missing:
    raise SystemExit('DEDA 100274 validator missing: ' + ' | '.join(missing))

# The large legacy purchase-balance card may stay as an unused helper method,
# but it must not be rendered in the page body after 100274.
body_start = text.find('// DEDA_STYLE_PREVIEW_100274')
body_end = text.find('// DEDA_GIFTS_MAIN_UI_100271', body_start)
style_page = text[body_start:body_end]
render_anchor = 'body: Column('
if render_anchor not in style_page:
    raise SystemExit('DEDA 100274 sticky column body missing')
render_slice = style_page[style_page.find(render_anchor):style_page.find('  Widget _stylePreviewCard', style_page.find(render_anchor))]
if '_walletCard(progress, ratio, within)' in render_slice:
    raise SystemExit('DEDA 100274 still renders the oversized wallet card')
if '_stylePreviewCard(progress, inventory)' not in render_slice:
    raise SystemExit('DEDA 100274 fixed profile preview card not rendered')

print('DEDA 100274 validator passed: sticky profile preview + tap preview + compact balances')
