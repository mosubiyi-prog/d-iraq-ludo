"""Add visible, bounded-wait PIN first-use feedback to ACTUAL golden main.dart.

Runs AFTER the accepted 100327 navigation reconstruction, before the ONE
future integrated APK. Preserves app functionality and security completely.
Only the first login screen's button changes. No Firebase or wallet changes.
"""
from pathlib import Path
import re

path = Path("lib/main.dart")
src = path.read_text(encoding="utf-8")
marker = "// DEDA_NEXT_LOGIN_BUSY_INDICATOR_2026_10_10"

if marker in src:
    print("PASS: next-release first-login progress indicator already applied")
    raise SystemExit(0)

assert src.count("onPressed: _loginBusy ? null : login,") == 1, (
    "The reconstructed PIN login button changed unexpectedly; refuse patch"
)
pattern = re.compile(
    r"icon:\s*const Icon\(\s*Icons\.login,\s*size:\s*27,\s*\),\s*"
    r"label:\s*Text\(\s*dedaText\('تسجيل الدخول', 'Sign in'\),"
)
replacement = """// DEDA_NEXT_LOGIN_BUSY_INDICATOR_2026_10_10
                                  icon: _loginBusy
                                      ? const SizedBox(
                                          width: 22,
                                          height: 22,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Icon(Icons.login, size: 27),
                                  label: Text(
                                    _loginBusy
                                        ? dedaText('جاري التحقق...', 'Checking...')
                                        : dedaText('تسجيل الدخول', 'Sign in'),"""
new, count = pattern.subn(replacement, src)
assert count == 1, (
    f"Expected exactly one first-login label+icon; found {count}. "
    "No UI changed."
)
assert new.count(marker) == 1
path.write_text(new, encoding="utf-8")
print(
    "PASS: first-install login now displays a visible spinner and "
    "'Checking...' until bound Firebase/Firestore lookup resolves."
)
