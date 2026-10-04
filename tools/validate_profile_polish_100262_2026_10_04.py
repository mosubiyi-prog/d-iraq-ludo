from pathlib import Path

text = Path('lib/main.dart').read_text(encoding='utf-8')

required = [
    '// DEDA_PROFILE_POLISH_100262',
    'const int profileLevel = 1;',
    "'مستوى ذهبي • $profileLevel'",
    'Icons.star_rounded',
    'padding: const EdgeInsets.fromLTRB(12, 8, 12, 14)',
    'fit: BoxFit.scaleDown',
    'alignment: AlignmentDirectional.centerStart',
    'DedaDiamondsWallet.balanceNotifier',
    'DedaTaskEngine.totalPointsNotifier',
    'DedaPublicProfilePreviewPage()',
]
missing = [item for item in required if item not in text]
if missing:
    raise SystemExit('Missing 100262 profile polish markers: ' + ' | '.join(missing))

if text.count('// DEDA_PROFILE_POLISH_100262') != 1:
    raise SystemExit('100262 profile polish marker must appear exactly once')

# The large backdrop may remain as an unused method for rollback readability,
# but it must no longer be part of the visible ListView flow.
body_start = text.index('      body: ListView(', text.index('class _DedaProfilePhase2PageState'))
body_end = text.index('    );\n  }', body_start)
body = text[body_start:body_end]
if '_profileBackdrop(),' in body:
    raise SystemExit('Oversized top backdrop is still visible in the 100262 profile flow')

# The profile ID and feature titles must no longer use ellipsis in their
# dedicated 100262 blocks.
id_anchor = text.index('child: FittedBox(', text.index('final id = _dedaId'))
id_slice = text[id_anchor:id_anchor + 650]
if 'TextOverflow.ellipsis' in id_slice:
    raise SystemExit('DEDA ID still truncates with ellipsis')

feature_anchor = text.index('alignment: AlignmentDirectional.centerStart')
feature_slice = text[feature_anchor - 180:feature_anchor + 520]
if 'TextOverflow.ellipsis' in feature_slice:
    raise SystemExit('Feature title still truncates with ellipsis')

# Preserve the five social tabs from 100260.
for label in [
    "label: dedaText('ملفي', 'My profile')",
    "label: dedaText('أصدقائي', 'Friends')",
    "label: dedaText('الطلبات', 'Requests')",
    "label: dedaText('إضافة صديق', 'Add friend')",
    "label: dedaText('الزينة', 'Style')",
]:
    if label not in text:
        raise SystemExit('Social navigation regression: ' + label)

print('validated DEDA profile polish 100262')
