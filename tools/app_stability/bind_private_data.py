"""Wire existing private-data stores only; preserve all financial/auth code."""
from pathlib import Path
import json


def _region(source, first, last, replacements):
    start = source.index(first)
    end = source.index(last or '\nclass ', start + len(first))
    region = source[start:end]
    for old, new, count in replacements:
        if region.count(old) != count:
            raise ValueError('Exact private-data store anchor required')
        region = region.replace(old, new)
    return source[:start] + region + source[end:]


def bind_source(source):
    if 'DEDA_PRIVATE_ACCOUNT_DATA_BOUND_V1' in source:
        raise ValueError('private data already bound')
    source = _region(source, 'class DedaPlacesStore {', 'class DedaRegisteredPlacesStore {', [
        ('prefs.getStringList(key)', '(await DedaPrivateDataBridge.readList(prefs, key))', 1),
        ('prefs.setStringList(key, encoded)', 'DedaPrivateDataBridge.write(prefs, key, encoded)', 1),
    ])
    source = _region(source, 'class _PersonalPlacesPageState ', None, [
        ('prefs.getString(_placesKey)', '(await DedaPrivateDataBridge.readString(prefs, _placesKey))', 1),
        ('prefs.setString(\n      _placesKey,', 'DedaPrivateDataBridge.write(prefs,\n      _placesKey,', 1),
    ])
    source = _region(source, 'class _DedaContactPageState ', '\nclass AccountTypePage ', [
        ('prefs.getString(_draftKey)', '(await DedaPrivateDataBridge.readString(prefs, _draftKey))', 1),
        ('prefs.setString(\n        _draftKey,', 'DedaPrivateDataBridge.write(prefs,\n        _draftKey,', 1),
        ('prefs.remove(_draftKey)', 'DedaPrivateDataBridge.write(prefs, _draftKey, null)', 1),
    ])
    anchor = """            _sectionCard(
              icon: Icons.favorite_rounded,"""
    if source.count(anchor) != 1:
        raise ValueError('Exact profile favorite card required')
    source = source.replace(anchor, """            if (dedaPrivateDataEnabled)
              _sectionCard(
                icon: Icons.cloud_sync_outlined,
                iconColor: const Color(0xFF17652F),
                surfaceColor: const Color(0xFFF4FBF8),
                borderColor: const Color(0xFFD5EAE2),
                title: dedaText('بياناتي المحفوظة', 'My saved data'),
                subtitle: dedaText('حفظ واسترجاع الأماكن وسجل الاختبار', 'Save and restore places and quiz history'),
                onTap: () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => const DedaPrivateDataPage())),
              ),
""" + anchor, 1)
    return "// DEDA_PRIVATE_ACCOUNT_DATA_BOUND_V1\nimport 'deda_private_data_bridge.dart';\nimport 'deda_private_data_page.dart';\n" + source


def bind_quiz(source):
    if "import 'deda_private_data_bridge.dart';" in source:
        raise ValueError('private quiz already bound')
    replacements = [
        ('prefs.getBool(_completedKey)', '(await DedaPrivateDataBridge.readBool(prefs, _completedKey))', 1),
        ('prefs.getString(_progressKey)', '(await DedaPrivateDataBridge.readString(prefs, _progressKey))', 1),
        ('prefs.getStringList(_dailyIdsKey)', '(await DedaPrivateDataBridge.readList(prefs, _dailyIdsKey))', 1),
        ('prefs.getStringList(_seenKey)', '(await DedaPrivateDataBridge.readList(prefs, _seenKey))', 1),
        ('prefs.setStringList(_dailyIdsKey,', 'DedaPrivateDataBridge.write(prefs, _dailyIdsKey,', 1),
        ('prefs.setStringList(_seenKey,', 'DedaPrivateDataBridge.write(prefs, _seenKey,', 1),
        ('prefs.setString(\n      _progressKey,', 'DedaPrivateDataBridge.write(prefs,\n      _progressKey,', 1),
        ('prefs.setBool(_completedKey, true)', 'DedaPrivateDataBridge.write(prefs, _completedKey, true)', 1),
    ]
    for old, new, count in replacements:
        if source.count(old) != count:
            raise ValueError('Exact original quiz data anchor required')
        source = source.replace(old, new)
    return "import 'deda_private_data_bridge.dart';\n" + source


def bind(output):
    main = Path(output)/'lib/main.dart'
    quiz = Path(output)/'lib/traffic_quiz_page.dart'
    # Compute both first; source drift must not produce a half-bound app.
    main_text, quiz_text = bind_source(main.read_text()), bind_quiz(quiz.read_text())
    main.write_text(main_text)
    quiz.write_text(quiz_text)
    report_path = Path(output)/'section-bindings.json'
    report = json.loads(report_path.read_text())
    report['deda_private_data_page.dart'] = [{'state': '_DedaPrivateDataPageState', 'binding': 'section-lifetime'}]
    for name in ('deda_private_data_sync.dart', 'deda_private_data_bridge.dart'):
        report[name] = []
    report_path.write_text(json.dumps(report, indent=2)+'\n')
