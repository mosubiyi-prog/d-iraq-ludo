#!/usr/bin/env python3
"""DEDA 100346 safe start: stop writing avatar migrations during startup.

After 100345 on-device diagnostics identified failure in local account restore,
prevent first-open migration writes and disclose sanitized failure type/phase.
These changes do NOT skip account loading and never clear local/remote data.
"""
from pathlib import Path
p=Path("lib/main.dart")
s=p.read_text(encoding="utf-8")
assert "DEDA_100345_NONBLOCKING_STARTUP_DIAGNOSTICS" in s
assert "DEDA_ROYAL_THREE_AVATARS_STEP1_2026_10_17" in s
assert "DEDA_100346_READ_ONLY_AVATAR_MIGRATION" not in s

def rep(old,new,where):
    global s
    hits=s.count(old)
    assert hits == 1, "SAFE_STOP "+where+" expected one, got "+str(hits)
    s=s.replace(old,new,1)

rep('''    if (oldChoice != null && safeChoice != oldChoice) {
      await prefs.setInt(key, safeChoice);
    }
    await prefs.setBool(migration, true);
    return safeChoice;''',
'''    // DEDA_100346_READ_ONLY_AVATAR_MIGRATION
    // No I/O here: on-device 100345 failed in account-state restoration.
    // Return mapped classic avatar in memory. When the user explicitly saves
    // appearance, setProfileAppearance() persists choice AND migration flag.
    return safeChoice;''',"profile migration at cold-start")

rep('''  String? _failedPhase;
  String _phase = 'جاري تجهيز التطبيق';''',
'''  String? _failedPhase;
  String? _failedKind;
  String _phase = 'جاري تجهيز التطبيق';''',"error kind field")

rep('''    _progress('استعادة بيانات الحساب');
    await DedaPreferences.load().timeout(const Duration(seconds: 12));''',
'''    // Distinguish plugin storage-read issues from avatar migration and
    // account decode; never continue with pretend empty account state.
    _progress('فتح التخزين المحلي');
    await SharedPreferences.getInstance().timeout(const Duration(seconds: 10));
    _progress('استعادة بيانات الحساب');
    await DedaPreferences.load().timeout(const Duration(seconds: 12));''',"storage open vs preferences load")

rep('''        _failedPhase = null;
        _phase = 'جاري تجهيز التطبيق';''',
'''        _failedPhase = null;
        _failedKind = null;
        _phase = 'جاري تجهيز التطبيق';''',"error reset")

rep('''        _failedPhase = _phase;
      });
    }
  }''',
'''        _failedPhase = _phase;
        // Only the error class is shown, never phone, ID, prefs, or raw logs.
        _failedKind = error is TimeoutException
            ? 'انتهت مهلة الانتظار'
            : error is PlatformException
                ? 'تعذر التواصل مع تخزين الهاتف'
                : error is TypeError || error is FormatException
                    ? 'بيانات محلية بصيغة غير متوقعة'
                    : 'خطأ محلي أثناء تشغيل التطبيق';
      });
    }
  }''',"sanitized failure kinds")

rep('''                    const SizedBox(height: 6),
                    const Text('بياناتك محفوظة. لا تحذف التطبيق ولا تمسح بياناته.',
''',
'''                    const SizedBox(height: 6),
                    Text(_failedKind ?? 'تعذر إكمال التهيئة',
                      key: const Key('deda_startup_failure_kind'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12,
                        color: Color(0xFF986A20))),
                    const SizedBox(height: 6),
                    const Text('لم نحذف بياناتك. لا تحذف التطبيق ولا تمسح بياناته.',
''',"safe error type display")

for marker in ("class DedaDiamondsWallet {","class DedaSocialProgressWallet {",
               "class DedaRoutePage extends StatefulWidget",
               "DedaPreferences.setProfileAppearance("):
    assert marker in s, "SAFE_STOP protected feature absent "+marker
p.write_text(s,encoding="utf-8")
print("PASS 100346: never write shared prefs during legacy avatar read")
print("PASS 100346: distinguish storage-open / restore-account and error kind")
print("PASS 100346: real local account required; no reset, cloud mutation or logout")
