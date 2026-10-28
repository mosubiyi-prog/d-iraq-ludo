"use strict";
/**
 * ORIGINAL APPROVED DEDA TASK: "Add a friend after request ACCEPTED".
 * PRIVATE real Firestore emulator ONLY. Captures a signed-looking but
 * explicitly NON-authoritative proof of the actual server-side transition,
 * NEVER credits legacy +5 points/+20 XP/+10 social coins/weekly XP/diamonds.
 *
 * Must be invoked only by a trusted server onUpdate with before/after
 * snapshots, NEVER by a callable accepting arbitrary client friend IDs.
 * The original task's immutable claim identifier is "long_trip" following
 * the owner-approved 100383 task remapping (NOT old road-trip behavior).
 */
const core=require("../tools/app_stability/progress_archive/reconcile-core.cjs");
const {PROJECT,dayInIraq}=require("./deda_weekly_xp_atomic_shadow_issuer_NOT_EXPORTED.js");
const {clockState}=require("./deda_weekly_stage31_frozen_league_winner_card_NOT_EXPORTED.js");
const TASK="long_trip";
const ACTION="friend_accepted";
const ROOT="deda_weekly_private_original_friend_accepted_actions";
const ISSUER="private_original_friend_accepted_transition_emulator_only_v1";
const ACCOUNT=/^[0-9]{10,16}$/;
const UID=/^[A-Za-z0-9_-]{1,128}$/;
const PUBLIC=/^@DEDA-[A-Z0-9]{6}$/;
function deny(code){throw Error("DEDA_ORIGINAL_FRIEND_ACCEPTED_"+code);}
function goodMs(v){return Number.isSafeInteger(v)&&v>=0;}
function ms(v){const x=v?.toMillis?.();if(!goodMs(x))deny("invalid_firestore_timestamp");return x;}
function record(doc,label){
 if(!doc?.exists||typeof doc.data!=="function")deny("missing_"+label);
 const d=doc.data();if(!d||typeof d!=="object"||Array.isArray(d))deny("invalid_"+label);
 return d;
}
function emulator(db){
 if(process.env.GCLOUD_PROJECT!==PROJECT||!process.env.FIRESTORE_EMULATOR_HOST||
    typeof db?.doc!=="function"||typeof db?.runTransaction!=="function")
  deny("emulator_only");
}
function originalClaim(accountKey,dayId){
 const receipt=core.parseReceipt({
  format:1,accountKey,source:"task-claim-v1",
  sourceId:"daily-task|"+dayId+"|"+TASK,kind:"award",
  delta:{points:5,coins:10,xp:20,earnedDiamonds:0},
 },accountKey);
 return Object.freeze({receipt,eventKey:core.eventKey(receipt)});
}
const stable=["pairKey","members","requesterUid","recipientUid",
 "requesterPublicId","recipientPublicId","requesterName","recipientName","createdAt"];
function sameIdentity(before,after){
 return stable.every(k=>k==="members"
  ? Array.isArray(before[k])&&Array.isArray(after[k])&&
    before[k].length===2&&after[k].length===2&&
    before[k].every((s,i)=>s===after[k][i])
  : k==="createdAt"
    ? ms(before[k])===ms(after[k])
    : before[k]===after[k]);
}
async function recordOriginalAcceptedFriendAction({
 db,relationId,before,after,firstOpenMs,serverNowMs,
}){
 emulator(db);
 if(!relationId||relationId.length>260||
    !goodMs(serverNowMs)||!before||!after||
    before.status!=="pending"||after.status!=="accepted"||
    before.respondedAt!==undefined||!sameIdentity(before,after))
  deny("trusted_original_pending_to_accepted_transition_required");
 const clock=clockState({firstOpenMs,serverNowMs});
 if(!clock.current||!["active","frozen"].includes(clock.phase))
  deny("week_not_active_or_frozen");
 const from=after.requesterUid,to=after.recipientUid;
 if(!UID.test(from||"")||!UID.test(to||"")||from===to||
    !PUBLIC.test(after.requesterPublicId||"")||
    !PUBLIC.test(after.recipientPublicId||"")||
    after.requesterPublicId===after.recipientPublicId||
    !Array.isArray(after.members)||after.members.length!==2||
    after.members[0]!==from||after.members[1]!==to||
    relationId!==[from,to].sort().join("__")||
    after.pairKey!==relationId)
  deny("canonical_pair_or_member_mismatch");
 const approvedAt=ms(after.respondedAt),updatedAt=ms(after.updatedAt),
   createdAt=ms(after.createdAt),pendingAt=ms(before.updatedAt);
 if(approvedAt!==updatedAt||pendingAt>approvedAt||
    createdAt>pendingAt||approvedAt>serverNowMs||
    serverNowMs-approvedAt>300000||
    approvedAt<clock.current.openedAtMs||
    approvedAt>=clock.current.nextOpenMs||
    dayInIraq(approvedAt)!==dayInIraq(serverNowMs))
  deny("untrusted_original_acceptance_timing");
 return db.runTransaction(async tx=>{
  const live=record(await tx.get(db.doc("deda_friendships/"+relationId)),
    "accepted_original_relation");
  if(live.status!=="accepted"||!sameIdentity(after,live)||
     ms(live.respondedAt)!==approvedAt||
     ms(live.updatedAt)!==updatedAt)
   deny("accepted_relation_modified_or_replayed");
  const [userA,userB,idA,idB,sessionA,sessionB]=await Promise.all([
   tx.get(db.doc("users/"+from)),tx.get(db.doc("users/"+to)),
   tx.get(db.doc("deda_share_ids/"+after.requesterPublicId)),
   tx.get(db.doc("deda_share_ids/"+after.recipientPublicId)),
   tx.get(db.doc("deda_sessions/"+from)),tx.get(db.doc("deda_sessions/"+to)),
  ]);
  const a=record(userA,"requester_user"),b=record(userB,"recipient_user"),
    ida=record(idA,"requester_id"),idb=record(idB,"recipient_id"),
    sa=record(sessionA,"requester_session"),
    sb=record(sessionB,"recipient_session");
  if(!ACCOUNT.test(a.accountKey||"")||
     !ACCOUNT.test(b.accountKey||"")||
     a.accountKey===b.accountKey||
     a.sharePersonalId!==after.requesterPublicId||
     b.sharePersonalId!==after.recipientPublicId||
     a.uid!=null&&a.uid!==from||
     b.uid!=null&&b.uid!==to||
     ida.kind!=="personal"||ida.active!==true||ida.ownerUid!==from||
     idb.kind!=="personal"||idb.active!==true||idb.ownerUid!==to||
     sa.uid!==from||sa.accountKey!==a.accountKey||
     sb.uid!==to||sb.accountKey!==b.accountKey||
     !UID.test(sa.installId||"")||!UID.test(sb.installId||""))
    deny("original_account_or_public_id_not_owned");
  const [profileA,profileB]=await Promise.all([
   tx.get(db.doc("deda_account_profiles/"+a.accountKey)),
   tx.get(db.doc("deda_account_profiles/"+b.accountKey)),
  ]);
  const pa=record(profileA,"account_profile_a"),
    pb=record(profileB,"account_profile_b");
  if(pa.accountKey!==a.accountKey||pb.accountKey!==b.accountKey||
     !Array.isArray(pa.trustedInstallIds)||
     !Array.isArray(pb.trustedInstallIds)||
     !pa.trustedInstallIds.includes(sa.installId)||
     !pb.trustedInstallIds.includes(sb.installId))
   deny("untrusted_original_device");
  const dayId=dayInIraq(approvedAt);
  const participants=[{uid:from,accountKey:a.accountKey},
   {uid:to,accountKey:b.accountKey}];
  const events=participants.map(p=>({...p,...originalClaim(p.accountKey,dayId)}));
  const prior=await Promise.all(events.map(e=>tx.get(db.doc(ROOT+"/"+e.eventKey))));
  for(let i=0;i<events.length;i++)if(prior[i].exists){
   const x=record(prior[i],"old_friend_event"),e=events[i];
   if(x.issuer!==ISSUER||x.emulatorOnly!==true||
      x.canAuthorizeProduction!==false||
      x.accountKey!==e.accountKey||x.taskId!==TASK||
      x.approvedAction!==ACTION||x.dayId!==dayId||
      x.eventKey!==e.eventKey||x.xpGranted!==0||
      x.leagueXpGranted!==0||x.diamondsGranted!==0||
      !UID.test(x.originalRelationId?.split("__")[0]||""))
    deny("tampered_old_task_action_proof");
  }
  // All reads before any write. Both sides receive at most one action proof
  // per Baghdad day; no credit, even if the friend pair accepts again.
  for(let i=0;i<events.length;i++){
   if(prior[i].exists)continue;
   const e=events[i];
   tx.create(db.doc(ROOT+"/"+e.eventKey),{
    issuer:ISSUER,emulatorOnly:true,canAuthorizeProduction:false,
    originalRelationId:relationId,approvedAction:ACTION,
    accountKey:e.accountKey,taskId:TASK,dayId,eventKey:e.eventKey,
    approvedAtMs:approvedAt,verifiedAtMs:serverNowMs,
    originalLocalClaimAwarded:"UNKNOWN_REQUIRES_MIGRATION_REVIEW",
    sourceVerifiedAs:"original_server_observed_friend_accepted_transition_only",
    pointsGranted:0,coinsGranted:0,xpGranted:0,
    leagueXpGranted:0,diamondsGranted:0,
   });
  }
  return Object.freeze({
   outcome:prior.every(x=>x.exists)?"already_verified":"private_accepted_action_verified",
   proofsAdded:prior.filter(x=>!x.exists).length,
   levelXpAdded:0,weeklyXpAdded:0,diamondsAdded:0,
   emulatorOnly:true,canAuthorizeProduction:false,
  });
 });
}
module.exports=Object.freeze({
 PROJECT,TASK,ACTION,ROOT,ISSUER,originalClaim,recordOriginalAcceptedFriendAction,
});
