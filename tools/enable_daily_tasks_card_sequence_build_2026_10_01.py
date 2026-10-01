from pathlib import Path

p = Path('.github/workflows/build.yml')
s = p.read_text(encoding='utf-8')

branch = '      - fix-daily-tasks-card-sequence-2026-10-01\n'
anchor = '      - points-stage1-code-2026-09-30\n'
if branch not in s:
    if s.count(anchor) != 1:
        raise SystemExit(f'branch anchor count={s.count(anchor)}')
    s = s.replace(anchor, anchor + branch, 1)

validation = """      - name: Validate DEDA daily tasks and card sequence in final source
        run: python3 tools/validate_daily_tasks_card_sequence_2026_10_01.py

"""
marker = '      - name: Build permanently signed APK and AAB\n'
if 'Validate DEDA daily tasks and card sequence in final source' not in s:
    if s.count(marker) != 1:
        raise SystemExit(f'build marker count={s.count(marker)}')
    s = s.replace(marker, validation + marker, 1)

p.write_text(s, encoding='utf-8')
print('enabled guarded APK build branch')
