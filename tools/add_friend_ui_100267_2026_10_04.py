from pathlib import Path

path = Path('lib/main.dart')
text = path.read_text(encoding='utf-8')

marker = '// DEDA_ADD_FRIEND_UI_100267'
if marker in text:
    print('add friend ui 100267 already applied')
    raise SystemExit(0)

# 1) Keep the user-requested Friends search line fully visible.
old_hint = "'ابحث بين أصدقائك بالاسم أو معرف DEDA'"
new_hint = "'ابحث بالاسم أو معرف DEDA'"
if text.count(old_hint) != 1:
    raise SystemExit(f'expected one Friends search hint, found {text.count(old_hint)}')
text = text.replace(old_hint, new_hint, 1)

# 2) Replace only the visual placeholder for Add friend.
old_placeholder = """          _DedaSocialPlaceholderPage(
            arabicTitle: 'إضافة صديق',
            englishTitle: 'Add friend',
            icon: Icons.person_add_alt_1_rounded,
            accent: Color(0xFF14945E),
          ),"""
new_page = """          const DedaAddFriendPage(),"""
if text.count(old_placeholder) != 1:
    raise SystemExit(
        f'expected one Add friend placeholder, found {text.count(old_placeholder)}'
    )
text = text.replace(old_placeholder, new_page, 1)

addition = r'''

// DEDA_ADD_FRIEND_UI_100267
// Visual/local-validation phase only. No friendship backend or request writes here.
class DedaAddFriendPage extends StatefulWidget {
  const DedaAddFriendPage({super.key});

  @override
  State<DedaAddFriendPage> createState() => _DedaAddFriendPageState();
}

class _DedaAddFriendPageState extends State<DedaAddFriendPage> {
  final TextEditingController _idController = TextEditingController();
  static const Color _navy = Color(0xFF0B4D8D);
  static const Color _green = Color(0xFF15946A);
  static const Color _cream = Color(0xFFF8FAF2);

  String get _myDedaId =>
      DedaBackend.personalShareIdForPhone(DedaPreferences.phone).trim();

  @override
  void dispose() {
    _idController.dispose();
    super.dispose();
  }

  String _normalizedId(String raw) {
    var value = raw.trim().toUpperCase();
    value = value.replaceAll(' ', '');
    if (value.isEmpty) return value;
    if (!value.startsWith('@')) value = '@$value';
    return value;
  }

  bool _looksLikeDedaId(String value) {
    return RegExp(r'^@DEDA-[A-Z0-9]{5,12}$').hasMatch(value);
  }

  Future<void> _copyMyId() async {
    final id = _myDedaId;
    if (id.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: id));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          dedaText('تم نسخ معرفك في DEDA', 'Your DEDA ID was copied'),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  void _previewSearch() {
    final id = _normalizedId(_idController.text);
    if (id.isEmpty) {
      _showMessage(
        'اكتب معرف DEDA للصديق أولاً.',
        'Enter your friend\'s DEDA ID first.',
      );
      return;
    }
    if (!_looksLikeDedaId(id)) {
      _showMessage(
        'تحقق من المعرف. مثال: @DEDA-AQPYXJ',
        'Check the ID format. Example: @DEDA-AQPYXJ',
      );
      return;
    }
    final myId = _normalizedId(_myDedaId);
    if (myId.isNotEmpty && id == myId) {
      _showMessage(
        'لا يمكنك إضافة نفسك كصديق.',
        'You cannot add yourself as a friend.',
      );
      return;
    }
    _idController.value = TextEditingValue(
      text: id,
      selection: TextSelection.collapsed(offset: id.length),
    );
    _showMessage(
      'واجهة البحث جاهزة. ربط التحقق بالحسابات وإرسال الطلب سيكون في المرحلة التالية.',
      'The search UI is ready. Account lookup and friend requests will be connected in the next phase.',
    );
  }

  void _showMessage(String ar, String en) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(
          dedaText(ar, en),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final myId = _myDedaId.isEmpty ? '@DEDA' : _myDedaId;
    return Scaffold(
      backgroundColor: _cream,
      appBar: AppBar(
        centerTitle: true,
        elevation: 0,
        foregroundColor: Colors.white,
        backgroundColor: _navy,
        title: Text(
          dedaText('إضافة صديق', 'Add friend'),
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _headerCard(),
                const SizedBox(height: 18),
                _myIdCard(myId),
                const SizedBox(height: 18),
                _searchCard(),
                const SizedBox(height: 18),
                _resultPlaceholder(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _headerCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: <Color>[Color(0xFFE4F7EF), Color(0xFFF5FBF8)],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFB9E1D2), width: 1.2),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x1715946A),
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 66,
            height: 66,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: <Color>[Color(0xFF1AAF7A), Color(0xFF0E7C59)],
              ),
              boxShadow: const <BoxShadow>[
                BoxShadow(
                  color: Color(0x3515946A),
                  blurRadius: 12,
                  offset: Offset(0, 5),
                ),
              ],
            ),
            child: const Icon(
              Icons.person_add_alt_1_rounded,
              color: Colors.white,
              size: 34,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  dedaText('أضف صديقك بمعرف DEDA', 'Add a friend by DEDA ID'),
                  style: const TextStyle(
                    color: Color(0xFF0B3C6F),
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  dedaText(
                    'اكتب المعرف، تحقق منه، وبعد الربط الحقيقي ستتمكن من إرسال طلب الصداقة.',
                    'Enter the ID and verify it. Friend-request sending will be enabled when the real connection is added.',
                  ),
                  style: const TextStyle(
                    color: Color(0xFF607487),
                    height: 1.45,
                    fontWeight: FontWeight.w600,
                    fontSize: 13.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _myIdCard(String myId) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFD7E4EE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            dedaText('معرفي في DEDA', 'My DEDA ID'),
            style: const TextStyle(
              color: Color(0xFF0B3C6F),
              fontWeight: FontWeight.w900,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 11),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: const Color(0xFFF2F7FB),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Directionality(
                    textDirection: TextDirection.ltr,
                    child: FittedBox(
                      alignment: Alignment.centerLeft,
                      fit: BoxFit.scaleDown,
                      child: Text(
                        myId,
                        maxLines: 1,
                        style: const TextStyle(
                          color: Color(0xFF334E68),
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton.filledTonal(
                  tooltip: dedaText('نسخ معرفي', 'Copy my ID'),
                  onPressed: _copyMyId,
                  icon: const Icon(Icons.copy_rounded, size: 20),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            dedaText(
              'شارك هذا المعرف مع أصدقائك ليبحثوا عنك داخل DEDA.',
              'Share this ID so your friends can find you in DEDA.',
            ),
            style: const TextStyle(
              color: Color(0xFF7A8996),
              fontWeight: FontWeight.w600,
              fontSize: 12.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _searchCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFBFD7EB), width: 1.2),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x140B4D8D),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            dedaText('معرف الصديق', 'Friend DEDA ID'),
            style: const TextStyle(
              color: Color(0xFF0B3C6F),
              fontWeight: FontWeight.w900,
              fontSize: 17,
            ),
          ),
          const SizedBox(height: 10),
          Directionality(
            textDirection: TextDirection.ltr,
            child: TextField(
              controller: _idController,
              textDirection: TextDirection.ltr,
              textCapitalization: TextCapitalization.characters,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                hintText: '@DEDA-AQPYXJ',
                prefixIcon: const Icon(Icons.alternate_email_rounded),
                filled: true,
                fillColor: const Color(0xFFF7FAFC),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 15,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: Color(0xFFD5E3EF)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: _navy, width: 1.6),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _previewSearch,
              icon: const Icon(Icons.search_rounded, size: 22),
              label: Text(
                dedaText('بحث عن المعرف', 'Search ID'),
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _navy,
                foregroundColor: Colors.white,
                elevation: 3,
                shadowColor: const Color(0x440B4D8D),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(17),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _resultPlaceholder() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFCF3),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFF0D99A)),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFFFFF0BE),
            ),
            child: const Icon(
              Icons.account_circle_outlined,
              color: Color(0xFFB07800),
              size: 29,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  dedaText('نتيجة البحث', 'Search result'),
                  style: const TextStyle(
                    color: Color(0xFF7D5700),
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  dedaText(
                    'بعد ربط الحسابات، ستظهر هنا بطاقة الصديق: الصورة، الاسم، المعرف، المستوى وزر إرسال الطلب.',
                    'After account lookup is connected, the friend card will appear here with avatar, name, ID, level, and send-request action.',
                  ),
                  style: const TextStyle(
                    color: Color(0xFF7A6A45),
                    height: 1.45,
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
'''

text = text.rstrip() + addition + '\n'
path.write_text(text, encoding='utf-8')
print('applied DEDA add friend UI 100267')
