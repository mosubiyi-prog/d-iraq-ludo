from pathlib import Path

path = Path('.github/workflows/build.yml')
text = path.read_text(encoding='utf-8')
branch_line = '      - next-points-map-profile-2026-09-30\n'
if branch_line in text:
    print('Build workflow already includes next-points-map-profile-2026-09-30.')
    raise SystemExit(0)

marker = '      - task-engine-points-2026-09-29\n'
if marker not in text:
    raise SystemExit('Could not find task-engine branch marker in build.yml')
text = text.replace(marker, marker + branch_line, 1)
path.write_text(text, encoding='utf-8')
print('Enabled APK/AAB build for next-points-map-profile-2026-09-30.')
