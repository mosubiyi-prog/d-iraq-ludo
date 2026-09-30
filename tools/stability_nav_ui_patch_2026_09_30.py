from pathlib import Path

path = Path('lib/main.dart')
text = path.read_text()

# 1) Clean opaque page transitions. MaterialPageRoute remains unchanged at call sites,
# but the old route is not visually blended/ghosted behind the new route.
app_marker = "class DedaApp extends StatelessWidget {\n"
transition_class = """class _DedaCleanPageTransitionsBuilder extends PageTransitionsBuilder {\n  const _DedaCleanPageTransitionsBuilder();\n\n  @override\n  Widget buildTransitions<T>(\n    PageRoute<T> route,\n    BuildContext context,\n    Animation<double> animation,\n    Animation<double> secondaryAnimation,\n    Widget child,\n  ) {\n    return child;\n  }\n}\n\n"""
if transition_class not in text:
    if app_marker not in text:
        raise SystemExit('DedaApp marker not found')
    text = text.replace(app_marker, transition_class + app_marker, 1)

old_theme = """            useMaterial3: true,\n          ),\n"""
new_theme = """            useMaterial3: true,\n            pageTransitionsTheme: const PageTransitionsTheme(\n              builders: <TargetPlatform, PageTransitionsBuilder>{\n                TargetPlatform.android: _DedaCleanPageTransitionsBuilder(),\n                TargetPlatform.iOS: _DedaCleanPageTransitionsBuilder(),\n                TargetPlatform.fuchsia: _DedaCleanPageTransitionsBuilder(),\n                TargetPlatform.linux: _DedaCleanPageTransitionsBuilder(),\n                TargetPlatform.macOS: _DedaCleanPageTransitionsBuilder(),\n                TargetPlatform.windows: _DedaCleanPageTransitionsBuilder(),\n              },\n            ),\n          ),\n"""
if new_theme not in text:
    if old_theme not in text:
        raise SystemExit('ThemeData marker not found')
    text = text.replace(old_theme, new_theme, 1)

# 2) Active navigation GPS cadence: restore the faster behavior and accept every fix.
old_location = """            accuracy: LocationAccuracy.best,\n            distanceFilter: 1,\n            intervalDuration: const Duration(milliseconds: 700),\n          )\n"""
new_location = """            accuracy: LocationAccuracy.best,\n            distanceFilter: 0,\n            intervalDuration: const Duration(milliseconds: 500),\n          )\n"""
if new_location not in text:
    if old_location not in text:
        raise SystemExit('Android navigation LocationSettings marker not found')
    text = text.replace(old_location, new_location, 1)

# 3) User gesture must pause automatic follow instead of immediately snapping back.
old_gesture = """                        onPositionChanged: (camera, hasGesture) {\n                          if (tripStarted &&\n                              hasGesture &&\n                              _autoFollowMap &&\n                              mounted) {\n                            setState(() => _autoFollowMap = true);\n                          }\n                        },\n"""
new_gesture = """                        onPositionChanged: (camera, hasGesture) {\n                          if (tripStarted &&\n                              hasGesture &&\n                              _autoFollowMap &&\n                              mounted) {\n                            // A deliberate map gesture temporarily pauses live\n                            // camera following. The existing recenter button is\n                            // then shown; pressing it resumes automatic follow.\n                            setState(() => _autoFollowMap = false);\n                          }\n                        },\n"""
if new_gesture not in text:
    if old_gesture not in text:
        raise SystemExit('navigation gesture marker not found')
    text = text.replace(old_gesture, new_gesture, 1)

path.write_text(text)

# Strict invariants for the combined build.
final = path.read_text()
checks = {
    'clean_transition_builder': 'class _DedaCleanPageTransitionsBuilder extends PageTransitionsBuilder',
    'clean_transition_theme': 'TargetPlatform.android: _DedaCleanPageTransitionsBuilder()',
    'gps_500ms': 'intervalDuration: const Duration(milliseconds: 500)',
    'gps_zero_filter': 'distanceFilter: 0',
    'gesture_pauses_follow': 'setState(() => _autoFollowMap = false);',
    'recenter_resumes_follow': 'setState(() {\n        _autoFollowMap = true;',
    'points_claim_text': 'استرد نقاطك 5,000 + 50',
    'opened_text': "dedaText('تم الفتح', 'Opened')",
}
missing = [name for name, marker in checks.items() if marker not in final]
if missing:
    raise SystemExit(f'missing stability invariants: {missing}')

# Do not allow the user-visible full-code-length disclosure to return.
if "'3 / 16'" in final:
    raise SystemExit('forbidden 3/16 disclosure is still present')

print('DEDA combined stability patch applied successfully')
