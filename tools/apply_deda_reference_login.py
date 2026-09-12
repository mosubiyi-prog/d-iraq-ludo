from pathlib import Path
import base64

main_path = Path('lib/main.dart')
generated_path = Path('lib/deda_reference_image.dart')
part_paths = [
    Path('assets/deda_ref_part00.txt'),
    Path('assets/deda_ref_part01.txt'),
    Path('assets/deda_ref_part02.txt'),
    Path('assets/deda_ref_part03.txt'),
]

if not main_path.exists():
    raise SystemExit('lib/main.dart not found')
for part in part_paths:
    if not part.exists():
        raise SystemExit(f'missing approved artwork part: {part}')

encoded = ''.join(part.read_text(encoding='utf-8').strip() for part in part_paths)
raw = base64.b64decode(encoded, validate=True)
if not (raw.startswith(b'\xff\xd8') and raw.endswith(b'\xff\xd9')):
    raise SystemExit('approved artwork is not a valid JPEG stream')

parts = [encoded[i:i + 120] for i in range(0, len(encoded), 120)]
generated = [
    '// Generated from the exact DEDA reference confirmed by the user.',
    '// Contains: Iraq flag/map/landmarks, DEDA logo, eight categories,',
    '// Rinad name/signature, Iraq footer and the approved scenic artwork.',
    'const String dedaLoginReferenceBase64 =',
]
generated.extend(f"    '{part}'" for part in parts)
generated.append('    ;')
generated_path.write_text('\n'.join(generated) + '\n', encoding='utf-8')

text = main_path.read_text(encoding='utf-8')
original = text

if "import 'deda_reference_image.dart';" not in text:
    marker = "import 'places_service.dart';"
    if marker not in text:
        raise SystemExit('places_service import marker not found')
    text = text.replace(marker, marker + "\nimport 'deda_reference_image.dart';", 1)

login_start = text.find('  Future<void> login() async {')
login_end = text.find('  void _openContact() {', login_start)
if login_start == -1 or login_end == -1:
    raise SystemExit('login function boundaries not found')

new_login = '''  Future<void> login() async {
    final normalizedPhone = _normalizeIraqiPhone(phoneController.text);
    if (nameController.text.trim().isEmpty) {
      _showLoginMessage(
        'أدخل الاسم الكامل',
        'Enter your full name',
      );
      return;
    }
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

text = text.replace(
    "'التواصل مع الشركة',\n                                    'Contact company',",
    "'التواصل مع الإدارة',\n                                    'Contact administration',",
    1,
)

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

    Widget loginField({
      required TextEditingController controller,
      required String hint,
      required IconData icon,
      TextInputType? keyboardType,
      TextInputAction? textInputAction,
      ValueChanged<String>? onSubmitted,
      String? prefixText,
    }) {
      return SizedBox(
        height: 44,
        child: TextField(
          controller: controller,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          onSubmitted: onSubmitted,
          style: const TextStyle(
            fontSize: 14,
            color: Color(0xFF2C2C2C),
            fontWeight: FontWeight.w600,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(
              color: Color(0xFF777777),
              fontSize: 13,
            ),
            prefixText: prefixText,
            prefixStyle: const TextStyle(
              color: Color(0xFF333333),
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
            prefixIcon: Icon(icon, color: _dedaGreen, size: 20),
            filled: true,
            fillColor: Colors.white.withOpacity(0.97),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFF95A99A), width: 1.0),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFF95A99A), width: 1.0),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: _dedaGreen, width: 1.6),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: _dedaCream,
      body: SafeArea(
        child: Center(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return FittedBox(
                fit: BoxFit.contain,
                alignment: Alignment.center,
                child: SizedBox(
                  width: 512,
                  height: 768,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: Image.memory(
                          base64Decode(dedaLoginReferenceBase64),
                          fit: BoxFit.fill,
                          gaplessPlayback: true,
                          filterQuality: FilterQuality.high,
                          errorBuilder: (context, error, stackTrace) {
                            return const ColoredBox(
                              color: Color(0xFFF8FAF2),
                              child: Center(
                                child: Text(
                                  'DEDA',
                                  style: TextStyle(
                                    fontSize: 42,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFF17652F),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      Positioned(
                        left: 12,
                        top: 28,
                        width: 112,
                        height: 34,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.95),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: const Color(0xFF8FA695),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(16),
                                  onTap: () => _setLanguage(DedaLanguage.ar),
                                  child: Container(
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: isArabic
                                          ? _dedaGreen
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: Text(
                                      'العربية',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: isArabic
                                            ? Colors.white
                                            : Colors.black87,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(16),
                                  onTap: () => _setLanguage(DedaLanguage.en),
                                  child: Container(
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: !isArabic
                                          ? _dedaGreen
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: Text(
                                      'English',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: !isArabic
                                            ? Colors.white
                                            : Colors.black87,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        right: 12,
                        top: 26,
                        width: 176,
                        height: 38,
                        child: Material(
                          color: Colors.white.withOpacity(0.92),
                          borderRadius: BorderRadius.circular(19),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(19),
                            onTap: _openContact,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(
                                    Icons.support_agent,
                                    color: _dedaGreen,
                                    size: 19,
                                  ),
                                  const SizedBox(width: 5),
                                  Flexible(
                                    child: Text(
                                      dedaText(
                                        'التواصل مع الإدارة',
                                        'Contact administration',
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: _dedaGreen,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 124,
                        top: 346,
                        width: 264,
                        height: 184,
                        child: Directionality(
                          textDirection:
                              isArabic ? TextDirection.rtl : TextDirection.ltr,
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAF2).withOpacity(0.96),
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x26000000),
                                  blurRadius: 10,
                                  offset: Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Column(
                              children: [
                                loginField(
                                  controller: nameController,
                                  hint: dedaText('الاسم الكامل', 'Full name'),
                                  icon: Icons.person,
                                  textInputAction: TextInputAction.next,
                                ),
                                const SizedBox(height: 8),
                                loginField(
                                  controller: phoneController,
                                  hint: '07XXXXXXXXX',
                                  icon: Icons.phone,
                                  keyboardType: TextInputType.phone,
                                  textInputAction: TextInputAction.done,
                                  onSubmitted: (_) => login(),
                                  prefixText: '+964  ',
                                ),
                                const SizedBox(height: 10),
                                SizedBox(
                                  width: double.infinity,
                                  height: 46,
                                  child: FilledButton.icon(
                                    onPressed: login,
                                    style: FilledButton.styleFrom(
                                      backgroundColor: _dedaGreen,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                    ),
                                    icon: const Icon(
                                      Icons.login,
                                      size: 22,
                                      color: Colors.white,
                                    ),
                                    label: Text(
                                      dedaText(
                                        'تسجيل الدخول',
                                        'Sign in',
                                      ),
                                      style: const TextStyle(
                                        fontSize: 18,
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
                  ),
                ),
              );
            },
          ),
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
print(
    'DEDA exact approved reference applied: all visual details preserved; '
    'OTP removed; name/phone/login plus language/admin controls are interactive.'
)
