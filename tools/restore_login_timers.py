from pathlib import Path

path = Path("lib/main.dart")
text = path.read_text(encoding="utf-8")


def replace_once(old: str, new: str, label: str) -> None:
    global text
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly 1 match, found {count}")
    text = text.replace(old, new, 1)


replace_once(
    "enum DedaAccountType { user, placeOwner }\n",
    "enum DedaAccountType { user, placeOwner }\n\nenum DedaOtpChannel { whatsapp, sms }\n",
    "otp channel enum",
)

replace_once(
    """  bool _sendingCode = false;\n  bool _verifyingCode = false;\n  bool _phoneVerified = false;\n""",
    """  bool _sendingCode = false;\n  bool _verifyingCode = false;\n  bool _phoneVerified = false;\n  Timer? _resendCountdownTimer;\n  Timer? _verificationCountdownTimer;\n  int _resendSeconds = 0;\n  int _verificationSeconds = 0;\n  DedaOtpChannel _otpChannel = DedaOtpChannel.whatsapp;\n""",
    "login timer and otp fields",
)

replace_once(
    """  @override\n  void dispose() {\n    nameController.dispose();\n    verificationController.dispose();\n    phoneController.dispose();\n    super.dispose();\n  }\n""",
    """  @override\n  void dispose() {\n    _resendCountdownTimer?.cancel();\n    _verificationCountdownTimer?.cancel();\n    nameController.dispose();\n    verificationController.dispose();\n    phoneController.dispose();\n    super.dispose();\n  }\n""",
    "login dispose",
)

replace_once(
    """  Future<void> _sendVerificationCode() async {\n    if (_sendingCode) return;\n""",
    """  void _startResendCountdown() {\n    _resendCountdownTimer?.cancel();\n    if (!mounted) return;\n\n    setState(() => _resendSeconds = 90);\n    _resendCountdownTimer = Timer.periodic(\n      const Duration(seconds: 1),\n      (timer) {\n        if (!mounted) {\n          timer.cancel();\n          return;\n        }\n        setState(() {\n          if (_resendSeconds > 0) _resendSeconds--;\n          if (_resendSeconds <= 0) timer.cancel();\n        });\n      },\n    );\n  }\n\n  void _startVerificationCountdown() {\n    _verificationCountdownTimer?.cancel();\n    if (!mounted) return;\n\n    setState(() => _verificationSeconds = 60);\n    _verificationCountdownTimer = Timer.periodic(\n      const Duration(seconds: 1),\n      (timer) {\n        if (!mounted) {\n          timer.cancel();\n          return;\n        }\n        setState(() {\n          if (_verificationSeconds > 0) _verificationSeconds--;\n          if (_verificationSeconds <= 0) timer.cancel();\n        });\n      },\n    );\n  }\n\n  void _selectOtpChannel(DedaOtpChannel channel) {\n    if (_otpChannel == channel) return;\n    _resendCountdownTimer?.cancel();\n    _verificationCountdownTimer?.cancel();\n    setState(() {\n      _otpChannel = channel;\n      _resendSeconds = 0;\n      _verificationSeconds = 0;\n      _verificationId = null;\n      _resendToken = null;\n      _verificationPhone = null;\n      _phoneVerified = false;\n      verificationController.clear();\n    });\n  }\n\n  Future<void> _sendSelectedVerificationCode() async {\n    if (_otpChannel == DedaOtpChannel.whatsapp) {\n      await _sendWhatsAppVerificationCode();\n      return;\n    }\n    await _sendVerificationCode();\n  }\n\n  Future<void> _sendWhatsAppVerificationCode() async {\n    final normalizedPhone = _normalizeIraqiPhone(phoneController.text);\n    if (normalizedPhone == null) {\n      _showLoginMessage(\n        'أدخل رقم هاتف عراقي صحيح مثل 07XXXXXXXXX',\n        'Enter a valid Iraqi mobile number such as 07XXXXXXXXX',\n      );\n      return;\n    }\n\n    _showLoginMessage(\n      'واتساب هو خيار الدخول الرئيسي الآن. الواجهة جاهزة، لكن إرسال الرمز الحقيقي سيبدأ بعد ربط مزود واتساب الرسمي الآمن.',\n      'WhatsApp is now the primary sign-in option. The interface is ready; real code delivery will start after the secure official WhatsApp provider is connected.',\n    );\n  }\n\n  Widget _otpChannelOption(\n    DedaOtpChannel channel,\n    String label,\n    IconData icon,\n  ) {\n    final selected = _otpChannel == channel;\n    return InkWell(\n      onTap: () => _selectOtpChannel(channel),\n      borderRadius: BorderRadius.circular(12),\n      child: AnimatedContainer(\n        duration: const Duration(milliseconds: 160),\n        height: 26,\n        padding: const EdgeInsets.symmetric(horizontal: 6),\n        decoration: BoxDecoration(\n          color: selected ? _dedaGreen : Colors.white,\n          borderRadius: BorderRadius.circular(12),\n          border: Border.all(\n            color: selected ? _dedaGreen : const Color(0xFF9CAF9F),\n          ),\n        ),\n        child: Row(\n          mainAxisAlignment: MainAxisAlignment.center,\n          children: [\n            Icon(\n              icon,\n              size: 14,\n              color: selected ? Colors.white : _dedaGreen,\n            ),\n            const SizedBox(width: 3),\n            Flexible(\n              child: Text(\n                label,\n                maxLines: 1,\n                overflow: TextOverflow.ellipsis,\n                style: TextStyle(\n                  fontSize: 10.5,\n                  fontWeight: FontWeight.w700,\n                  color: selected ? Colors.white : _dedaGreen,\n                ),\n              ),\n            ),\n          ],\n        ),\n      ),\n    );\n  }\n\n  Future<void> _sendVerificationCode() async {\n    if (_sendingCode || _resendSeconds > 0) return;\n""",
    "send verification entry and whatsapp otp scaffold",
)

replace_once(
    """    setState(() {\n      _sendingCode = true;\n      _phoneVerified = false;\n      _verificationPhone = normalizedPhone;\n      verificationController.clear();\n    });\n""",
    """    _startResendCountdown();\n    setState(() {\n      _sendingCode = true;\n      _phoneVerified = false;\n      _verificationPhone = normalizedPhone;\n      verificationController.clear();\n    });\n""",
    "start resend cooldown before Firebase SMS request",
)

replace_once(
    """            _resendToken = resendToken;\n            _sendingCode = false;\n          });\n          _showLoginMessage(\n""",
    """            _resendToken = resendToken;\n            _sendingCode = false;\n          });\n          _startVerificationCountdown();\n          _showLoginMessage(\n""",
    "code sent verification countdown start",
)

replace_once(
    """    if (_verificationId == null || _verificationPhone != normalizedPhone) {\n      await _sendVerificationCode();\n      return;\n    }\n""",
    """    if (_verificationId == null || _verificationPhone != normalizedPhone) {\n      await _sendSelectedVerificationCode();\n      return;\n    }\n""",
    "login uses selected otp channel",
)

replace_once(
    """                            Row(\n                              textDirection: TextDirection.ltr,\n                              children: [\n                                Expanded(\n                                  child: TextField(\n                                    controller: verificationController,\n""",
    """                            Row(\n                              textDirection: TextDirection.ltr,\n                              crossAxisAlignment: CrossAxisAlignment.center,\n                              children: [\n                                SizedBox(\n                                  width: 82,\n                                  child: Column(\n                                    children: [\n                                      _otpChannelOption(\n                                        DedaOtpChannel.whatsapp,\n                                        dedaText('واتساب', 'WhatsApp'),\n                                        Icons.chat_bubble_rounded,\n                                      ),\n                                      const SizedBox(height: 4),\n                                      _otpChannelOption(\n                                        DedaOtpChannel.sms,\n                                        'SMS',\n                                        Icons.sms_outlined,\n                                      ),\n                                    ],\n                                  ),\n                                ),\n                                const SizedBox(width: 8),\n                                Expanded(\n                                  child: TextField(\n                                    controller: verificationController,\n""",
    "otp selector beside verification field",
)

replace_once(
    """                                      if (value.length == 6 &&\n                                          _verificationId != null &&\n                                          !_verifyingCode) {\n""",
    """                                      if (_otpChannel == DedaOtpChannel.sms &&\n                                          value.length == 6 &&\n                                          _verificationId != null &&\n                                          !_verifyingCode) {\n""",
    "only auto verify firebase sms codes",
)

replace_once(
    """                                    onPressed: _sendingCode\n                                        ? null\n                                        : _sendVerificationCode,\n""",
    """                                    onPressed:\n                                        (_sendingCode ||\n                                                (_otpChannel == DedaOtpChannel.sms &&\n                                                    _resendSeconds > 0))\n                                            ? null\n                                            : _sendSelectedVerificationCode,\n""",
    "send button uses selected otp channel",
)

replace_once(
    """                                    label: Text(\n                                      dedaText('إرسال الرمز', 'Send code'),\n                                      textAlign: TextAlign.center,\n                                    ),\n""",
    """                                    label: Text(\n                                      _otpChannel == DedaOtpChannel.sms &&\n                                              _resendSeconds > 0\n                                          ? dedaText(\n                                              'إعادة الإرسال بعد $_resendSeconds ث',\n                                              'Resend in ${_resendSeconds}s',\n                                            )\n                                          : (_otpChannel == DedaOtpChannel.whatsapp\n                                              ? dedaText(\n                                                  'إرسال عبر واتساب',\n                                                  'Send via WhatsApp',\n                                                )\n                                              : dedaText(\n                                                  'إرسال عبر SMS',\n                                                  'Send via SMS',\n                                                )),\n                                      textAlign: TextAlign.center,\n                                    ),\n""",
    "send button label by otp channel",
)

replace_once(
    """                            Text(\n                              dedaText(\n                                'سيتم إرسال رمز التحقق إلى رقم هاتفك، وقد يتم التحقق تلقائياً على Android.',\n                                'A verification code will be sent to your phone; Android may verify it automatically.',\n                              ),\n                              textAlign: TextAlign.center,\n""",
    """                            Text(\n                              _verificationId != null && !_phoneVerified\n                                  ? (_verificationSeconds > 0\n                                      ? dedaText(\n                                          'تم إرسال الرمز. أمامك $_verificationSeconds ثانية لإدخاله يدوياً إذا لم يلتقطه الهاتف تلقائياً.',\n                                          'Code sent. You have $_verificationSeconds seconds to enter it manually if Android does not verify automatically.',\n                                        )\n                                      : dedaText(\n                                          'انتهى عداد 60 ثانية. يمكنك الاستمرار بإدخال الرمز يدوياً، وإعادة الإرسال تتاح بعد انتهاء عداد 90 ثانية.',\n                                          'The 60-second timer ended. You can still enter the code manually; resend becomes available after the 90-second timer ends.',\n                                        ))\n                                  : (_otpChannel == DedaOtpChannel.whatsapp\n                                      ? dedaText(\n                                          'واتساب هو خيار الدخول الرئيسي. سيصل رمز التحقق هنا بعد ربط خدمة واتساب الرسمية.',\n                                          'WhatsApp is the primary sign-in option. The verification code will arrive there after the official WhatsApp service is connected.',\n                                        )\n                                      : dedaText(\n                                          'سيتم إرسال رمز التحقق برسالة SMS إلى رقم هاتفك، وقد يتم التحقق تلقائياً على Android.',\n                                          'A verification code will be sent by SMS; Android may verify it automatically.',\n                                        )),\n                              textAlign: TextAlign.center,\n""",
    "verification helper text by otp channel",
)

replace_once(
    "_ => 'تعذر إرسال رمز التحقق. تحقق من الإنترنت وإعدادات Firebase ثم حاول مرة أخرى.',",
    "_ => 'تعذر إرسال رمز التحقق. رمز الخطأ: ${e.code}\\nالتفاصيل: ${e.message ?? 'لا توجد تفاصيل إضافية'}',",
    "Arabic Firebase error diagnostic",
)

replace_once(
    "_ => 'Could not send the verification code. Check internet and Firebase configuration, then try again.',",
    "_ => 'Could not send the verification code. Firebase error: ${e.code}\\nDetails: ${e.message ?? 'No additional details'}',",
    "English Firebase error diagnostic",
)

path.write_text(text, encoding="utf-8")
print("DEDA login timers, WhatsApp-first OTP UI, and Firebase diagnostics enabled")
