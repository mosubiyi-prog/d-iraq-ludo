"""100410: one active-ID authority for all verified/public ID presentations.

Only mutates an ephemeral already-tested 100409 workspace; the original
100409, 100408, wallet, identity account route, weekly scores, purchase,
gift grants, Firestore production rules and Play release stay unchanged.
"""
import argparse, hashlib, json, shutil
from pathlib import Path

ROOT=Path(__file__).resolve().parents[3]
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def one(s,old,new,label):
    if s.count(old)!=1:
        raise ValueError("100410 safety anchor: "+label+" count="+str(s.count(old)))
    return s.replace(old,new,1)

def bind(dest):
    dest=Path(dest).resolve()
    if dest==ROOT or ROOT in dest.parents:
        raise ValueError("NEVER modify success reference")
    meta_file=dest/"internal-build-inputs.json"
    meta=json.loads(meta_file.read_text())
    prior=meta.get("weekly100409SingleVerifiedIdentity",{})
    if meta.get("versionCode")!=100409 or meta.get("package")!="com.diraq.ludo.d_iraq_ludo" or not (
        prior.get("oneStage71ServerConfirmedSource") and
        prior.get("accountKeysUnchanged") and prior.get("xpWalletAndPrizesUnchanged")
    ):
        raise ValueError("verified 100409 signed source required")
    for f,h in meta["sourceHashes"].items():
        if not (dest/f).is_file() or sha(dest/f)!=h:
            raise ValueError("baseline digest drift: "+f)

    source="lib/deda_unified_active_id_100410.dart"
    admin="lib/deda_admin_league_active_id.dart"
    shutil.copy2(ROOT/source,dest/source)
    shutil.copy2(ROOT/"lib/deda_admin_league_unified_id_100410.dart",dest/admin)

    scope_file=dest/"lib/deda_qa32_active_account_scope.dart"
    scope=scope_file.read_text()
    scope=one(scope,
        "import 'deda_verified_active_id_store.dart';",
        "import 'deda_verified_active_id_store.dart';\n"
        "import 'deda_unified_active_id_100410.dart';",
        "one global store in account scope")
    begin=scope.index("  @override\n  Future<DedaQa32ActiveAccountIdentity> readVerified(")
    finish=scope.index("\n}\n\n/// UI wrapper",begin)
    existing=scope[begin:finish]
    if ("readVerified(" not in existing or
        "DedaQa32ActiveAccountIdentity" not in existing or
        "DedaStage71OwnedIdentifierService" not in existing):
        raise ValueError("original Stage71 source unexpectedly changed")
    replacement="""  @override
  Future<DedaQa32ActiveAccountIdentity> readVerified(
      String uid, String original) async {
    // A single shared owner verification per UID+original across profile,
    // own location shares and edit-profile UI. Stage71 authenticates account,
    // gift receipt and selected original route. No per-screen grant inventory.
    if (FirebaseAuth.instance.currentUser?.uid != uid) {
      throw StateError('owner-session-changed');
    }
    await DedaUnifiedActiveId100410.ensureOwner(original);
    if (FirebaseAuth.instance.currentUser?.uid != uid) {
      throw StateError('owner-session-changed-after-verification');
    }
    final result = DedaVerifiedActiveIdStore.read(uid,original);
    if (result == null) throw StateError('active-id-verification-incomplete');
    return DedaQa32ActiveAccountIdentity(
      uid:uid,originalId:original,displayId:result.displayId,
      fixedColor:result.fixedColor,
    );
  }
"""
    scope=scope[:begin]+replacement+scope[finish:]
    scope_file.write_text(scope)

    stage_file=dest/"lib/deda_stage71_free_owned_use_profile.dart"
    stage=stage_file.read_text()
    stage=one(stage,
        "import 'deda_qa32_spark_public_identifier_directory.dart';",
        "import 'deda_qa32_spark_public_identifier_directory.dart';\n"
        "import 'deda_unified_active_id_100410.dart';\n"
        "import 'deda_active_id_public_sync_100409.dart';\n"
        "import 'deda_verified_active_id_store.dart';",
        "unified owner source import")
    use_begin=stage.index("  static Future<void> use(")
    use_finish=stage.index("\n  }\n}",use_begin)
    use=stage[use_begin:use_finish]
    if "String? selectedColor;" not in use or "final persisted = await active(originalId);" not in use:
        raise ValueError("cannot safely reuse verified use colour and readback")
    start=use.index("    // Spark owner publication only after original ID")
    finish=use.index("    if (FirebaseAuth.instance.currentUser?.uid != uid) {\n"
                     "      throw StateError('account-switched-before-use-notifier');",start)
    use=use[:start]+"""    // Stage71 already proved original ownership, selected grant receipt,
    // persisted active selection and reread the server. Update ONE UI cache
    // NOW; all attached profile/league/admin widgets repaint instantly.
    DedaUnifiedActiveId100410.confirmedUse(
      uid,originalId,identifier,selectedColor,
    );
    // The public index is for OTHER viewers and NEVER blocks use() success.
    // Existing Firebase rules independently check canonical active + grant.
    if (DedaQa32SparkPublicIdentifierDirectory.enabled &&
        FirebaseAuth.instance.currentUser?.uid == uid) {
      unawaited(DedaActiveIdPublicSync100409.publishAfterVerifiedRead(
        uid:uid,originalId:originalId,
        activeId:identifier,fixedColor:selectedColor,
      ));
    }
""" + use[finish:]
    stage=stage[:use_begin]+use+stage[use_finish:]
    foil_begin=stage.find("class _DedaStage71ActiveProfileFoilState")
    if not stage.endswith("}\n"):
        raise ValueError("foil not last widget; refuse unsafe replacement")
    foil=r"""class _DedaStage71ActiveProfileFoilState
    extends State<DedaStage71ActiveProfileFoil> {
  StreamSubscription<User?>? _auth;
  void _repaint() { if(mounted) setState(() {}); }
  void _verify() {
    if(DedaUnifiedActiveId100410.uid==null) return;
    unawaited(DedaUnifiedActiveId100410.ensureOwner(widget.originalId)
        .catchError((Object _) {}));
  }

  @override
  void initState() {
    super.initState();
    DedaVerifiedActiveIdStore.revision.addListener(_repaint);
    DedaStage71ActiveIdRefresh.notifier.addListener(_verify);
    if(DedaUnifiedActiveId100410.ready) {
      _auth=FirebaseAuth.instance.authStateChanges().listen((_) {
        if(mounted) {_verify();_repaint();}
      });
    }
    _verify();
  }
  @override
  void didUpdateWidget(covariant DedaStage71ActiveProfileFoil old) {
    super.didUpdateWidget(old);
    if(old.originalId!=widget.originalId) _verify();
  }
  @override
  void dispose() {
    _auth?.cancel();
    DedaVerifiedActiveIdStore.revision.removeListener(_repaint);
    DedaStage71ActiveIdRefresh.notifier.removeListener(_verify);
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    if(Firebase.apps.isEmpty) return widget.fallback;
    final uid=DedaUnifiedActiveId100410.uid;
    final record=uid==null?null:
        DedaVerifiedActiveIdStore.read(uid,widget.originalId);
    if(record==null) {
      // No old ID while premium is unresolved. Await same shared verified
      // ID already used by the owner profile; never launch a second reader.
      return const SizedBox(height:50,child:Center(
          child:Text('جارِ تأكيد الآيدي...',textDirection:TextDirection.rtl)));
    }
    if(record.displayId==widget.originalId) return widget.fallback;
    final cardColor=DedaPremiumIdCardColor.values.firstWhere(
      (c)=>c.name==record.fixedColor,
    );
    return GestureDetector(
      key:const Key('deda_stage71_active_granted_id_hero'),
      onTap:()=>Clipboard.setData(ClipboardData(text:record.displayId)),
      child:DedaPremiumIdCard(
        identifier:record.displayId,color:cardColor,height:50,
      ),
    );
  }
}
"""
    if foil_begin >= 0:
        stage=stage[:foil_begin]+foil
    else:
        print("100410 ASSEMBLED_STAGE71_USES_DIFFERENT_PROFILE_FOIL; core owner source stays single")
    (dest/"lib/deda_stage71_free_owned_use_profile.dart").write_text(stage)

    # Public leaderboard paints through the SAME store: other users' old ID
    # must never be displayed merely because an alias read was delayed.
    league_file=dest/"lib/deda_weekly_leaderboard_page.dart"
    league=league_file.read_text()
    league=one(league,
        "import 'deda_weekly_league_clock.dart';",
        "import 'deda_weekly_league_clock.dart';\n"
        "import 'deda_unified_active_id_100410.dart';",
        "unified public league import")
    anchor="  Widget identity(DedaWeeklyLeaderboardRow? row,"
    if league.count(anchor)!=1:
        raise ValueError("league identity widget missing")
    league=league.replace(anchor,
        """  // The weekly backend's participant UID is derived from the immutable
  // score original ID; it is NOT an active display alias.
  String? _originalFromWeekly(DedaWeeklyLeaderboardRow? row) {
    final participant=row?.accountUid ?? '';
    const prefix='weekly-user-DEDA-';
    if(!participant.startsWith(prefix)) return null;
    final candidate='@DEDA-' + participant.substring(prefix.length);
    return DedaUnifiedActiveId100410.valid(candidate) ? candidate : null;
  }

"""+anchor,1)
    original="""child: fitted(details?.activePublicId ?? '—',
                       size: 11, color: silver, weight: FontWeight.w500,
                       ltr: true),"""
    target="""child: _originalFromWeekly(row) == null
                    ? fitted(details?.activePublicId ?? '—',
                        size: 11, color: silver, weight: FontWeight.w500,
                        ltr: true)
                    : DedaUnifiedActiveIdLabel100410(
                        originalId:_originalFromWeekly(row)!,
                        style:TextStyle(fontSize:11,color:silver)), """
    league=one(league,original,target,
        "top10 public label uses common ID authority")
    league=one(league,
        """fitted(profile(row)?.activePublicId ?? '—',
                         size: 11 * scale, color: silver, ltr: true),""",
        """_originalFromWeekly(row) == null
                      ? fitted(profile(row)?.activePublicId ?? '—',
                          size: 11 * scale, color: silver, ltr: true)
                      : DedaUnifiedActiveIdLabel100410(
                          originalId:_originalFromWeekly(row)!,
                          style:TextStyle(fontSize:11*scale,color:silver)),""",
        "podium ID uses common ID authority")
    league_file.write_text(league)

    # Public friend profile previously displayed the original ID as a
    # fallback and ran its OWN distinct style/Cloud Functions read. Keep all
    # existing verified artwork but drive it from the SAME shared projection.
    friend_file="lib/deda_stage50_verified_friend_ink_badge.dart"
    friend=(dest/friend_file).read_text()
    friend=one(friend,
        "import 'package:firebase_auth/firebase_auth.dart';",
        "import 'package:firebase_auth/firebase_auth.dart';\n"
        "import 'package:firebase_core/firebase_core.dart';",
        "friend safe tests with uninitialized Firebase")
    friend=one(friend,
        "import 'deda_qa32_spark_public_identifier_directory.dart';",
        "import 'deda_qa32_spark_public_identifier_directory.dart';\n"
        "import 'deda_unified_active_id_100410.dart';",
        "friend unified display import")
    begin=friend.index("class DedaStage50VerifiedFriendInkBadge extends StatefulWidget")
    finish=friend.index("/// Use the SAME full Crown/Jewel ID artwork",begin)
    friend=friend[:begin]+"""class DedaStage50VerifiedFriendInkBadge extends StatelessWidget {
  const DedaStage50VerifiedFriendInkBadge({
    super.key, required this.originalId, required this.fallback,
    this.premiumCardBuilder,
  });
  final String originalId;
  final Widget fallback;
  final Widget Function(DedaStage50PublicIdStyle verified)? premiumCardBuilder;

  @override
  Widget build(BuildContext context) {
    if (!DedaStage50PublicIdStyleBridge.enabled ||
        Firebase.apps.isEmpty) return fallback;
    return DedaUnifiedActiveIdBuilder100410(
      originalId:originalId,
      builder:(context,active) {
        final proof=DedaUnifiedActiveId100410.proof(originalId);
        if(proof==null || active==null) {
          // Never substitute the potentially retired original ID while
          // waiting for server-authorized premium proof.
          return const SizedBox(height:20,child:Text(
              'جارِ تأكيد الآيدي...',textDirection:TextDirection.rtl));
        }
        if(active==originalId) return fallback;
        final verified=DedaStage50PublicIdStyle(
          requestedId:originalId,displayId:proof.displayId,
          permanentColor:proof.fixedColor,
        );
        if (premiumCardBuilder != null && proof.fixedColor != null) {
          return DedaStage50PremiumPublicCard(
            originalId:originalId,verified:verified,
            fallback:const SizedBox.shrink(),
            builder:premiumCardBuilder!,
          );
        }
        return DedaStage50FriendIdInkText(
          originalId:originalId,verified:verified,
          fallback:const SizedBox.shrink(),
        );
      },
    );
  }
}

"""+friend[finish:]
    (dest/friend_file).write_text(friend)

    # Location shares must keep immutable original IDs for routing but show
    # the current active alias, including at the recipient's stored cards.
    main_file=dest/"lib/main.dart"
    main=main_file.read_text()
    main=one(main,
        "import 'deda_verified_active_id_store.dart';",
        "import 'deda_verified_active_id_store.dart';\n"
        "import 'deda_unified_active_id_100410.dart';",
        "shared display labels in main location share UI")
    main=one(main,
        """                          _idCard(
                            title: dedaText(
                              'معرفي الشخصي',
                              'My personal ID',
                            ),
                            id: _personalId,
                            icon: Icons.person,
                          ),""",
        """                          DedaUnifiedActiveIdBuilder100410(
                            originalId:_personalId,
                            builder:(context,active) => active==null
                              ? const SizedBox(height:48,child:Center(
                                  child:Text('جارِ تأكيد الآيدي...',
                                      textDirection:TextDirection.rtl)))
                              : _idCard(
                                  title:dedaText('معرفي الشخصي','My personal ID'),
                                  id:active,icon:Icons.person),
                          ),""",
        "location-share my personal ID displays only selected verified alias")
    main=one(main,
        """                       Text(
                         senderId,
                         textDirection: TextDirection.ltr,
                         style: const TextStyle(
                           color: Color(0xFF5C635D),
                           fontWeight: FontWeight.w700,
                         ),
                       ),""",
        """                       DedaUnifiedActiveId100410.valid(senderId)
                         ? DedaUnifiedActiveIdLabel100410(
                             originalId:senderId,
                             style:const TextStyle(
                               color:Color(0xFF5C635D),
                               fontWeight:FontWeight.w700))
                         : Text(senderId,
                             textDirection:TextDirection.ltr,
                             style:const TextStyle(
                               color:Color(0xFF5C635D),
                               fontWeight:FontWeight.w700)),
""",
        "recipient location share shows sender's active ID, not historical original")
    main_file.write_text(main)

    for path in (source,admin,"lib/deda_qa32_active_account_scope.dart",
                 "lib/deda_stage71_free_owned_use_profile.dart",
                 "lib/deda_weekly_leaderboard_page.dart","lib/main.dart",
                 friend_file):
        meta["sourceHashes"][path]=sha(dest/path)
    meta["versionCode"]=100410
    meta["weekly100410UnifiedActiveId"]={
      "oneUidScopedOwnerStore":True,
      "sameOwnerStage71VerificationReused":True,
      "directSelectedRegistryInsteadOfWholeInventory":True,
      "useConfirmedImmediatelyAfterServerReadback":True,
      "publicProjectionNonBlockingAndRuleProtected":True,
      "oneServerProjectionWatcherPerOriginalAcrossScreens":True,
      "profileFoilNoIndependentActiveAndOwnedReader":True,
      "weeklyPodiumAndTop10SharedDisplay":True,
      "adminUsesSharedDisplay":True,
      "locationSenderAndRecipientUseSameVerifiedDisplay":True,
      "friendProfilesUseUnifiedServerVerifiedAlias":True,
      "originalKeysNeverReplaced":True,
      "noXpDiamondOrRewardWrites":True,
      "phoneTestPending":True,
    }
    meta_file.write_text(json.dumps(meta,ensure_ascii=False,indent=2)+"\n")

if __name__=="__main__":
    p=argparse.ArgumentParser()
    p.add_argument("workspace",type=Path)
    bind(p.parse_args().workspace)
    print("100410_ONE_ID_AUTHORITY_BIND_COMPLETED_NO_PLAY")
