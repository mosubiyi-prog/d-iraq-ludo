from pathlib import Path

path = Path('lib/main.dart')
text = path.read_text(encoding='utf-8')
marker = '// DEDA_GIFT_NAV_BADGE_FIX_100271'
if marker in text:
    print('100271 gift nav badge fix already applied')
    raise SystemExit(0)

old_usage = '''              DedaGiftNavBadge(
                child: premiumBottomItem(
                  index: 3,
                  icon: Icons.card_giftcard_outlined,
                  selectedIcon: Icons.card_giftcard_rounded,
                  label: dedaText('هداياي', 'My gifts'),
                  selected: false,
                ),
              ),'''
new_usage = '''              DedaGiftNavBadge(
                label: dedaText('هداياي', 'My gifts'),
                onTap: () => openBottomDestination(3),
              ),'''
if text.count(old_usage) != 1:
    raise SystemExit(f'gift bottom wrapper usage count={text.count(old_usage)}')
text = text.replace(old_usage, new_usage, 1)

class_start = text.find('class DedaGiftNavBadge extends StatefulWidget {')
class_end = text.find('\nclass DedaMyGiftsPage extends StatefulWidget {', class_start)
if class_start < 0 or class_end < 0:
    raise SystemExit('gift nav badge class bounds missing')

new_class = r'''// DEDA_GIFT_NAV_BADGE_FIX_100271
class DedaGiftNavBadge extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  const DedaGiftNavBadge({
    super.key,
    required this.label,
    required this.onTap,
  });

  @override
  State<DedaGiftNavBadge> createState() => _DedaGiftNavBadgeState();
}

class _DedaGiftNavBadgeState extends State<DedaGiftNavBadge> {
  @override
  void initState() {
    super.initState();
    unawaited(DedaGiftInbox.start());
  }

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: ValueListenableBuilder<int>(
        valueListenable: DedaGiftInbox.pendingNotifier,
        builder: (context, pending, _) => Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: widget.onTap,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 7),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Icon(
                      Icons.card_giftcard_outlined,
                      color: Colors.white,
                      size: 24,
                    ),
                    const SizedBox(height: 3),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        widget.label,
                        maxLines: 1,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (pending > 0)
              PositionedDirectional(
                top: 0,
                end: 2,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 19, minHeight: 19),
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD92D20),
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  child: Text(
                    pending > 99 ? '99+' : '$pending',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      height: 1,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
'''

text = text[:class_start] + new_class + text[class_end:]
path.write_text(text, encoding='utf-8')
print('applied 100271 bottom-nav compatible gift badge')
