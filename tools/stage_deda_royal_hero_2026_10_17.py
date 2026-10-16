#!/usr/bin/env python3
"""DEDA step1: ONLY restyle the reconstructed 100340 profile HERO.

Run after ALL production 100340 source reconstruction stages.
No wallet, XP, tasks, friend, purchase, backend, Firebase, or publishing code touched.
Fail closed if any historical anchor changes.
"""
from pathlib import Path
import sys

path = Path('lib/main.dart')
if not path.exists():
    raise SystemExit('SAFE_STOP: missing rebuilt lib/main.dart')
old=path.read_text(encoding='utf-8')
marker = '// DEDA_ROYAL_PROFILE_HERO_LAYOUT_ONLY_2026_10_17'
if marker in old:
    print('PASS: royal hero already applied; no edits')
    raise SystemExit(0)

start_anchor='  Widget _profileHeroCard() {'
end_anchor='  Widget _avatar(int frameStyle, double size) {'
painter_anchor='class _DedaProfilePhase2PageState extends State<DedaProfilePhase2Page> {'
for text in (start_anchor,end_anchor,painter_anchor):
    if old.count(text)!=1:
        raise SystemExit(f'SAFE_STOP: expected exactly one source anchor {text!r}, found {old.count(text)}')
start=old.index(start_anchor)
end=old.index(end_anchor)
oldhero=old[start:end]
for needle in (
   'DedaProfileAppearanceState.frameNotifier',
   '_avatar(frameStyle, compact ? 82 : 90)',
   'DedaSocialProgressWallet.xpNotifier',
   'DedaStyleInventory.activeBadgeNotifier',
   'DedaBadgeAsset(id: badgeId, size: 34)',
   'onTap: _copyDedaId',
   'dedaProfileBackgroundColors(',
):
    if needle not in oldhero:
        raise SystemExit(f'SAFE_STOP: inherited hero marker missing: {needle}')

hero=r'''  // DEDA_ROYAL_PROFILE_HERO_LAYOUT_ONLY_2026_10_17
  // Layout and paint only. Existing notifiers and account actions stay intact.
  Widget _profileHeroCard() {
    final name = DedaPreferences.userName.trim().isEmpty
        ? dedaText('مستخدم DEDA', 'DEDA user')
        : DedaPreferences.userName.trim();
    final id = _dedaId.isEmpty ? '@DEDA' : _dedaId;
    // Keep saved legacy background preference intact, and use it only for
    // a subtle glow tint; do not overwrite any selected user appearance.
    final savedColors = dedaProfileBackgroundColors(
      DedaPreferences.profileBackgroundStyle,
    );

    return LayoutBuilder(
      builder: (context, outer) {
        final width = outer.maxWidth;
        final compact = width < 355;
        final avatarSize = compact ? 174.0 : 202.0;
        return Container(
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: <Color>[
                Color(0xFF092A63),
                Color(0xFF222056),
                Color(0xFF51204E),
                Color(0xFF111C49),
              ],
              stops: <double>[0, 0.41, 0.72, 1],
            ),
            borderRadius: BorderRadius.circular(29),
            border: Border.all(color: const Color(0xFFF2CC68), width: 2),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x40210E46),
                blurRadius: 21,
                offset: Offset(0, 9),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: <Widget>[
              Positioned.fill(
                child: CustomPaint(
                  painter: _DedaRoyalProfileBackdropPainter(
                    glow: savedColors.last,
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsetsDirectional.fromSTEB(
                  compact ? 12 : 17,
                  14,
                  compact ? 12 : 17,
                  16,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Center(
                      child: ValueListenableBuilder<int>(
                        valueListenable: DedaProfileAppearanceState.frameNotifier,
                        builder: (context, frameStyle, _) =>
                            _avatar(frameStyle, avatarSize),
                      ),
                    ),
                    const SizedBox(height: 10),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 360),
                      child: Text(
                        name,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: compact ? 25 : 28,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          shadows: const <Shadow>[
                            Shadow(color: Color(0x80000000), blurRadius: 8),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 7),
                    Material(
                      color: const Color(0x2BFFFFFF),
                      borderRadius: BorderRadius.circular(28),
                      child: InkWell(
                        onTap: _copyDedaId,
                        borderRadius: BorderRadius.circular(28),
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 320),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 13,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(28),
                            border: Border.all(
                              color: const Color(0x88D7C8F4),
                              width: 1,
                            ),
                          ),
                          child: Directionality(
                            textDirection: TextDirection.ltr,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Flexible(
                                  child: Text(
                                    id,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: compact ? 15.0 : 17.0,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                const Icon(
                                  Icons.copy_rounded,
                                  color: Color(0xFFEEE7FD),
                                  size: 18,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 5,
                      children: <Widget>[
                        ValueListenableBuilder<int>(
                          valueListenable: DedaSocialProgressWallet.xpNotifier,
                          builder: (context, totalPoints, _) {
                            // Reuse the live level calculation already used
                            // by _profileLevelProgressCard; no new XP logic.
                            final level = DedaSocialProgressWallet.levelForXp(
                              totalPoints.clamp(0, 1 << 30).toInt(),
                            );
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 15,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: <Color>[
                                    Color(0xFFFFEBA4),
                                    Color(0xFFF0C15E),
                                    Color(0xFFFFE9A0),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(25),
                                border: Border.all(
                                  color: const Color(0xFFFFFFDA),
                                  width: 1.3,
                                ),
                                boxShadow: const <BoxShadow>[
                                  BoxShadow(
                                    color: Color(0x80DEA928),
                                    blurRadius: 13,
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  const Icon(
                                    Icons.star_rounded,
                                    size: 19,
                                    color: Color(0xFF986310),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    dedaText(
                                      'مستوى ذهبي $level',
                                      'Gold level $level',
                                    ),
                                    style: TextStyle(
                                      fontSize: compact ? 15.5 : 17.0,
                                      color: const Color(0xFF704807),
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                        // This is the already-equipped badge, NOT a fake badge.
                        ValueListenableBuilder<String>(
                          valueListenable:
                              DedaStyleInventory.activeBadgeNotifier,
                          builder: (context, badgeId, _) => Container(
                            width: 51,
                            height: 51,
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFDF7DC),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: const Color(0xFFE2B647),
                                width: 2,
                              ),
                              boxShadow: const <BoxShadow>[
                                BoxShadow(
                                  color: Color(0x80E7B13A),
                                  blurRadius: 12,
                                ),
                              ],
                            ),
                            child: DedaBadgeAsset(id: badgeId, size: 42),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        const Icon(
                          Icons.people_alt_outlined,
                          color: Color(0xFFE6DBF4),
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            dedaText(
                              'عضو في مجتمع DEDA',
                              'Member of the DEDA community',
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFFE9DFF9),
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

'''

painter=r'''// Decorative ONLY: no data reads and no animations on the navigation thread.
class _DedaRoyalProfileBackdropPainter extends CustomPainter {
  final Color glow;
  const _DedaRoyalProfileBackdropPainter({required this.glow});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final t = Paint()
      ..shader = RadialGradient(
        colors: <Color>[
          glow.withOpacity(0.19),
          glow.withOpacity(0.0),
        ],
      ).createShader(Rect.fromCircle(
        center: Offset(w * 0.16, h * 0.63),
        radius: w * 0.68,
      ));
    canvas.drawRect(Offset.zero & size, t);

    final thin = Paint()
      ..color = const Color(0x9CFFE5A4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.0037;
    final ribbon = Path()
      ..moveTo(-w * 0.06, h * 0.65)
      ..cubicTo(w * 0.19, h * 0.57, w * 0.22, h * 0.80,
          w * 0.50, h * 0.72)
      ..cubicTo(w * 0.72, h * 0.64, w * 0.79, h * 0.47,
          w * 1.05, h * 0.51);
    canvas.drawPath(ribbon, thin);
    final ribbon2 = Path()
      ..moveTo(-w * 0.08, h * 0.77)
      ..cubicTo(w * 0.28, h * 0.61, w * 0.30, h * 0.87,
          w * 0.58, h * 0.78)
      ..cubicTo(w * 0.76, h * 0.73, w * 0.87, h * 0.66,
          w * 1.04, h * 0.62);
    canvas.drawPath(ribbon2, thin..color = const Color(0x45FFDFA4));

    final sparkle = Paint()..color = const Color(0xE6FFF3C0);
    const stars = <Offset>[
      Offset(0.09, 0.08), Offset(0.24, 0.20),
      Offset(0.80, 0.11), Offset(0.92, 0.31),
      Offset(0.15, 0.48), Offset(0.88, 0.72),
      Offset(0.06, 0.90), Offset(0.71, 0.90),
      Offset(0.95, 0.94),
    ];
    for (var i = 0; i < stars.length; i++) {
      final x = stars[i].dx * w;
      final y = stars[i].dy * h;
      final r = (i % 3 == 0 ? 3.2 : 2.1) * (w / 400.0);
      final star = Path()
        ..moveTo(x, y - r * 2.1)
        ..lineTo(x + r * 0.5, y - r * 0.5)
        ..lineTo(x + r * 1.5, y)
        ..lineTo(x + r * 0.5, y + r * 0.5)
        ..lineTo(x, y + r * 2.1)
        ..lineTo(x - r * 0.5, y + r * 0.5)
        ..lineTo(x - r * 1.5, y)
        ..lineTo(x - r * 0.5, y - r * 0.5)
        ..close();
      canvas.drawPath(star, sparkle);
    }
  }

  @override
  bool shouldRepaint(_DedaRoyalProfileBackdropPainter oldDelegate) =>
      oldDelegate.glow != glow;
}

'''

new = old[:start]+hero+old[end:]
new = new.replace(painter_anchor, painter+painter_anchor,1)
# A STRICT algebraic safeguard: restoring the previous hero and removing
# only the added painter must recover every byte of the original source.
recovered=new.replace(painter+painter_anchor,painter_anchor,1)
recovered=recovered.replace(hero,oldhero,1)
if recovered!=old:
    raise SystemExit('SAFE_STOP: a non-hero source byte would change')
for section in (
    'Widget _profileLevelProgressCard() {',
    'Widget _statsRow() {',
    'Widget _pointsCardsPanel(int totalPoints) {',
    'Widget _statCard({',
    'class DedaDiamondsWallet',
    'class DedaTaskEngine',
):
    if section not in new:
        raise SystemExit('SAFE_STOP: protected section missing '+section)
path.write_text(new,encoding='utf8')
print('PASS: royal-profile hero-only patch; EVERY non-hero source byte identical')
print('Hero original bytes:',len(oldhero),'new bytes:',len(hero))