from pathlib import Path

path = Path('lib/main.dart')
text = path.read_text(encoding='utf-8')
marker = '// DEDA_SOCIAL_RUNTIME_REFINEMENT_100269'
if marker in text:
    print('DEDA social runtime refinement already applied')
    raise SystemExit(0)
if '// DEDA_SOCIAL_SYSTEM_100269' not in text:
    raise SystemExit('consolidated social system must be applied first')

# Task reward: persist XP/DEDA currency, then update the safe social profile.
old_hook = '''    if (result.pointsAwarded) {
      unawaited(DedaSocialProgressWallet.awardTaskClaim(taskId));
    }'''
new_hook = '''    if (result.pointsAwarded) {
      try {
        await DedaSocialProgressWallet.awardTaskClaim(taskId);
        await dedaEnsurePersonalSocialSession();
      } catch (_) {
        // The original task reward is authoritative. Social cosmetic progress
        // must never undo or block a successfully claimed task reward.
      }
    }'''
if text.count(old_hook) != 1:
    raise SystemExit('task social progress hook anchor missing')
text = text.replace(old_hook, new_hook, 1)

# My Profile should repaint once the account-scoped level has loaded.
old_load = '    unawaited(DedaSocialProgressWallet.load());'
new_load = '''    unawaited(DedaSocialProgressWallet.load().then((_) {
      if (mounted) setState(() {});
    }));'''
if text.count(old_load) != 1:
    raise SystemExit('profile social progress load anchor missing')
text = text.replace(old_load, new_load, 1)

# This social feature is personal-only. Never ask the identity helper to create
# or refresh a place-share identity as a side effect of opening social pages.
old_place = '    hasApprovedPlace: type == DedaAccountType.placeOwner,'
new_place = '''    // Personal social profile only; place-owner identity remains in its
    // separate existing settings/management flow.
    hasApprovedPlace: false,'''
if text.count(old_place) != 1:
    raise SystemExit('personal-only social identity anchor missing')
text = text.replace(old_place, new_place, 1)

# Upgrade Friends cards to show the actual safe cosmetic profile and level.
start_marker = 'class _DedaFriendCompactCard extends StatelessWidget {'
end_marker = 'class DedaAddFriendPage extends StatefulWidget {'
start = text.index(start_marker)
end = text.index(end_marker, start)
new_card = r'''class _DedaFriendCompactCard extends StatelessWidget {
  final String name;
  final String dedaId;
  final VoidCallback onOpen;
  final VoidCallback onRemove;
  const _DedaFriendCompactCard({
    required this.name,
    required this.dedaId,
    required this.onOpen,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DedaSocialProfile?>(
      future: DedaSocialService.findByPublicId(dedaId),
      builder: (context, snapshot) {
        final profile = snapshot.data;
        return Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(17),
          child: InkWell(
            onTap: onOpen,
            borderRadius: BorderRadius.circular(17),
            child: Container(
              constraints: const BoxConstraints(minHeight: 78),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(17),
                border: Border.all(color: const Color(0xFFD5E3ED)),
              ),
              child: Row(
                children: <Widget>[
                  if (profile != null)
                    DedaFramedAvatar(
                      avatarStyle: profile.avatarStyle,
                      frameStyle: profile.frameStyle,
                      size: 58,
                    )
                  else
                    const CircleAvatar(
                      radius: 27,
                      backgroundColor: Color(0xFFE6F1FC),
                      child: Icon(Icons.person_rounded,
                          color: Color(0xFF1769C2), size: 27),
                    ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Text(
                          profile?.displayName ?? name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF0B3C6F),
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                          ),
                        ),
                        Directionality(
                          textDirection: TextDirection.ltr,
                          child: Text(
                            dedaId,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF647787),
                              fontWeight: FontWeight.w700,
                              fontSize: 11.5,
                            ),
                          ),
                        ),
                        if (profile != null)
                          Text(
                            dedaText(
                              '⭐ المستوى ${profile.level}',
                              '⭐ Level ${profile.level}',
                            ),
                            style: const TextStyle(
                              color: Color(0xFF9A6800),
                              fontWeight: FontWeight.w900,
                              fontSize: 10.5,
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: dedaText('إزالة الصديق', 'Remove friend'),
                    onPressed: onRemove,
                    icon: const Icon(
                      Icons.more_vert_rounded,
                      color: Color(0xFF607487),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

'''
text = text[:start] + new_card + text[end:]
text = text.replace('// DEDA_SOCIAL_SYSTEM_100269',
                    '// DEDA_SOCIAL_SYSTEM_100269\n' + marker, 1)
path.write_text(text, encoding='utf-8')
print('applied DEDA social runtime refinements 100269')
