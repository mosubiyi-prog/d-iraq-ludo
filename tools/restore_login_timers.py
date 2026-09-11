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
    """  bool _sendingCode = false;\n  bool _verifyingCode = false;\n  bool _phoneVerified = false;\n""",
    """  bool _sendingCode = false;\n  bool _verifyingCode = false;\n  bool _phoneVerified = false;\n  Timer? _resendCountdownTimer;\n  Timer? _verificationCountdownTimer;\n  int _resendSeconds = 0;\n  int _verificationSeconds = 0;\n""",
    "login timer fields",
)

replace_once(
    """  @override\n  void dispose() {\n    nameController.dispose();\n    verificationController.dispose();\n    phoneController.dispose();\n    super.dispose();\n  }\n""",
    """  @override\n  void dispose() {\n    _resendCountdownTimer?.cancel();\n    _verificationCountdownTimer?.cancel();\n    nameController.dispose();\n    verificationController.dispose();\n    phoneController.dispose();\n    super.dispose();\n  }\n""",
    "login dispose",
)

replace_once(
    """  Future<void> _sendVerificationCode() async {\n    if (_sendingCode) return;\n""",
    """  void _startVerificationCountdowns() {\n    _resendCountdownTimer?.cancel();\n    _verificationCountdownTimer?.cancel();\n    if (!mounted) return;\n\n    setState(() {\n      _resendSeconds = 90;\n      _verificationSeconds = 60;\n    });\n\n    _resendCountdownTimer = Timer.periodic(\n      const Duration(seconds: 1),\n      (timer) {\n        if (!mounted) {\n          timer.cancel();\n          return;\n        }\n        setState(() {\n          if (_resendSeconds > 0) _resendSeconds--;\n          if (_resendSeconds <= 0) timer.cancel();\n        });\n      },\n    );\n\n    _verificationCountdownTimer = Timer.periodic(\n      const Duration(seconds: 1),\n      (timer) {\n        if (!mounted) {\n          timer.cancel();\n          return;\n        }\n        setState(() {\n          if (_verificationSeconds > 0) _verificationSeconds--;\n          if (_verificationSeconds <= 0) timer.cancel();\n        });\n      },\n    );\n  }\n\n  Future<void> _sendVerificationCode() async {\n    if (_sendingCode || _resendSeconds > 0) return;\n""",
    "send verification entry",
)

replace_once(
    """            _resendToken = resendToken;\n            _sendingCode = false;\n          });\n          _showLoginMessage(\n""",
    """            _resendToken = resendToken;\n            _sendingCode = false;\n          });\n          _startVerificationCountdowns();\n          _showLoginMessage(\n""",
    "code sent countdown start",
)

replace_once(
    """                                    onPressed: _sendingCode\n                                        ? null\n                                        : _sendVerificationCode,\n""",
    """                                    onPressed:\n                                        (_sendingCode || _resendSeconds > 0)\n                                            ? null\n                                            : _sendVerificationCode,\n""",
    "send button guard",
)

replace_once(
    """                                    label: Text(\n                                      dedaText('إرسال الرمز', 'Send code'),\n                                      textAlign: TextAlign.center,\n                                    ),\n""",
    """                                    label: Text(\n                                      _resendSeconds > 0\n                                          ? dedaText(\n                                              'إعادة الإرسال بعد $_resendSeconds ث',\n                                              'Resend in ${_resendSeconds}s',\n                                            )\n                                          : dedaText(\n                                              'إرسال الرمز',\n                                              'Send code',\n                                            ),\n                                      textAlign: TextAlign.center,\n                                    ),\n""",
    "send button label",
)

replace_once(
    """                            Text(\n                              dedaText(\n                                'سيتم إرسال رمز التحقق إلى رقم هاتفك، وقد يتم التحقق تلقائياً على Android.',\n                                'A verification code will be sent to your phone; Android may verify it automatically.',\n                              ),\n                              textAlign: TextAlign.center,\n""",
    """                            Text(\n                              _verificationId != null && !_phoneVerified\n                                  ? (_verificationSeconds > 0\n                                      ? dedaText(\n                                          'تم إرسال الرمز. أمامك $_verificationSeconds ثانية لإدخاله يدوياً إذا لم يلتقطه الهاتف تلقائياً.',\n                                          'Code sent. You have $_verificationSeconds seconds to enter it manually if Android does not verify automatically.',\n                                        )\n                                      : dedaText(\n                                          'انتهى عداد 60 ثانية. يمكنك الاستمرار بإدخال الرمز يدوياً، وإعادة الإرسال تتاح بعد انتهاء عداد 90 ثانية.',\n                                          'The 60-second timer ended. You can still enter the code manually; resend becomes available after the 90-second timer ends.',\n                                        ))\n                                  : dedaText(\n                                      'سيتم إرسال رمز التحقق إلى رقم هاتفك، وقد يتم التحقق تلقائياً على Android.',\n                                      'A verification code will be sent to your phone; Android may verify it automatically.',\n                                    ),\n                              textAlign: TextAlign.center,\n""",
    "verification helper text",
)

path.write_text(text, encoding="utf-8")
print("DEDA login timers restored: resend=90s, verification/auto-detect=60s")
