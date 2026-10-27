import 'package:flutter/material.dart';

/// An authenticated, backend-issued league row AND a matching public profile.
/// Opaque participantId is NEVER assumed to be the Firebase UID.
class DedaWeeklyPublicCompetitor {
  const DedaWeeklyPublicCompetitor({
    required this.participantId, required this.originalPublicId,
    required this.activePublicId, required this.displayName,
    required this.rankVerified, required this.publicOwnerVerified,
    required this.equippedAppearanceVerified, this.avatarStyle,
    this.equippedFrameStyle,
  });
  final String participantId, originalPublicId, activePublicId, displayName;
  final bool rankVerified, publicOwnerVerified, equippedAppearanceVerified;
  final int? avatarStyle, equippedFrameStyle;
  static final participantPattern=RegExp(r'^[A-Za-z0-9_-]{16,90}$');
  static final originalPattern=RegExp(r'^@DEDA-[A-Z0-9]{6}$');
  static final activePattern=RegExp(r'^@DEDA-[A-Z0-9]{4,12}$');
  static final namePattern=RegExp(r'^[^\x00-\x1F\x7F@]{2,60}$');

  bool get safePublicIdentity =>
      rankVerified && publicOwnerVerified &&
      participantPattern.hasMatch(participantId) &&
      originalPattern.hasMatch(originalPublicId) &&
      activePattern.hasMatch(activePublicId) &&
      namePattern.hasMatch(displayName) &&
      !RegExp(r'\b0[0-9]{10}\b').hasMatch(displayName) &&
      !RegExp(r'\S+@\S+').hasMatch(displayName);

  /// Showing a purchased or free frame requires proof it is EQUIPPED for
  /// this owner, not merely listed/previewed/owned by the viewer.
  bool get canShowEquippedFrame => safePublicIdentity &&
      equippedAppearanceVerified &&
      avatarStyle != null && avatarStyle! >= 0 && avatarStyle! <= 18 &&
      equippedFrameStyle != null &&
      equippedFrameStyle! >= 0 && equippedFrameStyle! <= 18;
  bool isOtherVerifiedParticipant(String? viewerParticipantId) =>
      safePublicIdentity && viewerParticipantId != null &&
      participantPattern.hasMatch(viewerParticipantId) &&
      participantId != viewerParticipantId;
}

enum DedaWeeklyFriendRelation { unknown, notFriends, pending, friends, self }

/// This is ONLY a verified-data presentation surface. The caller supplies
/// ORIGINAL DEDA DedaFramedAvatar and authenticated public-profile/social
/// actions. NO Firebase, wallet, XP, purchase or relationship write here.
/// No callback means no false impression that the action has been enabled.
class DedaWeeklyCompetitorCard extends StatelessWidget {
  const DedaWeeklyCompetitorCard({
    super.key, required this.profile, required this.viewerParticipantId,
    this.relation = DedaWeeklyFriendRelation.unknown,
    this.drawOriginalEquippedAvatar, this.onOpenExistingPublicProfile,
    this.onSendExistingFriendRequest, this.compact = false,
  });
  final DedaWeeklyPublicCompetitor? profile;
  final String? viewerParticipantId;
  final DedaWeeklyFriendRelation relation;
  final Widget Function(BuildContext,int avatarStyle,int frameStyle,double size)?
      drawOriginalEquippedAvatar;
  final Future<void> Function(DedaWeeklyPublicCompetitor)?
      onOpenExistingPublicProfile;
  final Future<void> Function(DedaWeeklyPublicCompetitor)?
      onSendExistingFriendRequest;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    const gold=Color(0xFFFFD268), navy=Color(0xFF0E2E52);
    final verified=profile?.safePublicIdentity == true;
    final data=profile;
    final actionable=verified &&
        data!.isOtherVerifiedParticipant(viewerParticipantId) &&
        (onOpenExistingPublicProfile!=null ||
            (relation==DedaWeeklyFriendRelation.notFriends &&
             onSendExistingFriendRequest!=null));
    final size=compact?36.0:66.0;
    final framed=verified && data!.canShowEquippedFrame &&
        drawOriginalEquippedAvatar!=null;
    final portrait=framed
        ? drawOriginalEquippedAvatar!(
            context,data.avatarStyle!,data.equippedFrameStyle!,size)
        : CircleAvatar(radius:size/2,backgroundColor:navy,
            child:Icon(Icons.person,size:size*.55,color:gold));

    Future<void> showActions() async {
      if(!actionable || !context.mounted)return;
      final target=data!;
      await showModalBottomSheet<void>(
        context:context,backgroundColor:navy,showDragHandle:true,
        builder:(sheet)=>SafeArea(child:Padding(
          padding:const EdgeInsets.all(16),
          child:Column(mainAxisSize:MainAxisSize.min,children:[
            Text(target.displayName,style:const TextStyle(
              color:gold,fontSize:19,fontWeight:FontWeight.bold)),
            Text(target.activePublicId,textDirection:TextDirection.ltr,
              style:const TextStyle(color:Colors.white70)),
            if(onOpenExistingPublicProfile!=null)
              FilledButton.icon(icon:const Icon(Icons.person_outline),
                label:const Text('مشاهدة الملف الشخصي'),
                onPressed:(){
                  Navigator.pop(sheet);
                  onOpenExistingPublicProfile!(target);
                }),
            if(relation==DedaWeeklyFriendRelation.notFriends &&
               onSendExistingFriendRequest!=null)
              OutlinedButton.icon(icon:const Icon(Icons.person_add),
                label:const Text('إرسال طلب صداقة'),
                onPressed:(){
                  Navigator.pop(sheet);
                  onSendExistingFriendRequest!(target);
                }),
            if(relation==DedaWeeklyFriendRelation.pending)
              const Text('طلب الصداقة قيد الانتظار',
                style:TextStyle(color:gold)),
            if(relation==DedaWeeklyFriendRelation.friends)
              const Text('أنتما أصدقاء بالفعل',
                style:TextStyle(color:gold)),
            if(relation==DedaWeeklyFriendRelation.unknown)
              const Text('حالة الصداقة بانتظار التحقق',
                style:TextStyle(color:Colors.white70)),
          ]),
        )),
      );
    }

    return Semantics(
      button:actionable,
      child:InkWell(
        onTap:actionable?showActions:null,
        borderRadius:BorderRadius.circular(12),
        child:Row(mainAxisSize:MainAxisSize.min,children:[
          SizedBox(width:size,height:size,child:portrait),
          const SizedBox(width:6),
          Flexible(child:Column(
            mainAxisSize:MainAxisSize.min,
            crossAxisAlignment:CrossAxisAlignment.start,
            children:[
              Text(verified?data!.displayName:'—',
                maxLines:1,overflow:TextOverflow.ellipsis,
                style:const TextStyle(color:Colors.white)),
              if(!compact)
                Text(verified?data!.activePublicId:'—',
                  maxLines:1,overflow:TextOverflow.ellipsis,
                  textDirection:TextDirection.ltr,
                  style:const TextStyle(color:gold)),
            ],
          )),
        ]),
      ),
    );
  }
}
