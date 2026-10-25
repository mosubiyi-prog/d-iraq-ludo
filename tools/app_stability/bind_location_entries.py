"""Bound GPS acquisition for the eight original foreground section callsites.

Uses the plugin's request cancellation, not an outer Future.timeout which
would leave Android's location request running. Does not time out permission
dialogs, change accuracy, invent coordinates or alter navigation streams.
"""
import re


def once(source, before, after):
    if source.count(before) != 1:
        raise ValueError('Location section source anchor changed')
    return source.replace(before, after, 1)


def bind(source):
    # Include both original layouts, but refuse an omitted or modified callsite.
    pattern = re.compile(
        r'(Geolocator\.getCurrentPosition\(\s*locationSettings:\s*'
        r'const LocationSettings\(\s*accuracy: LocationAccuracy.high)'
        r'(,?\s*\))'
    )
    if source.count('Geolocator.getCurrentPosition(') != 8:
        raise ValueError('Unexpected location acquisition callsite count')
    source, count = pattern.subn(
        lambda m: m[1] + ', timeLimit: Duration(seconds: 12)' + m[2], source)
    if count != 8:
        raise ValueError('Location settings changed or already bound')
    # Keep details' original fallback coordinates, but cancellation now happens
    # inside the plugin instead of abandoning a still-live native request.
    source = once(source, ').timeout(const Duration(seconds: 12));\n    } catch (_) {\n      // If a fresh GPS fix',
                  ');\n    } catch (_) {\n      // If a fresh GPS fix')
    start = source.index('  Future<void> _captureCurrentLocation() async {')
    end = source.index('\n  Future<void> _setAvailability(', start)
    body = source[start:end]
    body = once(body, '    } finally {', '''    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(dedaText(
          'تعذر تحديد موقعك الآن. تأكد من GPS ثم أعد المحاولة.',
          'Could not determine your location. Check GPS and try again.',
        )),
      ));
    } finally {''')
    source = source[:start] + body + source[end:]
    # A page left during GPS acquisition must not begin a subsequent remote read.
    start = source.index('class _DedaPlaceSearchPageState ')
    end = source.index('class PlaceDetailsPage ', start)
    body = source[start:end]
    body = once(body, '      if (position == null) return;',
                '      if (!mounted || position == null) return;')
    body = once(body, '      final registered = await DedaRegisteredPlacesStore.readAll();',
                '      final registered = await DedaRegisteredPlacesStore.readAll();\n      if (!mounted) return;')
    body = once(body, '    } catch (_) {\n      if (!mounted) return;\n      setState(() {\n        _status = dedaText(',
                '''    } on TimeoutException {
      if (!mounted) return;
      setState(() => _status = dedaText(
        'تعذر تحديد موقعك خلال المهلة. تأكد من GPS ثم أعد البحث.',
        'Location timed out. Check GPS and search again.',
      ));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _status = dedaText(''')
    source = source[:start] + body + source[end:]
    # Free-map lookup already checked mounted before its read, but not after it.
    source = once(source, '      final dedaPlaces = await DedaRegisteredPlacesStore.readAll();\n      final destination = selectedDestination;',
                  '      final dedaPlaces = await DedaRegisteredPlacesStore.readAll();\n      if (!mounted) return;\n      final destination = selectedDestination;')
    return source
