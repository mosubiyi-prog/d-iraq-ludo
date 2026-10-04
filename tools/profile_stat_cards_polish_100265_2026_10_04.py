from pathlib import Path

path = Path('lib/main.dart')
text = path.read_text(encoding='utf-8')

marker = '// DEDA_PROFILE_STAT_CARDS_POLISH_100265'
if marker in text:
    print('profile stat cards polish 100265 already applied')
    raise SystemExit(0)

if '// DEDA_PROFILE_POINTS_TOGGLE_100264' not in text:
    raise SystemExit('100264 points toggle must be applied before 100265')

state_marker = 'class _DedaProfilePhase2PageState extends State<DedaProfilePhase2Page> {'
start = text.index(state_marker)
end = text.index('class DedaPublicProfilePreviewPage', start)
profile = text[start:end]

old_start = profile.index('  Widget _statCard({')
old_end = profile.index('  Widget _featureGrid()', old_start)

new_method = r'''  // DEDA_PROFILE_STAT_CARDS_POLISH_100265
  Widget _statCard({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
    required Color surface,
  }) {
    final topSurface = Color.lerp(surface, Colors.white, 0.34)!;
    final bottomSurface = Color.lerp(surface, color, 0.10)!;
    final iconTop = Color.lerp(color, Colors.white, 0.18)!;
    final iconBottom = Color.lerp(color, Colors.black, 0.10)!;

    return Container(
      constraints: const BoxConstraints(minHeight: 104),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            topSurface,
            surface,
            bottomSurface,
          ],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: Color.lerp(color, Colors.white, 0.46)!,
          width: 1.2,
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: color.withOpacity(0.15),
            blurRadius: 14,
            spreadRadius: 0.4,
            offset: const Offset(0, 6),
          ),
          const BoxShadow(
            color: Color(0x12062E57),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          Positioned(
            right: -16,
            top: -20,
            child: Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.18),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 9, 6, 9),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: <Color>[iconTop, color, iconBottom],
                    ),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.86),
                      width: 1.3,
                    ),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: color.withOpacity(0.34),
                        blurRadius: 9,
                        spreadRadius: 0.5,
                        offset: const Offset(0, 4),
                      ),
                      const BoxShadow(
                        color: Color(0x40FFFFFF),
                        blurRadius: 3,
                        offset: Offset(-1, -1),
                      ),
                    ],
                  ),
                  child: Icon(
                    icon,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
                const SizedBox(height: 5),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    value,
                    maxLines: 1,
                    style: const TextStyle(
                      color: _deepNavy,
                      fontWeight: FontWeight.w900,
                      fontSize: 21,
                      height: 1.0,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF43566A),
                    fontWeight: FontWeight.w800,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

'''

profile = profile[:old_start] + new_method + profile[old_end:]
text = text[:start] + profile + text[end:]

path.write_text(text, encoding='utf-8')
print('applied DEDA 100265: polished raised profile stat cards')
