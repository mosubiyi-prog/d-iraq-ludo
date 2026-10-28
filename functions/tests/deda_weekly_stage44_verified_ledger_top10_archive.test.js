"use strict";
const test=require("node:test"),assert=require("node:assert/strict");
const crypto=require("node:crypto");
const {initializeApp,deleteApp}=require("firebase-admin/app");
const {getFirestore}=require("firebase-admin/firestore");
const core=require("../../tools/app_stability/progress_archive/reconcile-core.cjs");
const {clockState,windowFor,previewFrozenResult,previewWinnerCard,
  SOURCE,PRIZES}=require(
    "../deda_weekly_stage31_frozen_league_winner_card_NOT_EXPORTED.js");
const {receiptFor,ROOT:SOURCE_ROOT,ISSUER:SOURCE_ISSUER}=require(
  "../deda_weekly_stage42_server_share_action_producer_NOT_EXPORTED.js");
const {ROOT:EPOCH_ROOT,ISSUER:EPOCH_ISSUER}=require(
  "../deda_weekly_stage43_reviewed_cutover_epoch_NOT_EXPORTED.js");
const {PROJECT,VERIFIED_ROOT,LEAGUE_ROOT,profilePath,
  monthOfFinalEligibleInstant,previewPrivateTopTenFromAppliedXp:project,
  previewPrivateMonthlyHistory:history}=require(
    "../deda_weekly_stage44_verified_ledger_top10_archive_NOT_EXPORTED.js");
const {dayInIraq}=require("../deda_weekly_xp_atomic_shadow_issuer_NOT_EXPORTED.js");
if(process.env.GCLOUD_PROJECT!==PROJECT||!process.env.FIRESTORE_EMULATOR_HOST)
  throw Error("STAGE44_ONLY_LOCAL_FIRESTORE_EMULATOR");
const app=initializeApp({projectId:PROJECT},"deda-stage44");
const db=getFirestore(app);
const FIRST=Date.UTC(2026,9,27,3); // 06:00 Baghdad
const WEEK=windowFor(FIRST,0);
const FROZEN=WEEK.closeAtMs+60000;
const RELEASE=WEEK.nextOpenMs;
const SECRET=Buffer.alloc(32,0x41);
const ACCOUNTS=Array.from({length:12},(_,i)=>
  "0770123"+String(4500+i).padStart(4,"0"));
const profile=(a,i)=>({
  issuer:"stage44_private_profile_fixture_only",
  emulatorOnly:true,accountKey:a,
  displayName:"مشارك ديدا "+String(i+1),
  activePublicId:"@DEDA-"+String(i+1).padStart(6,"0"),
  level:i+1,
});
function args(now=FROZEN,index=0,additional={}){
  return {db,firstOpenMs:FIRST,weekIndex:index,serverNowMs:now,
    backendSecret:SECRET,...additional};
}
function hash(str){return crypto.createHash("sha256").update(str).digest("hex");}
function fixture(account,at,seq){
  const {receipt,eventKey}=receiptFor(account,dayInIraq(at));
  const initial=core.parseReceipt({format:1,accountKey:account,
    source:"legacy-baseline-v1",
    sourceId:"legacy-review|stage44-migration-00000001|"+
      hash("legacy|"+account),
    kind:"baseline",
    delta:{points:30,coins:20,xp:60,earnedDiamonds:15}},account);
  return {receipt,eventKey,baseline:initial,
    baselineKey:core.eventKey(initial),time:at,seq};
}
async function seed(){
  const batch=db.batch();
  for(let i=0;i<ACCOUNTS.length;i++){
    const account=ACCOUNTS[i];
    const times=[FIRST+3600000+i*45000];
    if(i<2)times.push(FIRST+86400000+3600000+i*45000);
    let state=null;
    let baselineKey=null;
    for(let j=0;j<times.length;j++){
      const {receipt,eventKey,baseline,baselineKey:key,time}=fixture(account,times[j],j);
      if(state===null){state=core.applyEvent(null,baseline);baselineKey=key;}
      state=core.applyEvent(state,receipt);
      batch.set(db.doc("deda_verified_progress/"+account+
        "/events/"+eventKey),{
          format:1,accountKey:account,eventKey,receipt,receiptId:eventKey,
          appliedVersion:state.version,afterBalances:state.balances,
          createdAtMs:time+100,
          emitter:"stage43_private_reviewed_cutover_atomic_emulator_only"
      });
      batch.set(db.doc("deda_progress_receipts/"+account+
        "/events/"+eventKey),receipt);
      batch.set(db.doc(SOURCE_ROOT+"/"+eventKey),{
        issuer:SOURCE_ISSUER,emulatorOnly:true,
        canAuthorizeProduction:false,serverVerifiedAction:true,
        accountKey:account,dayId:dayInIraq(time),
        taskId:"share_personal_location",eventKey,
        originalShareId:"ABCDE"+String(i).padStart(15,"0"),
        originalSenderUid:"stage44_sender_"+i,
        sourceCreatedAtMs:time,sourceVerifiedAtMs:time+100,
        originalLocalClaimAwarded:"UNKNOWN_REQUIRES_MIGRATION_REVIEW",
        verifiedAs:"original_cross_account_share_action_only",
        coinsGranted:0,xpGranted:0,pointsGranted:0,diamondsGranted:0,
      });
      batch.set(db.doc(LEAGUE_ROOT+"/"+WEEK.weekId+"_"+eventKey),{
        emulatorOnly:true,issuer:SOURCE_ISSUER,accountKey:account,
        weekId:WEEK.weekId,dayId:dayInIraq(time),
        eventKey,taskId:"share_personal_location",amount:20,
        createdAtMs:time+100,
      });
    }
    batch.set(db.doc("deda_verified_progress/"+account),state);
    const migrationId="stage44-migration-00000001";
    batch.set(db.doc("deda_progress_migrations/"+account),{
      format:1,accountKey:account,migrationId,
      phase:"cutover-complete",
      evidenceDigest:hash("legacy|"+account),
      baselineEventKey:baselineKey,
      settlementId:"stage44-settlement-00000001",
    });
    batch.set(db.doc(EPOCH_ROOT+"/"+account),{
      issuer:EPOCH_ISSUER,emulatorOnly:true,
      canAuthorizeProduction:false,accountKey:account,
      migrationId,evidenceDigest:hash("legacy|"+account),
      baselineEventKey:baselineKey,
      settlementId:"stage44-settlement-00000001",
      phase:"reviewed-server-only-private-fixture",
      pendingLocalClaims:0,pendingPurchases:0,pendingReservations:0,
      realOldApkRevocationVerified:false,effectiveAtMs:FIRST-60000
    });
    batch.set(db.doc(profilePath(account,SECRET)),profile(account,i));
    batch.set(db.doc("users/"+account+"/wallet/live_user"),{
      originalDiamonds:999+i,items:["frame-"+i],premiumId:"@DEDA-OWN"+i
    });
  }
  batch.set(db.doc("deda_admin_diamond_wallets/gm"),
    {diamonds:1000000,issuer:"do_not_touch"});
  await batch.commit();
}
test.before(async()=>{await seed();});
test.after(async()=>{
 // Prevent Stage44's 14 synthetic receipts from contaminating the
 // independent Stage43 legacy test that checks collection size === 1.
 // No live/project deletion: GCLOUD_PROJECT is the fixed emulator project.
 const own=await db.collection(LEAGUE_ROOT)
   .where("weekId","==",WEEK.weekId).get();
 const batch=db.batch();
 for(const snapshot of own.docs)batch.delete(snapshot.ref);
 if(own.size)await batch.commit();
 await deleteApp(app);
});
test("read ONLY correct original +5/+10/+20 applied ledger receipts -> top 10",async()=>{
 const result=await project(args());
 assert.equal(result.topTen.length,10);
 assert.equal(result.allCompetitorCount,12);
 assert.equal(result.state,"frozen");
 assert.deepEqual(result.topTen.map(r=>r.place),
   Array.from({length:10},(_,i)=>i+1));
 assert.equal(result.topTen[0].weeklyXp,40);
 assert.equal(result.topTen[1].weeklyXp,40);
 assert.equal(result.topTen[2].weeklyXp,20);
 assert.deepEqual(result.topTen.map(r=>r.plannedDiamonds),PRIZES);
 assert.equal(result.plannedTotalDiamonds,370);
 assert.equal(result.actuallyCreditedDiamonds,0);
 assert.equal(result.previewOnly,true);
 assert.equal(result.productionReady,false);
 assert.equal(JSON.stringify(result.topTen).includes("0770123"),false);
 assert.equal(result.archiveMonthId,"2026-11");
});
test("00:00–06:00 freezes EXACT same result; next week opens at 06",async()=>{
 const first=await project(args(FROZEN));
 const later=await project(args(RELEASE-1000));
 assert.deepEqual(first.topTen,later.topTen);
 assert.deepEqual(first.snapshot,later.snapshot);
 const p=previewFrozenResult({firstOpenMs:FIRST,weekIndex:0,
   serverNowMs:FROZEN,snapshot:first.snapshot});
 assert.equal(p.rows.length,10);
 assert.equal(p.rows[1].place,2);
 assert.equal(p.releaseAtMs,RELEASE);
 const next=await project(args(RELEASE+1000,1));
 assert.equal(next.topTen.length,0);
 assert.equal(next.state,"active");
 assert.equal(next.snapshot,null);
 const previous=await project(args(RELEASE+1000));
 assert.deepEqual(previous.topTen,first.topTen);
});
test("approved winner card copy is tied to after 06, not name/DEDA ID",async()=>{
 const preview=await project(args());
 const second=preview.topTen[1];
 const gift={source:SOURCE,emulatorOnly:true,
   weekId:preview.weekId,participantId:second.participantId,
   place:2,diamonds:100,status:"pending"};
 const early=previewWinnerCard({firstOpenMs:FIRST,weekIndex:0,
   serverNowMs:FROZEN,snapshot:preview.snapshot,
   viewerParticipantId:second.participantId,giftReceipt:gift});
 assert.equal(early,null);
 const card=previewWinnerCard({firstOpenMs:FIRST,weekIndex:0,
   serverNowMs:RELEASE+1000,snapshot:preview.snapshot,
   viewerParticipantId:second.participantId,giftReceipt:gift});
 assert.equal(card.prizeText,"100 💎");
 assert.equal(card.rankText.includes("الثاني"),true);
 assert.equal(card.title,"تهانينا يا بطل DEDA!");
 assert.equal(JSON.stringify(card).includes(second.activePublicId),false);
 assert.equal(JSON.stringify(card).includes(second.displayName),false);
 assert.equal(card.creditsMade,0);
});
test("GM private month stores 10 ranks, top 3, and no payouts",async()=>{
 const frozen=await project(args());
 const view=history({monthId:"2026-11",
   closedWeekPreviews:[frozen],serverNowMs:RELEASE});
 assert.equal(view.records.length,1);
 assert.equal(view.records[0].topTen.length,10);
 assert.equal(view.records[0].firstThree.length,3);
 assert.deepEqual(view.records[0].firstThree.map(x=>x.place),[1,2,3]);
 assert.equal(view.actuallyCreditedDiamonds,0);
 assert.equal(view.managerAuthorizationVerified,false);
 assert.equal(view.readOnly,true);
 assert.throws(()=>history({monthId:"2026-10",
   closedWeekPreviews:[frozen],serverNowMs:RELEASE}),
   /invalid_closed_snapshot/);
 assert.throws(()=>history({monthId:"2026-11",
   closedWeekPreviews:[frozen,frozen],serverNowMs:RELEASE}),
   /invalid_closed_snapshot/);
});
test("missing original approved XP event OR migration invalidates whole ranking",async()=>{
 const account=ACCOUNTS[0],time=FIRST+3600000;
 const {eventKey}=receiptFor(account,dayInIraq(time));
 const ref=db.doc("deda_progress_receipts/"+account+"/events/"+eventKey);
 const original=(await ref.get()).data();
 await ref.delete();
 await assert.rejects(project(args()),/orphan_league_receipt/);
 await ref.set(original);
 const epoch=db.doc(EPOCH_ROOT+"/"+account);
 await epoch.update({pendingLocalClaims:1});
 await assert.rejects(project(args()),/cutover_or_verified_progress_conflict/);
 await epoch.update({pendingLocalClaims:0});
});
test("fake source proof, wrong 10 coins, or changed receipt cannot rank",async()=>{
 const account=ACCOUNTS[2],time=FIRST+3600000+2*45000;
 const {eventKey}=receiptFor(account,dayInIraq(time));
 const proof=db.doc(SOURCE_ROOT+"/"+eventKey);
 const originalProof=(await proof.get()).data();
 await proof.update({originalLocalClaimAwarded:"NO_CLAIM_YET"});
 await assert.rejects(project(args()),/unverified_applied_original_event/);
 await proof.set(originalProof);
 const pair=db.doc("deda_progress_receipts/"+account+"/events/"+eventKey);
 const receipt=(await pair.get()).data();
 await pair.update({"delta.coins":0});
 await assert.rejects(project(args()),/receipt_not_applied_to_original_progress/);
 await pair.set(receipt);
});
test("a receipt after 00:00 close cannot be backdated into league",async()=>{
 const account=ACCOUNTS[3],time=FIRST+3600000+3*45000;
 const {eventKey}=receiptFor(account,dayInIraq(time));
 const proof=db.doc(SOURCE_ROOT+"/"+eventKey);
 const saved=(await proof.get()).data();
 await proof.update({sourceCreatedAtMs:WEEK.closeAtMs+1000});
 await assert.rejects(project(args()),/unverified_applied_original_event/);
 await proof.set(saved);
});
test("read-only preview leaves all ORIGINAL user wallets, diamonds and manager unchanged",async()=>{
 await project(args());
 for(let i=0;i<ACCOUNTS.length;i++){
  const original=(await db.doc("users/"+ACCOUNTS[i]+"/wallet/live_user").get()).data();
  assert.equal(original.originalDiamonds,999+i);
  assert.deepEqual(original.items,["frame-"+i]);
 }
 const gm=(await db.doc("deda_admin_diamond_wallets/gm").get()).data();
 assert.deepEqual(gm,{diamonds:1000000,issuer:"do_not_touch"});
});
test("no user overrides or missing backend private secret, no real production",async()=>{
 await assert.rejects(project(args(FROZEN,0,{userCoins:9999})),
   /client_override_or_clock/);
 await assert.rejects(project(args(FROZEN,0,{backendSecret:Buffer.alloc(8)})),
   /private_emulator_only/);
 const projectBefore=process.env.GCLOUD_PROJECT;
 process.env.GCLOUD_PROJECT="deda-25b88";
 try{await assert.rejects(project(args()),/private_emulator_only/);}
 finally{process.env.GCLOUD_PROJECT=projectBefore;}
});
