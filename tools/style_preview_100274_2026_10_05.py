from pathlib import Path

MAIN = Path('lib/main.dart')
text = MAIN.read_text(encoding='utf-8')
marker = '// DEDA_STYLE_PREVIEW_100274'
if marker in text:
    print('DEDA 100274 style preview patch already applied')
    raise SystemExit(0)

if '// DEDA_STYLE_BADGES_FRAMES_100273' not in text:
    raise SystemExit('DEDA 100273 style layer must exist before 100274')


def replace_once(old: str, new: str, label: str) -> None:
    global text
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected exactly one anchor, found {count}')
    text = text.replace(old, new, 1)


replace_once(
    '// DEDA_STYLE_BADGES_FRAMES_100273\nclass DedaStylePage extends StatefulWidget {',
    '// DEDA_STYLE_BADGES_FRAMES_100273\n// DEDA_STYLE_PREVIEW_100274\nclass DedaStylePage extends StatefulWidget {',
    '100274 marker',
)

replace_once(
    "  int _diamonds = 0;\n  bool _busy = false;\n",
    "  int _diamonds = 0;\n  bool _busy = false;\n  int? _previewFrameIndex;\n  int? _previewBadgeIndex;\n",
    'preview state',
)

replace_once(
    "  Future<bool> _payForIndex(int index) async {\n",
    r'''  void _previewFrame(int index) {
    if (!mounted) return;
    setState(() => _previewFrameIndex = index.clamp(0, 5).toInt());
  }

  void _previewBadge(int index) {
    if (!mounted) return;
    setState(() => _previewBadgeIndex = index.clamp(0, 5).toInt());
  }

  void _clearPreview() {
    if (!mounted) return;
    setState(() {
      _previewFrameIndex = null;
      _previewBadgeIndex = null;
    });
  }

  Future<bool> _payForIndex(int index) async {
''',
    'preview methods',
)

old_body = r'''      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: <Widget>[
          _walletCard(progress, ratio, within),
          const SizedBox(height: 12),
          Text(
            dedaText(
              'مجموعات DEDA المطابقة',
              'Matched DEDA collections',
            ),
            style: const TextStyle(
              color: Color(0xFF0B3C6F),
              fontWeight: FontWeight.w900,
              fontSize: 19,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            dedaText(
              'كل شارة مع إطارها من نفس الهوية. الشراء منفصل، والتفعيل فوري.',
              'Each badge is paired with its matching frame. Purchases are separate and activation is immediate.',
            ),
            style: const TextStyle(
              color: Color(0xFF677987),
              fontWeight: FontWeight.w600,
              fontSize: 12,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 10),
          ...List<Widget>.generate(
            6,
            (index) => _pairCard(index, inventory),
          ),
        ],
      ),
'''
new_body = r'''      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
            child: _stylePreviewCard(progress, inventory),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 2, 12, 24),
              children: <Widget>[
                Text(
                  dedaText(
                    'مجموعات DEDA المطابقة',
                    'Matched DEDA collections',
                  ),
                  style: const TextStyle(
                    color: Color(0xFF0B3C6F),
                    fontWeight: FontWeight.w900,
                    fontSize: 19,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  dedaText(
                    'اضغط على أي شارة أو إطار لمعاينته على ملفك أولاً، ثم قرر الشراء أو الاستخدام.',
                    'Tap any badge or frame to preview it on your profile before buying or equipping it.',
                  ),
                  style: const TextStyle(
                    color: Color(0xFF677987),
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 10),
                ...List<Widget>.generate(
                  6,
                  (index) => _pairCard(index, inventory),
                ),
              ],
            ),
          ),
        ],
      ),
'''
replace_once(old_body, new_body, 'sticky preview body')

preview_method = r'''  Widget _stylePreviewCard(
    DedaSocialProgressSnapshot progress,
    DedaStyleInventorySnapshot inventory,
  ) {
    final actualFrame = DedaPreferences.profileFrameStyle.clamp(0, 5).toInt();
    final previewFrame = (_previewFrameIndex ?? actualFrame).clamp(0, 5).toInt();
    final actualBadgeId = inventory.activeBadges.isEmpty
        ? 'badge_member'
        : inventory.activeBadges.first;
    final actualBadgeIndex = dedaStyleBadgeIds.indexOf(actualBadgeId);
    final previewBadge = (_previewBadgeIndex ??
            (actualBadgeIndex < 0 ? 0 : actualBadgeIndex))
        .clamp(0, 5)
        .toInt();
    final previewing = _previewFrameIndex != null || _previewBadgeIndex != null;

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: <Color>[Color(0xFF102E59), Color(0xFF164D83)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE0BD57), width: 1.1),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x22062E57),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              SizedBox(
                width: 108,
                height: 108,
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: <Widget>[
                    DedaFramedAvatar(
                      avatarStyle: DedaPreferences.profileAvatarStyle,
                      frameStyle: previewFrame,
                      size: 106,
                    ),
                    PositionedDirectional(
                      end: -2,
                      bottom: -1,
                      child: Container(
                        width: 46,
                        height: 46,
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.94),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(0xFFFFD45F),
                            width: 1.2,
                          ),
                        ),
                        child: DedaBadgeAsset(
                          id: dedaStyleBadgeId(previewBadge),
                          size: 41,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            dedaText('معاينة ملفك', 'Your profile preview'),
                            style: const TextStyle(
                              color: Color(0xFFFFDD77),
                              fontWeight: FontWeight.w900,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        if (previewing)
                          IconButton(
                            onPressed: _clearPreview,
                            tooltip: dedaText('إلغاء المعاينة', 'Reset preview'),
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(
                              Icons.refresh_rounded,
                              color: Colors.white,
                              size: 21,
                            ),
                          ),
                      ],
                    ),
                    Text(
                      dedaText(
                        'الإطار: ${dedaStyleName(previewFrame)}',
                        'Frame: ${dedaStyleName(previewFrame)}',
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 11.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      dedaText(
                        'الشارة: ${dedaStyleName(previewBadge)}',
                        'Badge: ${dedaStyleName(previewBadge)}',
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFE3ECF4),
                        fontWeight: FontWeight.w700,
                        fontSize: 11.5,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: _miniBalanceChip('💎', _diamonds),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: _miniBalanceChip('🪙', progress.coins),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            dedaText(
              'المعاينة مجانية ولا تخصم أي رصيد • الخصم فقط عند الضغط على زر الشراء',
              'Preview is free • balance is charged only when you tap Buy',
            ),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFFDCE8F3),
              fontWeight: FontWeight.w600,
              fontSize: 9.8,
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniBalanceChip(String icon, int value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.11),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: Colors.white24),
      ),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Text(
          '$icon $value',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

'''
replace_once(
    '  Widget _walletCard(\n',
    preview_method + '  Widget _walletCard(\n',
    'preview card method',
)

old_badge_art = r'''        SizedBox(
          height: 104,
          child: DedaBadgeAsset(id: dedaStyleBadgeId(index), size: 102),
        ),
'''
new_badge_art = r'''        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _previewBadge(index),
            borderRadius: BorderRadius.circular(16),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              height: 104,
              width: double.infinity,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _previewBadgeIndex == index
                      ? accent
                      : Colors.transparent,
                  width: 2,
                ),
              ),
              child: DedaBadgeAsset(
                id: dedaStyleBadgeId(index),
                size: 98,
              ),
            ),
          ),
        ),
        Text(
          dedaText('اضغط للمعاينة', 'Tap to preview'),
          style: TextStyle(
            color: _previewBadgeIndex == index ? accent : const Color(0xFF71808A),
            fontWeight: FontWeight.w700,
            fontSize: 9.5,
          ),
        ),
'''
replace_once(old_badge_art, new_badge_art, 'badge preview tap')

old_frame_art = r'''        SizedBox(
          height: 104,
          child: Center(
            child: DedaFramedAvatar(
              avatarStyle: DedaPreferences.profileAvatarStyle,
              frameStyle: index,
              size: 102,
            ),
          ),
        ),
'''
new_frame_art = r'''        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _previewFrame(index),
            borderRadius: BorderRadius.circular(16),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              height: 104,
              width: double.infinity,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _previewFrameIndex == index
                      ? accent
                      : Colors.transparent,
                  width: 2,
                ),
              ),
              child: Center(
                child: DedaFramedAvatar(
                  avatarStyle: DedaPreferences.profileAvatarStyle,
                  frameStyle: index,
                  size: 98,
                ),
              ),
            ),
          ),
        ),
        Text(
          dedaText('اضغط للمعاينة', 'Tap to preview'),
          style: TextStyle(
            color: _previewFrameIndex == index ? accent : const Color(0xFF71808A),
            fontWeight: FontWeight.w700,
            fontSize: 9.5,
          ),
        ),
'''
replace_once(old_frame_art, new_frame_art, 'frame preview tap')

old_active_badge = r'''              ? OutlinedButton(
                  onPressed: active ? null : () => _activateBadge(index),
                  child: Text(
                    active ? dedaText('مفعلة', 'Active') : dedaText('تفعيل', 'Use'),
                  ),
                )
'''
new_active_badge = r'''              ? OutlinedButton(
                  onPressed: active
                      ? () => _previewBadge(index)
                      : () => _activateBadge(index),
                  child: Text(
                    active ? dedaText('مفعلة ✓', 'Active ✓') : dedaText('تفعيل', 'Use'),
                  ),
                )
'''
replace_once(old_active_badge, new_active_badge, 'active badge response')

old_equipped_frame = r'''              ? OutlinedButton(
                  onPressed: equipped ? null : () => _equipFrame(index),
                  child: Text(
                    equipped ? dedaText('مستخدم', 'Equipped') : dedaText('استخدام', 'Equip'),
                  ),
                )
'''
new_equipped_frame = r'''              ? OutlinedButton(
                  onPressed: equipped
                      ? () => _previewFrame(index)
                      : () => _equipFrame(index),
                  child: Text(
                    equipped ? dedaText('مستخدم ✓', 'Equipped ✓') : dedaText('استخدام', 'Equip'),
                  ),
                )
'''
replace_once(old_equipped_frame, new_equipped_frame, 'equipped frame response')

MAIN.write_text(text, encoding='utf-8')
print('Applied DEDA 100274 sticky live profile preview for badges and frames')
