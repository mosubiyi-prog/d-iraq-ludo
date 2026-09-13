from pathlib import Path

path = Path("lib/main.dart")
text = path.read_text()
old = """                              ).copyWith(
                                prefixText: '+964  ',
                                prefixStyle: const TextStyle(
                                  color: Color(0xFF1F2D23),
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
"""
new = """                              ).copyWith(
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
if text.count(old) != 1:
    raise SystemExit("Expected DEDA phone prefix block was not found exactly once")
path.write_text(text.replace(old, new, 1))
