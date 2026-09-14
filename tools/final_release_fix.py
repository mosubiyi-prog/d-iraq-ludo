from pathlib import Path

path = Path("lib/main.dart")
text = path.read_text()


def replace_once(source: str, target: str, description: str) -> None:
    global text
    count = text.count(source)
    if count != 1:
        raise SystemExit(
            f"{description}: expected exactly one match, found {count}"
        )
    text = text.replace(source, target, 1)


old_phone = """                              ).copyWith(
                                prefixText: '+964  ',
                                prefixStyle: const TextStyle(
                                  color: Color(0xFF1F2D23),
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
"""
new_phone = """                              ).copyWith(
                                prefix: DedaLanguageState.isArabic
                                    ? null
                                    : const Directionality(
                                        textDirection: TextDirection.ltr,
                                        child: Text(
                                          '+964  ',
                                          style: TextStyle(
                                            color: Color(0xFF1F2D23),
                                            fontSize: 18,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                suffix: DedaLanguageState.isArabic
                                    ? const Directionality(
                                        textDirection: TextDirection.ltr,
                                        child: Text(
                                          '+964  ',
                                          style: TextStyle(
                                            color: Color(0xFF1F2D23),
                                            fontSize: 18,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      )
                                    : null,
                              ),
"""
replace_once(old_phone, new_phone, "DEDA phone prefix patch")

owner_start = text.find(
    "class _OwnerPlacePageState extends State<OwnerPlacePage> {"
)
owner_end = text.find("\nclass DedaPersonalPlace {", owner_start)
if owner_start < 0 or owner_end < 0:
    raise SystemExit("Owner place section was not found")
owner = text[owner_start:owner_end]


def owner_replace(source: str, target: str, description: str) -> None:
    global owner
    count = owner.count(source)
    if count != 1:
        raise SystemExit(
            f"{description}: expected exactly one owner match, found {count}"
        )
    owner = owner.replace(source, target, 1)


owner_replace(
    "  static const String _draftKey = 'deda_owner_place_draft_v1';\n",
    "  static const String _draftKey = 'deda_owner_place_draft_v1';\n"
    "  static const String _availabilityKey = 'deda_owner_availability_v1';\n",
    "owner availability key patch",
)

owner_replace(
    """      }
    } catch (_) {
      // Keep the form usable even if an old draft cannot be decoded.
    }

    for (final controller in [
""",
    """      }

      final savedAvailability = prefs.getBool(_availabilityKey);
      if (savedAvailability != null) {
        _isAvailableNow = savedAvailability;
      }
    } catch (_) {
      // Keep the form usable even if an old draft cannot be decoded.
    }

    for (final controller in [
""",
    "owner availability load patch",
)

owner_replace(
    """  Future<void> _saveDraft() async {
""",
    """  Future<void> _setAvailabilityNow(bool value) async {
    if (_isAvailableNow == value) return;
    setState(() => _isAvailableNow = value);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_availabilityKey, value);
    } catch (_) {
      // Keep the selection responsive even if local persistence fails.
    }
  }

  Future<void> _saveDraft() async {
""",
    "owner availability setter patch",
)

owner_replace(
    "onTap: () => setState(() => _isAvailableNow = true),",
    "onTap: () => _setAvailabilityNow(true),",
    "available-now tap patch",
)
owner_replace(
    "onTap: () => setState(() => _isAvailableNow = false),",
    "onTap: () => _setAvailabilityNow(false),",
    "not-available tap patch",
)

text = text[:owner_start] + owner + text[owner_end:]
path.write_text(text)
