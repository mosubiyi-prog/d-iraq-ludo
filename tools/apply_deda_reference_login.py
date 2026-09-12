from pathlib import Path
import base64

main_path = Path('lib/main.dart')
asset_path = Path('assets/deda_login_reference.jpg')
generated_path = Path('lib/deda_reference_image.dart')

if not main_path.exists():
    raise SystemExit('lib/main.dart not found')
if not asset_path.exists():
    raise SystemExit('assets/deda_login_reference.jpg not found')

# Generate a Dart constant from the approved DEDA reference artwork.
encoded = base64.b64encode(asset_path.read_bytes()).decode('ascii')
parts = [encoded[i:i + 120] for i in range(0, len(encoded), 120)]
generated = [
    '// Generated at build time from assets/deda_login_reference.jpg.',
    '// Approved DEDA login reference artwork: Iraqi landmarks, DEDA logo,',
    '// categories, Rinad name and signature.',
    'const String dedaLoginReferenceBase64 =',
]
generated.extend(f"    '{part}'" for part in parts)
generated.append('    ;')
generated_path.write_text('\n'.join(generated) + '\n', encoding='utf-8')

text = main_path.read_text(encoding='utf-8')
original = text

# Import the generated reference artwork constant.
if "import 'deda_reference_image.dart';" not in text:
    marker = "import 'places_service.dart';"
    if marker not in text:
        raise SystemExit('places_service import marker not found')
    text = text.replace(marker, marker + "\nimport 'deda_reference_image.dart';", 1)

# A proportional crop helper preserves the approved artwork exactly while
# keeping the real language/admin/login controls interactive. The Stack keeps
# the full source image laid out at its real scaled height before clipping;
# this avoids the blank crop produced by Transform under tight constraints.
if 'Widget _referenceCrop(double fromY, double toY)' not in text:
    marker = '  InputDecoration _fieldDecoration({'
    helper = r'''  Widget _referenceCrop(double fromY, double toY) {
    const sourceWidth = 512.0;
    const sourceHeight = 768.0;

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final scale = width / sourceWidth;
          final cropHeight = (toY - fromY) * scale;
          final imageHeight = sourceHeight * scale;

          return SizedBox(
            width: width,
            height: cropHeight,
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                Positioned(
                  left: 0,
                  top: -fromY * scale,
                  width: width,
                  height: imageHeight,
                  child: Image.memory(
                    base64Decode(dedaLoginReferenceBase64),
                    width: width,
                    height: imageHeight,
                    fit: BoxFit.fill,
                    alignment: Alignment.topCenter,
                    gaplessPlayback: true,
                    filterQuality: FilterQuality.high,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

'''
    if marker not in text:
        raise SystemExit('field decoration marker not found')
    text = text.replace(marker, helper + marker, 1)

# Approved scenic header: Iraqi flag/map/landmarks, DEDA logo and welcome text.
old_hero = '''                      ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: Image.memory(
                          base64Decode(_dedaHeroBase64),
                          width: double.infinity,
                          fit: BoxFit.fitWidth,
                          gaplessPlayback: true,
                        ),
                      ),'''
new_hero = '''                      _referenceCrop(58, 350),'''
if old_hero in text:
    text = text.replace(old_hero, new_hero, 1)
elif new_hero not in text:
    raise SystemExit('hero block marker not found')

# Remove the OTP field, SMS send button and SMS explanatory text. The approved
# form now has only full name + Iraqi phone + sign in.
name_marker = '                              controller: nameController,'
phone_marker = '''                            TextField(
                              controller: phoneController,'''
name_pos = text.find(name_marker)
if name_pos == -1:
    raise SystemExit('name field marker not found')
otp_start = text.find('                            const SizedBox(height: 10),', name_pos)
phone_pos = text.find(phone_marker, otp_start)
if otp_start == -1 or phone_pos == -1:
    raise SystemExit('OTP block boundaries not found')
text = text[:otp_start] + '                            const SizedBox(height: 10),\n' + text[phone_pos:]

# Direct sign-in: validate the Iraqi number, then save name + phone and open DEDA.
login_start = text.find('  Future<void> login() async {')
login_end = text.find('  void _openContact() {', login_start)
if login_start == -1 or login_end == -1:
    raise SystemExit('login function boundaries not found')
new_login = '''  Future<void> login() async {
    final normalizedPhone = _normalizeIraqiPhone(phoneController.text);
    if (normalizedPhone == null) {
      _showLoginMessage(
        'أدخل رقم هاتف عراقي صحيح مثل 07XXXXXXXXX',
        'Enter a valid Iraqi mobile number such as 07XXXXXXXXX',
      );
      return;
    }

    await _completeVerifiedLogin(normalizedPhone);
  }

'''
text = text[:login_start] + new_login + text[login_end:]

# Replace the generic lower preview with the exact lower section of the approved
# artwork: Iraq-wide slogan, eight category tiles, Rinad name/signature, and Iraq footer.
discover_idx = text.find("dedaText('اكتشف ما يحيط بك', 'Discover what is around you')")
if discover_idx == -1:
    raise SystemExit('discover heading marker not found')
bottom_start = text.rfind('                      const SizedBox(height: 14),', 0, discover_idx)
if bottom_start == -1:
    raise SystemExit('bottom preview start marker not found')
end_marker = '''                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          dedaText('بغداد', 'Baghdad'),
                          style: TextStyle(
                            color: Color(0xFF78967D),
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),'''
bottom_end_start = text.find(end_marker, discover_idx)
if bottom_end_start == -1:
    raise SystemExit('bottom preview end marker not found')
bottom_end = bottom_end_start + len(end_marker)
text = text[:bottom_start] + '''                      const SizedBox(height: 14),
                      _referenceCrop(530, 768),''' + text[bottom_end:]

# Administration contact wording; existing contact page retains the four agreed options.
text = text.replace(
    "'التواصل مع الشركة',\n                                    'Contact company',",
    "'التواصل مع الإدارة',\n                                    'Contact administration',",
    1,
)

if text == original:
    raise SystemExit('No changes were applied')

main_path.write_text(text, encoding='utf-8')
print('Applied approved DEDA reference login: exact artwork details + direct name/phone sign-in + administration contact.')
