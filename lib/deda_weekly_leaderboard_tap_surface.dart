import 'package:flutter/material.dart';
import 'deda_weekly_competitor_public_card.dart';

/// Reuses the original app's public-profile navigator and friendship service
/// only via callbacks supplied by an AUTHENTICATED main-app coordinator.
///
/// This UI NEVER writes friendship docs, XP, balances or frames. A future
/// server-owned verified identity with a known target owner is mandatory.
class DedaWeeklyLeaderboardTapSurface extends StatelessWidget {
  const DedaWeeklyLeaderboardTapSurface({
    super.key,
    required this.child,
    required this.competitor,
    required this.viewerParticipantId,
    this.friendRelation = DedaWeeklyFriendRelation.unknown,
    this.onOpenExistingPublicProfile,
    this.onSendExistingFriendRequest,
  });

  final Widget child;
  final DedaWeeklyPublicCompetitor? competitor;
  final String? viewerParticipantId;
  final DedaWeeklyFriendRelation friendRelation;
  final Future<void> Function(DedaWeeklyPublicCompetitor)?
      onOpenExistingPublicProfile;
  final Future<void> Function(DedaWeeklyPublicCompetitor)?
      onSendExistingFriendRequest;

  bool get canOpen {
    final person=competitor;
    return person != null &&
        person.isOtherVerifiedParticipant(viewerParticipantId) &&
        (onOpenExistingPublicProfile != null ||
            (friendRelation == DedaWeeklyFriendRelation.notFriends &&
                onSendExistingFriendRequest != null));
  }

  Future<void> _open(BuildContext context) async {
    if (!canOpen || !context.mounted) return;
    final target=competitor!;
    const gold=Color(0xFFFFCF67);
    const navy=Color(0xFF0B2C50);
    await showModalBottomSheet<void>(
      context:context,
      backgroundColor:navy,
      showDragHandle:true,
      builder:(sheet) => SafeArea(
        child:Padding(
          padding:const EdgeInsets.all(16),
          child:Column(
            mainAxisSize:MainAxisSize.min,
            children:[
              Text(target.displayName,
                textAlign:TextAlign.center,
                style:const TextStyle(color:gold,fontSize:19,
                  fontWeight:FontWeight.bold)),
              Text(target.activePublicId,
                textDirection:TextDirection.ltr,
                style:const TextStyle(color:Colors.white70)),
              const SizedBox(height:8),
              if(onOpenExistingPublicProfile!=null)
                FilledButton.icon(
                  icon:const Icon(Icons.person_outline),
                  label:const Text('مشاهدة الملف الشخصي'),
                  onPressed:(){
                    Navigator.of(sheet).pop();
                    onOpenExistingPublicProfile!(target);
                  },
                ),
              if(friendRelation==DedaWeeklyFriendRelation.notFriends &&
                 onSendExistingFriendRequest!=null)
                OutlinedButton.icon(
                  icon:const Icon(Icons.person_add_alt_1),
                  label:const Text('إرسال طلب صداقة'),
                  onPressed:(){
                    Navigator.of(sheet).pop();
                    onSendExistingFriendRequest!(target);
                  },
                ),
              if(friendRelation==DedaWeeklyFriendRelation.pending)
                const Text('طلب الصداقة قيد الانتظار',
                  style:TextStyle(color:gold)),
              if(friendRelation==DedaWeeklyFriendRelation.friends)
                const Text('أنتما أصدقاء بالفعل',
                  style:TextStyle(color:gold)),
              if(friendRelation==DedaWeeklyFriendRelation.unknown)
                const Text('حالة الصداقة بانتظار التحقق',
                  style:TextStyle(color:Colors.white70)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Semantics(
    button:canOpen,
    label:canOpen?'عرض خيارات المتصدر':'متصدر بانتظار التحقق',
    child:InkWell(
      onTap:canOpen?()=>_open(context):null,
      borderRadius:BorderRadius.circular(12),
      child:child,
    ),
  );
}
