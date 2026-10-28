import 'package:flutter/material.dart';

import 'deda_social_service.dart';
import 'deda_weekly_competitor_public_card.dart';

/// Source-authenticated public profile LOOKUP for DEDA's original social
/// directory, used only after an independently verified league snapshot.
/// NOT a proof of eligibility, not a prize issuer and not a friend writer.
/// Participant ID is an opaque league token, NEVER a Firebase UID.
class DedaWeeklyOriginalPublicProfileResolver {
  const DedaWeeklyOriginalPublicProfileResolver._();

  static Future<DedaSocialProfile?> resolve({
    required DedaWeeklyPublicCompetitor competitor,
    required bool Function() stillSameViewer,
    required String? Function() currentAuthUid,
    required Future<DedaSocialProfile?> Function(String) findOriginalProfile,
  }) async {
    if (!competitor.safePublicIdentity || !stillSameViewer()) return null;
    final uid = currentAuthUid();
    if (uid == null || uid.trim().isEmpty) return null;
    final canonical = competitor.originalPublicId;
    final DedaSocialProfile? found;
    try {
      // Never search by the purchased/replaceable active alias, anonymous
      // participant token, phone number or guessed UID.
      found = await findOriginalProfile(canonical);
    } catch (_) {
      return null;
    }
    if (!stillSameViewer() || currentAuthUid() != uid || found == null ||
        found.publicId != canonical || found.ownerUid.trim().isEmpty ||
        found.ownerUid == uid ||
        found.displayName != competitor.displayName) {
      // Directory changes, account switching and stale identity all fail
      // closed. This cannot authorize friendship or identity ownership.
      return null;
    }
    return found;
  }
}

/// Read-only profile navigation backed by the EXISTING DedaSocialService.
/// A new phone/session does not reuse a previous request. No add-friend
/// action is exposed here until original server ownership is independently
/// certified and friendship write rules have been reviewed.
class DedaWeeklyOriginalPublicProfileViewer {
  const DedaWeeklyOriginalPublicProfileViewer._();

  static Future<void> open({
    required BuildContext context,
    required DedaWeeklyPublicCompetitor competitor,
    required bool Function() stillSameViewer,
    required String? Function() currentAuthUid,
    required Stream<Object?> authEvents,
    required Widget Function(BuildContext, int, int, double)
        drawOriginalEquippedAvatar,
    Future<DedaSocialProfile?> Function(String)? findOriginalProfile,
  }) async {
    final profile = await DedaWeeklyOriginalPublicProfileResolver.resolve(
      competitor: competitor,
      stillSameViewer: stillSameViewer,
      currentAuthUid: currentAuthUid,
      findOriginalProfile:
          findOriginalProfile ?? DedaSocialService.findByPublicId,
    );
    if (!context.mounted || !stillSameViewer() || profile == null) return;
    await Navigator.of(context).push<void>(MaterialPageRoute<void>(
      builder: (_) => _DedaWeeklyReadOnlyPublicProfilePage(
        competitor: competitor,
        verifiedPublicProfile: profile,
        stillSameViewer: stillSameViewer,
        authEvents: authEvents,
        drawOriginalEquippedAvatar: drawOriginalEquippedAvatar,
      ),
    ));
  }
}

class _DedaWeeklyReadOnlyPublicProfilePage extends StatelessWidget {
  const _DedaWeeklyReadOnlyPublicProfilePage({
    required this.competitor,
    required this.verifiedPublicProfile,
    required this.stillSameViewer,
    required this.authEvents,
    required this.drawOriginalEquippedAvatar,
  });

  final DedaWeeklyPublicCompetitor competitor;
  final DedaSocialProfile verifiedPublicProfile;
  final bool Function() stillSameViewer;
  final Stream<Object?> authEvents;
  final Widget Function(BuildContext, int, int, double)
      drawOriginalEquippedAvatar;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Object?>(
      stream: authEvents,
      builder: (context, _) {
        if (!stillSameViewer()) {
          return const Scaffold(
            body: SafeArea(child: Center(
              child: Text('انتهت جلسة الحساب. أعد فتح الدوري.'),
            )),
          );
        }
        // Never attach an original DEDA frame to a different owner or
        // an unverified equipped appearance.
        final frameAllowed = competitor.canShowEquippedFrame &&
            verifiedPublicProfile.publicId == competitor.originalPublicId &&
            verifiedPublicProfile.avatarStyle == competitor.avatarStyle &&
            verifiedPublicProfile.frameStyle == competitor.equippedFrameStyle;
        return Scaffold(
          appBar: AppBar(title: const Text('الملف الشخصي العام')),
          body: SafeArea(child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    frameAllowed
                        ? drawOriginalEquippedAvatar(
                            context, competitor.avatarStyle!,
                            competitor.equippedFrameStyle!, 90)
                        : const CircleAvatar(
                            radius: 44, child: Icon(Icons.person, size: 44)),
                    const SizedBox(height: 18),
                    Text(verifiedPublicProfile.displayName,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 10),
                    SelectableText(competitor.activePublicId,
                      textDirection: TextDirection.ltr,
                      textAlign: TextAlign.center),
                    const SizedBox(height: 8),
                    Text('المستوى ${verifiedPublicProfile.level}'),
                    const SizedBox(height: 12),
                    const Text(
                      'عرض عام للملف الشخصي. طلب الصداقة يبقى معطلاً '
                      'إلى حين اكتمال التحقق من ملكية الحساب.',
                      textAlign: TextAlign.center),
                  ],
                ),
              ),
            ),
          )),
        );
      },
    );
  }
}
