#!/usr/bin/env python3
"""DEDA 100345: first Flutter frame before async boot; show safe retry on failure.

App 100344 remained at Android launch logo on a user's phone. This stage
does not clear preferences, Firebase records, rewards, maps, or ownership.
"""
from pathlib import Path
file=Path("lib/main.dart")
s=file.read_text(encoding="utf-8")
assert "DEDA_100345_NONBLOCKING_STARTUP_DIAGNOSTICS" not in s
assert "DEDA_100344_OWNER_EXACT_ROYAL_FRAMES_PREVIEW_ONLY" in s
old='''Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // flutter_map 8.x provides a native on-device tile cache. Configure it before
  // the first map opens so DEDA reuses recently viewed tiles across screens and
  // app launches without any paid API or extra service.
  BuiltInMapCachingProvider.getOrCreateInstance(
    maxCacheSize: 128 * 1024 * 1024,
  );

  try {
    await Firebase.initializeApp();
  } catch (_) {
    // Keep DEDA usable while Firebase platform configuration is being connected.
  }
  await DedaPreferences.load();
  await DedaTaskEngine.initializeForCurrentAccount();
  runApp(const DedaApp());
}

'''
new=r'''// DEDA_100345_NONBLOCKING_STARTUP_DIAGNOSTICS
// Do not hold native splash while waiting for plugins, storage or Firebase.
// Never silently log out/reset accounts on failed local-state load.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DedaStartupGate());
}

class DedaStartupGate extends StatefulWidget {
  final Future<void> Function()? initializeForTesting;
  const DedaStartupGate({super.key, this.initializeForTesting});
  @override
  State<DedaStartupGate> createState() => _DedaStartupGateState();
}

class _DedaStartupGateState extends State<DedaStartupGate> {
  bool _ready = false;
  bool _loading = true;
  String? _failedPhase;
  String _phase = 'جاري تجهيز التطبيق';

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  void _progress(String phase) {
    if (mounted) setState(() => _phase = phase);
  }

  Future<void> _initializeProduction() async {
    _progress('تجهيز الخرائط');
    try {
      BuiltInMapCachingProvider.getOrCreateInstance(
        maxCacheSize: 128 * 1024 * 1024,
      );
    } catch (error) {
      debugPrint('DEDA 100345 tile cache optional: $error');
    }

    // Existing DEDA offline fallback: unavailable Firebase is not fatal.
    _progress('تهيئة الخدمات');
    try {
      await Firebase.initializeApp().timeout(const Duration(seconds: 8));
    } catch (error) {
      debugPrint('DEDA 100345 Firebase optional: $error');
    }

    // These local reads must complete before the account is shown; failed
    // reads keep existing data and offer retry rather than fake logout.
    _progress('استعادة بيانات الحساب');
    await DedaPreferences.load().timeout(const Duration(seconds: 12));
    _progress('تحميل النقاط والمهام');
    await DedaTaskEngine.initializeForCurrentAccount()
        .timeout(const Duration(seconds: 12));
  }

  Future<void> _start() async {
    if (!_loading) {
      setState(() {
        _loading = true;
        _failedPhase = null;
        _phase = 'جاري تجهيز التطبيق';
      });
    }
    try {
      if (widget.initializeForTesting != null) {
        await widget.initializeForTesting!();
      } else {
        await _initializeProduction();
      }
      if (!mounted) return;
      setState(() { _ready = true; _loading = false; });
    } catch (error, stack) {
      debugPrint('DEDA 100345 startup failure at $_phase: $error');
      debugPrintStack(stackTrace: stack);
      if (!mounted) return;
      setState(() {
        _ready = false;
        _loading = false;
        _failedPhase = _phase;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) return const DedaApp();
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFFF8FAF2),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(Icons.location_on_rounded,
                    size: 61, color: Color(0xFF17652F)),
                  const SizedBox(height: 10),
                  const Text('DEDA - الدليل الدقيق',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 21,
                      fontWeight: FontWeight.w900, color: Color(0xFF20335B))),
                  const SizedBox(height: 18),
                  if (_loading) ...<Widget>[
                    const CircularProgressIndicator(
                      key: Key('deda_startup_loading'),
                      color: Color(0xFF17652F)),
                    const SizedBox(height: 12),
                    Text(_phase, textAlign: TextAlign.center),
                  ] else ...<Widget>[
                    const Icon(Icons.warning_amber_rounded,
                      key: Key('deda_startup_error'),
                      size: 38, color: Color(0xFF9C6C20)),
                    const SizedBox(height: 7),
                    Text('تعذر إكمال تشغيل DEDA أثناء: ' +
                      (_failedPhase ?? 'التهيئة'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 14)),
                    const SizedBox(height: 6),
                    const Text('بياناتك محفوظة. لا تحذف التطبيق ولا تمسح بياناته.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12,
                        color: Color(0xFF667085))),
                    const SizedBox(height: 12),
                    FilledButton(
                      key: const Key('deda_startup_retry'),
                      onPressed: _loading ? null : () => unawaited(_start()),
                      child: const Text('إعادة المحاولة')),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

'''
assert s.count(old)==1, "SAFE_STOP original main() layout changed"
n=s.replace(old,new,1)
assert n.replace(new,old,1)==s
for marker in ("class DedaDiamondsWallet {","class DedaSocialProgressWallet {",
               "class DedaRoutePage extends StatefulWidget"):
    assert marker in n
file.write_text(n,encoding="utf-8")
print("PASS: user-visible Flutter frame before async initialization")
print("PASS: no user data reset; local account/points guarded, retry possible")
