from pathlib import Path

path = Path("tools/final_release_fix.py")
text = path.read_text()

# Build 243+ source is dart-formatted before release. Teach the legacy release
# patch the formatted indentation of the same +964 field so its exact match
# remains safe without changing the phone-prefix behavior.
phone_start = text.find('old_phone = """')
phone_end = text.find('new_phone = """', phone_start)
if phone_start < 0 or phone_end < 0:
    raise SystemExit("final_release_fix phone markers not found")
formatted_old_phone = '''old_phone = """                                ).copyWith(
                                  prefixText: '+964  ',
                                  prefixStyle: const TextStyle(
                                    color: Color(0xFF1F2D23),
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
"""
'''
text = text[:phone_start] + formatted_old_phone + text[phone_end:]

start_marker = "owner_start = text.find("
end_marker = "# Keep the admin source stable in the repository and apply the release-only"
start = text.find(start_marker)
end = text.find(end_marker, start)

if start < 0 or end < 0:
    raise SystemExit("final_release_fix owner section markers not found")

replacement = """# The final owner-place flow already owns availability persistence and\n# server synchronization. Skip the obsolete release-only owner patch.\npath.write_text(text)\n\n# Build 111+ uses the first-class team/permissions system and central audit.\nif Path(\"lib/admin_team_pages.dart\").exists():\n    print(\"DEDA admin team system detected; skipped legacy admin-history patch.\")\n    raise SystemExit(0)\n\n"""

text = text[:start] + replacement + text[end:]
path.write_text(text)

# The PIN-login patch also has one exact UI anchor that dart format expands
# across three lines. Update only that anchor; all login behavior stays intact.
pin_path = Path("tools/pin_login_patch.py")
pin = pin_path.read_text()
pin_start = pin.find('old_name_field = r"""')
pin_end = pin.find('new_phone_intro = r"""', pin_start)
if pin_start < 0 or pin_end < 0:
    raise SystemExit("pin_login_patch name-field markers not found")
formatted_name_field = r'''old_name_field = r"""                              TextField(
                                controller: nameController,
                                textDirection: DedaLanguageState.direction,
                                textAlign: DedaLanguageState.isArabic
                                    ? TextAlign.right
                                    : TextAlign.left,
                                decoration: _fieldDecoration(
                                  hint: dedaText('الاسم الكامل', 'Full name'),
                                  icon: Icons.person,
                                ),
                              ),
                              const SizedBox(height: 10),
"""
'''
pin = pin[:pin_start] + formatted_name_field + pin[pin_end:]
pin_path.write_text(pin)

print("Prepared final release and PIN patches for formatted final DEDA source.")
