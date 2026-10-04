from pathlib import Path

path = Path('lib/main.dart')
text = path.read_text(encoding='utf-8')
marker = '// DEDA_SETTINGS_LOGOUT_100270'
if marker in text:
    print('100270 settings logout already applied')
    raise SystemExit(0)

state_anchor = '''class _DedaSettingsPageState extends State<DedaSettingsPage> {
  bool _adminEntryVisible = false;
'''
state_new = '''class _DedaSettingsPageState extends State<DedaSettingsPage> {
  // DEDA_SETTINGS_LOGOUT_100270
  bool _adminEntryVisible = false;
'''
if text.count(state_anchor) != 1:
    raise SystemExit(f'settings state anchor count={text.count(state_anchor)}')
text = text.replace(state_anchor, state_new, 1)

method_anchor = '''  Widget _sectionTitle(String text) {
'''
method_code = r'''  Future<void> _logoutPersonalAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(dedaText('تسجيل الخروج', 'Sign out')),
        content: Text(
          dedaText(
            'هل تريد تسجيل الخروج؟ إغلاق التطبيق أو زر الرجوع لا يسجل خروجك.',
            'Do you want to sign out? Closing the app or pressing Back does not sign you out.',
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(dedaText('إلغاء', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFB3261E),
            ),
            child: Text(dedaText('تسجيل الخروج', 'Sign out')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    // Keep the proven personal-account logout behavior unchanged. This does
    // not sign out an unrelated administrative session as a side effect.
    await DedaPreferences.logout();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (_) => false,
    );
  }

'''
settings_start = text.index('class _DedaSettingsPageState')
settings_end = text.index('class OwnerPlacePage', settings_start)
settings_scope = text[settings_start:settings_end]
if settings_scope.count(method_anchor) != 1:
    raise SystemExit(f'settings method anchor count={settings_scope.count(method_anchor)}')
settings_scope = settings_scope.replace(method_anchor, method_code + method_anchor, 1)
text = text[:settings_start] + settings_scope + text[settings_end:]

ui_anchor = '''                  ],

                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class OwnerPlacePage'''
ui_new = '''                  ],

                  // Personal-account sign out stays in Settings. When the
                  // administration block is hidden this naturally occupies
                  // the same lower area; authorized accounts see it directly
                  // below Administration.
                  const SizedBox(height: 12),
                  Card(
                    color: const Color(0xFFFFF7F6),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                      side: const BorderSide(color: Color(0xFFE8B9B4)),
                    ),
                    child: InkWell(
                      onTap: _logoutPersonalAccount,
                      borderRadius: BorderRadius.circular(18),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        child: Row(
                          children: <Widget>[
                            Container(
                              width: 46,
                              height: 46,
                              decoration: const BoxDecoration(
                                color: Color(0xFFFFE3E0),
                                shape: BoxShape.circle,
                              ),
                              alignment: Alignment.center,
                              child: const Icon(
                                Icons.logout_rounded,
                                color: Color(0xFFB3261E),
                                size: 25,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: <Widget>[
                                  Text(
                                    dedaText('تسجيل الخروج', 'Sign out'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Color(0xFF8B1E17),
                                      fontSize: 16.5,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    dedaText(
                                      'الخروج من الحساب الشخصي الحالي',
                                      'Sign out of the current personal account',
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Color(0xFF795B58),
                                      fontSize: 12.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(
                              Icons.chevron_left_rounded,
                              color: Color(0xFF9B514B),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class OwnerPlacePage'''
if text.count(ui_anchor) != 1:
    raise SystemExit(f'settings UI end anchor count={text.count(ui_anchor)}')
text = text.replace(ui_anchor, ui_new, 1)

path.write_text(text, encoding='utf-8')
print('restored compact personal logout card to Settings 100270')
