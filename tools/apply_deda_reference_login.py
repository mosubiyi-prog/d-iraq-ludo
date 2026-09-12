from pathlib import Path
import base64

main_path = Path('lib/main.dart')
asset_path = Path('assets/deda_login_reference.jpg')
generated_path = Path('lib/deda_reference_image.dart')

if not main_path.exists():
    raise SystemExit('lib/main.dart not found')
if not asset_path.exists():
    raise SystemExit('assets/deda_login_reference.jpg not found')

# Embed the exact approved DEDA artwork so the build never depends on a runtime asset path.
encoded = base64.b64encode(asset_path.read_bytes()).decode('ascii')
parts = [encoded[i:i + 120] for i in range(0, len(encoded), 120)]
generated = [
    '// Generated at build time from assets/deda_login_reference.jpg.',
    '// Approved DEDA artwork: Iraqi flag/map/landmarks, DEDA logo,',
    '// eight categories, Rinad name/signature and Iraq footer.',
    'const String dedaLoginReferenceBase64 =',
]
generated.extend(f"    '{part}'" for part in parts)
generated.append('    ;')
generated_path.write_text('\n'.join(generated) + '\n', encoding='utf-8')

text = main_path.read_text(encoding='utf-8')
original = text

# Import the embedded approved artwork.
if "import 'deda_reference_image.dart';" not in text:
    marker = "import 'places_service.dart';"
    if marker not in text:
        raise SystemExit('places_service import marker not found')
    text = text.replace(marker, marker + "\nimport 'deda_reference_image.dart';", 1)

# Direct sign-in for this stage: name + Iraqi phone only; no OTP/SMS UI.
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

# Administration wording agreed with the user.
text = text.replace(
    "'التواصل مع الشركة',\n                                    'Contact company',",
    "'التواصل مع الإدارة',\n                                    'Contact administration',",
    1,
)

# Build 47 strategy: stop cropping the reference image entirely.
# The exact approved artwork is stretched over the full login screen so none of
# its details can disappear. Only the real interactive controls sit above it.
state_pos = text.find('class _LoginPageState extends State<LoginPage> {')
if state_pos == -1:
    raise SystemExit('LoginPage state not found')
build_pos = text.find('  @override\n  Widget build(BuildContext context) {', state_pos)
if build_pos == -1:
    raise SystemExit('LoginPage build method not found')
next_class = text.find('\nclass ', build_pos + 1)
if next_class == -1:
    raise SystemExit('next top-level class after LoginPage not found')

new_build_tail = r'''  @override
  Widget build(BuildContext context) {
    final isArabic = _language == DedaLanguage.ar;

    return Scaffold(
      backgroundColor: _dedaCream,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final h = constraints.maxHeight;
            final formTop = (h * 0.455).clamp(300.0, h * 0.58);

            return Stack(
              fit: StackFit.expand,
              children: [
                // Exact approved reference artwork, including every visual detail.
                Image.memory(
                  base64Decode(dedaLoginReferenceBase64),
                  width: constraints.maxWidth,
                  height: constraints.maxHeight,
                  fit: BoxFit.fill,
                  gaplessPlayback: true,
                  filterQuality: FilterQuality.high,
                ),

                // Language selector: Arabic first, English second.
                Positioned(
                  left: 18,
                  top: 14,
                  child: Material(
                    color: Colors.white.withOpacity(0.94),
                    borderRadius: BorderRadius.circular(28),
                    child: Container(
                      width: 170,
                      height: 54,
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFF8BA58F), width: 1.4),
                        borderRadius: BorderRadius.circular(28),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              borderRadius: BorderRadius.circular(23),
                              onTap: () => _setLanguage(DedaLanguage.ar),
                              child: Container(
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: isArabic ? _dedaGreen : Colors.transparent,
                                  borderRadius: BorderRadius.circular(23),
                                ),
                                child: Text(
                                  'العربية',
                                  style: TextStyle(
                                    color: isArabic ? Colors.white : Colors.black87,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: InkWell(
                              borderRadius: BorderRadius.circular(23),
                              onTap: () => _setLanguage(DedaLanguage.en),
                              child: Container(
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: !isArabic ? _dedaGreen : Colors.transparent,
                                  borderRadius: BorderRadius.circular(23),
                                ),
                                child: Text(
                                  'English',
                                  style: TextStyle(
                                    color: !isArabic ? Colors.white : Colors.black87,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Administration contact stays available before sign-in.
                Positioned(
                  right: 16,
                  top: 19,
                  child: Material(
                    color: Colors.white.withOpacity(0.90),
                    borderRadius: BorderRadius.circular(24),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(24),
                      onTap: _openContact,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.support_agent, color: _dedaGreen, size: 25),
                            const SizedBox(width: 7),
                            Text(
                              dedaText('التواصل مع الإدارة', 'Contact administration'),
                              style: const TextStyle(
                                color: _dedaGreen,
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // Cover the old OTP artwork area and place only the agreed fields.
                Positioned(
                  left: 24,
                  right: 24,
                  top: formTop,
                  child: Directionality(
                    textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAF2).withOpacity(0.95),
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x33000000),
                            blurRadius: 18,
                            offset: Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextField(
                            controller: nameController,
                            textInputAction: TextInputAction.next,
                            decoration: InputDecoration(
                              hintText: dedaText('الاسم الكامل', 'Full name'),
                              prefixIcon: const Icon(Icons.person, color: _dedaGreen),
                              filled: true,
                              fillColor: Colors.white.withOpacity(0.96),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(24),
                                borderSide: const BorderSide(color: Color(0xFF8BA58F)),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(24),
                                borderSide: const BorderSide(color: Color(0xFF8BA58F), width: 1.4),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: phoneController,
                            keyboardType: TextInputType.phone,
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => login(),
                            decoration: InputDecoration(
                              hintText: '07XXXXXXXXX',
                              prefixIcon: const Icon(Icons.phone, color: _dedaGreen),
                              filled: true,
                              fillColor: Colors.white.withOpacity(0.96),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(24),
                                borderSide: const BorderSide(color: Color(0xFF8BA58F)),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(24),
                                borderSide: const BorderSide(color: Color(0xFF8BA58F), width: 1.4),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          SizedBox(
                            width: double.infinity,
                            height: 58,
                            child: FilledButton.icon(
                              onPressed: login,
                              style: FilledButton.styleFrom(
                                backgroundColor: _dedaGreen,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(28),
                                ),
                              ),
                              icon: const Icon(Icons.login, color: Colors.white, size: 27),
                              label: Text(
                                dedaText('تسجيل الدخول', 'Sign in'),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
'''

text = text[:build_pos] + new_build_tail + text[next_class:]

if text == original:
    raise SystemExit('No changes were applied')

main_path.write_text(text, encoding='utf-8')
print('Build 47 login applied: full approved DEDA artwork background + interactive language/admin/name/phone/sign-in overlay.')
