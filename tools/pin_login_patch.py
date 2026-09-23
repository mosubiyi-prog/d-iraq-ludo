from pathlib import Path

main_path = Path("lib/main.dart")
text = main_path.read_text()


def replace_once(source: str, target: str, description: str) -> None:
    global text
    count = text.count(source)
    if count != 1:
        raise SystemExit(f"{description}: expected exactly one match, found {count}")
    text = text.replace(source, target, 1)


replace_once(
    "import 'package:firebase_core/firebase_core.dart';\n",
    "import 'package:firebase_core/firebase_core.dart';\n"
    "import 'package:firebase_auth/firebase_auth.dart';\n",
    "firebase auth import",
)
replace_once(
    "import 'deda_backend.dart';\n",
    "import 'deda_backend.dart';\nimport 'deda_pin_auth.dart';\n",
    "DEDA PIN auth import",
)

replace_once(
    """  static Future<void> logout() async {
    isLoggedIn = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_loggedInKey, false);
  }
""",
    """  static Future<void> logout() async {
    isLoggedIn = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_loggedInKey, false);
    try {
      await DedaPinAuth.signOutFirebase();
    } catch (_) {
      // Local logout must still complete if Firebase is temporarily unavailable.
    }
  }
""",
    "logout Firebase session",
)

replace_once(
    """class _LoginPageState extends State<LoginPage> {
  final nameController = TextEditingController();
  final phoneController = TextEditingController();
  DedaLanguage _language = DedaLanguageState.current;
""",
    """class _LoginPageState extends State<LoginPage> {
  final phoneController = TextEditingController();
  DedaLanguage _language = DedaLanguageState.current;
  bool _loginBusy = false;
""",
    "login state fields",
)

start = text.find("  Future<void> _completeVerifiedLogin(String normalizedPhone) async {")
end = text.find("  void _openContact() {", start)
if start < 0 or end < 0:
    raise SystemExit("login method section not found")
new_login = r"""  Future<void> login() async {
    if (_loginBusy) return;
    final normalizedPhone = _normalizeIraqiPhone(phoneController.text);
    if (normalizedPhone == null) {
      _showLoginMessage(
        'أدخل رقم هاتف عراقي صحيح مثل 07XXXXXXXXX',
        'Enter a valid Iraqi mobile number such as 07XXXXXXXXX',
      );
      return;
    }

    setState(() => _loginBusy = true);
    try {
      final exists = await DedaPinAuth.accountExists(normalizedPhone);
      if (!mounted) return;
      if (exists) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => DedaPinSignInPage(phone: normalizedPhone),
          ),
        );
      } else {
        final pin = DedaPinAuth.generatePin();
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => DedaPinCreatePage(
              phone: normalizedPhone,
              generatedPin: pin,
            ),
          ),
        );
      }
    } on FirebaseAuthException catch (error) {
      if (error.code == 'operation-not-allowed') {
        _showLoginMessage(
          'تعذر بدء جلسة DEDA. تأكد من تفعيل تسجيل الدخول المجهول في Firebase.',
          'Could not start the DEDA session. Ensure Anonymous sign-in is enabled in Firebase.',
        );
      } else {
        _showLoginMessage(
          'تعذر فحص الحساب الآن. تحقق من الإنترنت وحاول مجددًا.',
          'Could not check the account now. Check the internet and try again.',
        );
      }
    } catch (_) {
      _showLoginMessage(
        'تعذر فحص الحساب الآن. تحقق من الإنترنت وحاول مجددًا.',
        'Could not check the account now. Check the internet and try again.',
      );
    } finally {
      if (mounted) setState(() => _loginBusy = false);
    }
  }

"""
text = text[:start] + new_login + text[end:]

replace_once(
    """        builder: (_) => DedaContactPage(
          initialName: nameController.text.trim(),
          initialPhone: phoneController.text.trim(),
        ),
""",
    """        builder: (_) => DedaContactPage(
          initialName: '',
          initialPhone: phoneController.text.trim(),
        ),
""",
    "login contact initial name",
)
replace_once(
    """  void dispose() {
    nameController.dispose();
    phoneController.dispose();
    super.dispose();
  }
""",
    """  void dispose() {
    phoneController.dispose();
    super.dispose();
  }
""",
    "login dispose",
)

old_name_field = r"""                            TextField(
                              controller: nameController,
                              textDirection: DedaLanguageState.direction,
                              textAlign: DedaLanguageState.isArabic ? TextAlign.right : TextAlign.left,
                              decoration: _fieldDecoration(
                                hint: dedaText('الاسم الكامل', 'Full name'),
                                icon: Icons.person,
                              ),
                            ),
                            const SizedBox(height: 10),
"""
new_phone_intro = r"""                            Text(
                              dedaText(
                                'أدخل رقم هاتفك للمتابعة',
                                'Enter your phone number to continue',
                              ),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Color(0xFF173C27),
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 10),
"""
replace_once(old_name_field, new_phone_intro, "remove name from first login screen")
replace_once(
    "                                onPressed: login,\n",
    "                                onPressed: _loginBusy ? null : login,\n",
    "disable repeated login taps",
)

pages = r'''

DedaAccountType _dedaAccountTypeFromRaw(String value) {
  return value == 'placeOwner'
      ? DedaAccountType.placeOwner
      : DedaAccountType.user;
}

class DedaPinCreatePage extends StatefulWidget {
  final String phone;
  final String generatedPin;

  const DedaPinCreatePage({
    super.key,
    required this.phone,
    required this.generatedPin,
  });

  @override
  State<DedaPinCreatePage> createState() => _DedaPinCreatePageState();
}

class _DedaPinCreatePageState extends State<DedaPinCreatePage> {
  final _name = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _message(String ar, String en) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(dedaText(ar, en), textAlign: TextAlign.center)),
    );
  }

  Future<void> _create() async {
    if (_busy) return;
    final name = _name.text.trim();
    if (name.length < 2) {
      _message('أدخل الاسم الكامل أولاً.', 'Enter your full name first.');
      return;
    }

    setState(() => _busy = true);
    try {
      await DedaPinAuth.createAccount(
        phone: widget.phone,
        fullName: name,
        pin: widget.generatedPin,
      );
      await DedaPreferences.saveLogin(
        name: name,
        normalizedPhone: widget.phone,
        type: DedaAccountType.user,
      );
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => HomePage(userName: name)),
        (_) => false,
      );
    } on FirebaseAuthException catch (error) {
      if (error.code == 'operation-not-allowed') {
        _message(
          'تعذر بدء جلسة DEDA في Firebase.',
          'Could not start the DEDA session in Firebase.',
        );
      } else if (error.code == 'email-already-in-use') {
        _message(
          'هذا الرقم مسجل بالفعل. ارجع وسجل الدخول برمزك.',
          'This number is already registered. Go back and sign in with your code.',
        );
      } else {
        _message(
          'تعذر إنشاء الحساب الآن. حاول مرة أخرى.',
          'Could not create the account now. Try again.',
        );
      }
    } catch (error) {
      if (error.toString().contains('account-already-exists')) {
        _message(
          'هذا الرقم مسجل بالفعل. ارجع وسجل الدخول برمزك.',
          'This number is already registered. Go back and sign in with your code.',
        );
      } else {
        _message(
          'تعذر إنشاء الحساب الآن. تحقق من الإنترنت وحاول مجددًا.',
          'Could not create the account now. Check the internet and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF2),
      appBar: AppBar(title: Text(dedaText('إنشاء حساب DEDA', 'Create DEDA account'))),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.verified_user_outlined,
                      size: 68, color: Color(0xFF17652F)),
                  const SizedBox(height: 16),
                  Text(
                    dedaText(
                      'احفظ اسمك الكامل ورمز الدخول جيدًا. يمكنك أخذ لقطة شاشة لهذه الصفحة للاحتفاظ بهما.',
                      'Keep your full name and sign-in code safe. You can take a screenshot of this page.',
                    ),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _name,
                    textDirection: DedaLanguageState.direction,
                    decoration: InputDecoration(
                      labelText: dedaText('الاسم الكامل', 'Full name'),
                      prefixIcon: const Icon(Icons.person_outline),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFF8FB099), width: 1.4),
                    ),
                    child: Column(
                      children: [
                        Text(
                          dedaText('رمز الدخول الخاص بك', 'Your sign-in code'),
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 8),
                        SelectableText(
                          widget.generatedPin,
                          textDirection: TextDirection.ltr,
                          style: const TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 8,
                            color: Color(0xFF17652F),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: () async {
                            await Clipboard.setData(
                              ClipboardData(text: widget.generatedPin),
                            );
                            _message('تم نسخ الرمز.', 'Code copied.');
                          },
                          icon: const Icon(Icons.copy),
                          label: Text(dedaText('نسخ الرمز', 'Copy code')),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    dedaText(
                      'لن نرسل هذا الرمز برسالة SMS أو واتساب. هو مفتاح الدخول الخاص بحسابك في DEDA.',
                      'This code is not sent by SMS or WhatsApp. It is your DEDA account sign-in key.',
                    ),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFF53665A)),
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _busy ? null : _create,
                    icon: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.person_add_alt_1),
                    label: Text(dedaText('إنشاء الحساب والدخول', 'Create account and sign in')),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(56),
                      backgroundColor: const Color(0xFF17652F),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class DedaPinSignInPage extends StatefulWidget {
  final String phone;

  const DedaPinSignInPage({super.key, required this.phone});

  @override
  State<DedaPinSignInPage> createState() => _DedaPinSignInPageState();
}

class _DedaPinSignInPageState extends State<DedaPinSignInPage> {
  final _pin = TextEditingController();
  bool _busy = false;
  bool _hidePin = true;

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  void _message(String ar, String en) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(dedaText(ar, en), textAlign: TextAlign.center)),
    );
  }

  Future<void> _signIn() async {
    if (_busy) return;
    final pin = _pin.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(pin)) {
      _message('أدخل رمز الدخول المكوّن من 6 أرقام.', 'Enter the 6-digit sign-in code.');
      return;
    }

    final lock = await DedaPinAuth.remainingLocalLock(widget.phone);
    if (lock != null) {
      final minutes = lock.inMinutes + (lock.inSeconds % 60 == 0 ? 0 : 1);
      _message(
        'تم إيقاف المحاولات مؤقتًا. حاول بعد $minutes دقيقة.',
        'Attempts are temporarily locked. Try again in $minutes minute(s).',
      );
      return;
    }

    setState(() => _busy = true);
    try {
      final profile = await DedaPinAuth.signIn(phone: widget.phone, pin: pin);
      await DedaPinAuth.clearFailedAttempts(widget.phone);
      final name = (profile['name'] ?? '').toString().trim();
      final accountType = _dedaAccountTypeFromRaw(
        (profile['accountType'] ?? 'user').toString(),
      );
      if (name.isEmpty) throw StateError('missing-profile-name');
      await DedaPreferences.saveLogin(
        name: name,
        normalizedPhone: widget.phone,
        type: accountType,
      );
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => HomePage(userName: name)),
        (_) => false,
      );
    } on FirebaseAuthException catch (error) {
      if (error.code == 'wrong-password' ||
          error.code == 'invalid-credential' ||
          error.code == 'user-not-found') {
        await DedaPinAuth.recordFailedAttempt(widget.phone);
        _message('رمز الدخول غير صحيح.', 'The sign-in code is incorrect.');
      } else if (error.code == 'too-many-requests') {
        _message(
          'محاولات كثيرة. انتظر قليلًا ثم حاول مجددًا.',
          'Too many attempts. Wait a while and try again.',
        );
      } else {
        _message(
          'تعذر تسجيل الدخول الآن. تحقق من الإنترنت وحاول مجددًا.',
          'Could not sign in now. Check the internet and try again.',
        );
      }
    } catch (error) {
      if (error.toString().contains('invalid-pin')) {
        await DedaPinAuth.recordFailedAttempt(widget.phone);
        _message('رمز الدخول غير صحيح.', 'The sign-in code is incorrect.');
      } else {
        _message(
          'تعذر تسجيل الدخول الآن. تحقق من الإنترنت وحاول مجددًا.',
          'Could not sign in now. Check the internet and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF2),
      appBar: AppBar(title: Text(dedaText('تسجيل الدخول', 'Sign in'))),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(22),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.lock_person_outlined,
                      size: 70, color: Color(0xFF17652F)),
                  const SizedBox(height: 14),
                  Text(
                    widget.phone,
                    textAlign: TextAlign.center,
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _pin,
                    keyboardType: TextInputType.number,
                    obscureText: _hidePin,
                    textDirection: TextDirection.ltr,
                    textAlign: TextAlign.center,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(6),
                    ],
                    decoration: InputDecoration(
                      labelText: dedaText('رمز الدخول - 6 أرقام', '6-digit sign-in code'),
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        onPressed: () => setState(() => _hidePin = !_hidePin),
                        icon: Icon(_hidePin ? Icons.visibility : Icons.visibility_off),
                      ),
                    ),
                    onSubmitted: (_) => _signIn(),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _busy ? null : _signIn,
                    icon: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.login),
                    label: Text(dedaText('دخول', 'Sign in')),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(56),
                      backgroundColor: const Color(0xFF17652F),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: _busy
                        ? null
                        : () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => DedaPinRecoveryPage(phone: widget.phone),
                              ),
                            ),
                    icon: const Icon(Icons.lock_reset),
                    label: Text(dedaText('نسيت رمز الدخول', 'Forgot sign-in code')),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class DedaPinRecoveryPage extends StatefulWidget {
  final String phone;

  const DedaPinRecoveryPage({super.key, required this.phone});

  @override
  State<DedaPinRecoveryPage> createState() => _DedaPinRecoveryPageState();
}

class _DedaPinRecoveryPageState extends State<DedaPinRecoveryPage> {
  final _name = TextEditingController();
  bool _busy = false;
  String? _requestId;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _message(String ar, String en) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(dedaText(ar, en), textAlign: TextAlign.center)),
    );
  }

  Future<void> _submit() async {
    if (_busy) return;
    final name = _name.text.trim();
    if (name.length < 2) {
      _message('أدخل الاسم الكامل المسجل بالحساب.', 'Enter the full name on the account.');
      return;
    }
    setState(() => _busy = true);
    try {
      final id = await DedaPinAuth.requestRecovery(
        phone: widget.phone,
        fullName: name,
      );
      if (!mounted) return;
      setState(() => _requestId = id);
    } catch (_) {
      _message(
        'تعذر إرسال طلب الاسترجاع الآن.',
        'Could not send the recovery request now.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _enterWithNewPin(String pin) async {
    setState(() => _busy = true);
    try {
      final profile = await DedaPinAuth.signIn(phone: widget.phone, pin: pin);
      final name = (profile['name'] ?? '').toString().trim();
      final type = _dedaAccountTypeFromRaw(
        (profile['accountType'] ?? 'user').toString(),
      );
      if (name.isEmpty) throw StateError('missing-profile-name');
      await DedaPreferences.saveLogin(
        name: name,
        normalizedPhone: widget.phone,
        type: type,
      );
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => HomePage(userName: name)),
        (_) => false,
      );
    } catch (_) {
      _message(
        'تعذر الدخول بالرمز الجديد. حاول مرة أخرى.',
        'Could not sign in with the new code. Try again.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _waitingStatus(String status) {
    if (status == 'rejected') {
      return Text(
        dedaText(
          'تم رفض طلب الاسترجاع. تواصل مع إدارة DEDA إذا كنت صاحب الحساب.',
          'The recovery request was rejected. Contact DEDA administration if this is your account.',
        ),
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w700),
      );
    }
    if (status == 'error') {
      return Text(
        dedaText(
          'اعتمدت الإدارة الطلب لكن تعذر إصدار الرمز آليًا. ستراجع الإدارة الطلب.',
          'The request was approved but the new code could not be issued automatically. Administration will review it.',
        ),
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w700),
      );
    }
    return Column(
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 14),
        Text(
          dedaText(
            'تم إرسال الطلب إلى إدارة DEDA. سيظهر الرمز الجديد هنا بعد اعتماد الطلب.',
            'The request was sent to DEDA administration. Your new code will appear here after approval.',
          ),
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF2),
      appBar: AppBar(title: Text(dedaText('استرجاع رمز الدخول', 'Recover sign-in code'))),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(22),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: _requestId == null
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Icon(Icons.support_agent,
                            size: 68, color: Color(0xFF17652F)),
                        const SizedBox(height: 14),
                        Text(
                          dedaText(
                            'أدخل الاسم الكامل المسجل بالحساب. سيصل طلب إلى الإدارة للتحقق قبل إصدار رمز جديد.',
                            'Enter the full name on the account. Administration will verify the request before a new code is issued.',
                          ),
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          widget.phone,
                          textAlign: TextAlign.center,
                          textDirection: TextDirection.ltr,
                          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: _name,
                          decoration: InputDecoration(
                            labelText: dedaText('الاسم الكامل', 'Full name'),
                            prefixIcon: const Icon(Icons.person_outline),
                            border: const OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _busy ? null : _submit,
                          icon: const Icon(Icons.send_outlined),
                          label: Text(dedaText('إرسال طلب الاسترجاع', 'Send recovery request')),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(56),
                            backgroundColor: const Color(0xFF17652F),
                          ),
                        ),
                      ],
                    )
                  : StreamBuilder(
                      stream: DedaPinAuth.recoveryRequest(_requestId!),
                      builder: (context, snapshot) {
                        final data = snapshot.data?.data();
                        final status = (data?['status'] ?? 'new').toString();
                        if (status != 'ready') return _waitingStatus(status);

                        return FutureBuilder<String?>(
                          future: DedaPinAuth.readRecoveryPin(_requestId!),
                          builder: (context, pinSnapshot) {
                            final pin = pinSnapshot.data;
                            if (pinSnapshot.connectionState != ConnectionState.done) {
                              return const Center(child: CircularProgressIndicator());
                            }
                            if (pin == null) {
                              return Text(
                                dedaText(
                                  'تم إصدار رمز جديد لكن انتهت صلاحية عرضه. أرسل طلب استرجاع جديد.',
                                  'A new code was issued but its display window expired. Send a new recovery request.',
                                ),
                                textAlign: TextAlign.center,
                              );
                            }
                            return Column(
                              children: [
                                Text(
                                  dedaText(
                                    'تم اعتماد طلبك. احفظ رمز الدخول الجديد الآن.',
                                    'Your request was approved. Save your new sign-in code now.',
                                  ),
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(height: 16),
                                SelectableText(
                                  pin,
                                  textDirection: TextDirection.ltr,
                                  style: const TextStyle(
                                    fontSize: 38,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 8,
                                    color: Color(0xFF17652F),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                TextButton.icon(
                                  onPressed: () async {
                                    await Clipboard.setData(ClipboardData(text: pin));
                                    _message('تم نسخ الرمز الجديد.', 'New code copied.');
                                  },
                                  icon: const Icon(Icons.copy),
                                  label: Text(dedaText('نسخ الرمز', 'Copy code')),
                                ),
                                const SizedBox(height: 12),
                                FilledButton.icon(
                                  onPressed: _busy ? null : () => _enterWithNewPin(pin),
                                  icon: const Icon(Icons.login),
                                  label: Text(dedaText('الدخول بالرمز الجديد', 'Sign in with new code')),
                                  style: FilledButton.styleFrom(
                                    minimumSize: const Size.fromHeight(56),
                                    backgroundColor: const Color(0xFF17652F),
                                  ),
                                ),
                              ],
                            );
                          },
                        );
                      },
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
'''

marker = "\nclass _DedaCategoryPreviewStrip extends StatelessWidget {"
count = text.count(marker)
if count != 1:
    raise SystemExit(f"PIN pages insertion marker: expected one match, found {count}")
text = text.replace(marker, pages + marker, 1)
main_path.write_text(text)

# Build 111+ exposes recovery from the permission-aware admin dashboard.
# The legacy inbox-tab patch below is kept only for older branches.
if Path("lib/admin_team_pages.dart").exists():
    print("Applied DEDA PIN login/recovery; skipped legacy admin inbox tab patch.")
    raise SystemExit(0)

admin_path = Path("lib/admin_pages.dart")
admin = admin_path.read_text()


def admin_replace_once(source: str, target: str, description: str) -> None:
    global admin
    count = admin.count(source)
    if count != 1:
        raise SystemExit(f"{description}: expected exactly one match, found {count}")
    admin = admin.replace(source, target, 1)


admin_replace_once(
    "import 'deda_backend.dart';\n",
    "import 'deda_backend.dart';\nimport 'deda_recovery_admin.dart';\n",
    "recovery admin import",
)
admin_replace_once(
    "      length: 2,\n",
    "      length: 3,\n",
    "admin tab count",
)
admin_replace_once(
    """              Tab(text: t('الدعم', 'Support')),
              Tab(text: t('طلبات الأماكن', 'Places')),
""",
    """              Tab(text: t('الدعم', 'Support')),
              Tab(text: t('طلبات الأماكن', 'Places')),
              Tab(text: t('استرجاع الدخول', 'Recovery')),
""",
    "admin recovery tab",
)
admin_replace_once(
    """            _RequestList(
              isArabic: widget.isArabic,
              collection: 'place_requests',
              stream: DedaBackend.placeRequests(),
            ),
""",
    """            _RequestList(
              isArabic: widget.isArabic,
              collection: 'place_requests',
              stream: DedaBackend.placeRequests(),
            ),
            DedaRecoveryAdminList(isArabic: widget.isArabic),
""",
    "admin recovery view",
)
admin_path.write_text(admin)

print("Applied DEDA PIN login, recovery flow, and admin recovery queue.")
