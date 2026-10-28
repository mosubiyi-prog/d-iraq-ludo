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
const {ROOT:GIFTS,ISSUER:GIFT_ISSUER,privateToken,giftId,
  preparePrivateFrozenWeek:prepare,
  simulateIssuePrivateGiftInbox:issue,
  previewPrivateGiftInbox:inbox,
  simulateRedeemPrivateGift:redeem}=require(
    "../deda_weekly_stage45_private_gifts_inbox_atomic_NOT_EXPORTED.js");

if(process.env.GCLOUD_PROJECT!==PROJECT||!process.env.FIRESTORE_EMULATOR_HOST)
  throw Error("STAGE44_ONLY_LOCAL_FIRESTORE_EMULATOR");
const app=initializeApp({projectId:PROJECT},"deda-stage45");
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


const UID1="stage45_first_account_phone_one";
const UID2="stage45_first_account_phone_two";
const UID3="stage45_second_place_phone";
const TIME=RELEASE+3600000;
function request(uid,data={}){
 return {auth:{uid,token:{firebase:{sign_in_provider:"password"}}},
   app:{appId:"1:000000:android:stage45-private-qa"},data};
}
function makeArgs(now=TIME,more={}){return args(now,0,more);}
async function seedIdentity(uid,account,install){
 const batch=db.batch();
 batch.set(db.doc("users/"+uid),{uid,accountKey:account});
 batch.set(db.doc("deda_sessions/"+uid),{uid,accountKey:account,installId:install});
 batch.set(db.doc("deda_weekly_identity_attestations/"+uid),{
   issuer:"privileged_identity_verifier_v1",state:"verified",
   uid,accountKey:account,installId:install,
   issuedAtMs:RELEASE-60000,expiresAtMs:TIME+3600000
 });
 await batch.commit();
}
test.before(async()=>{
 await seed();
 await seedIdentity(UID1,ACCOUNTS[0],"stage45_phone_one");
 await seedIdentity(UID2,ACCOUNTS[0],"stage45_phone_two");
 await seedIdentity(UID3,ACCOUNTS[1],"stage45_second_phone");
 await db.doc("deda_account_profiles/"+ACCOUNTS[0]).set({
   accountKey:ACCOUNTS[0],trustedInstallIds:["stage45_phone_one","stage45_phone_two"]
 });
 await db.doc("deda_account_profiles/"+ACCOUNTS[1]).set({
   accountKey:ACCOUNTS[1],trustedInstallIds:["stage45_second_phone"]
 });
});
test.after(async()=>{
 // Avoid polluting Stage43/44 tests sharing the emulator environment.
 const own=await db.collection(LEAGUE_ROOT).where("weekId","==",WEEK.weekId).get();
 if(own.size){
   const batch=db.batch();
   own.docs.forEach(x=>batch.delete(x.ref));
   await batch.commit();
 }
 await deleteApp(app);
});
test("BEFORE 06:00 no weekly sealed gift or inbox payout, original untouched",async()=>{
 await assert.rejects(prepare(makeArgs(RELEASE-1)),/not_released_0600_baghdad/);
 await assert.rejects(issue(makeArgs(RELEASE-1)),/not_released_0600_baghdad/);
 await assert.rejects(issue(makeArgs()),/verified_week_not_sealed/);
 assert.equal((await db.collection(GIFTS.inbox).get()).size,0);
 assert.equal((await db.collection(GIFTS.shadowWallet).get()).size,0);
});
test("Seal Stage44 applied XP top-ten only AFTER 06, not from arbitrary client list",async()=>{
 const first=await prepare(makeArgs());
 const again=await prepare(makeArgs(TIME+1000));
 assert.equal(first.outcome,"private_week_sealed");
 assert.equal(first.winnerCount,10);
 assert.equal(again.outcome,"already_sealed");
 const s=(await db.doc(GIFTS.snapshot+"/"+WEEK.weekId).get()).data();
 assert.equal(s.rows.length,10);
 assert.deepEqual(s.rows.map(x=>x.amount),PRIZES);
 assert.equal(s.rows.reduce((n,x)=>n+x.amount,0),370);
 await assert.rejects(prepare(makeArgs(TIME,{winners:[ACCOUNTS[11]]})),
   /client_supplied_parameters/);
});
test("Issue ten PENDING هداياي only once; simultaneous re-run never doubles",async()=>{
 const [a,b]=await Promise.all([issue(makeArgs()),issue(makeArgs())]);
 assert.deepEqual([a.outcome,b.outcome].sort(),
   ["already_issued","private_pending_gifts_issued"]);
 assert.equal(a.pendingDiamondsIssued+b.pendingDiamondsIssued,370);
 const inboxDocs=await db.collection(GIFTS.inbox).get();
 assert.equal(inboxDocs.size,10);
 const gifts=inboxDocs.docs.map(x=>x.data());
 assert.deepEqual(gifts.map(x=>x.amount).sort((x,y)=>y-x),[150,100,50,10,10,10,10,10,10,10]);
 assert.equal(gifts.every(x=>x.status==="pending"),true);
 assert.equal((await db.collection(GIFTS.shadowWallet).get()).size,0);
 assert.equal((await db.doc("deda_admin_diamond_wallets/gm").get()).data().diamonds,1000000);
 assert.equal((await db.doc("users/"+ACCOUNTS[0]+"/wallet/live_user").get()).data().originalDiamonds,999);
 const nonexistent=giftId(SECRET,WEEK.weekId,ACCOUNTS[11]);
 assert.equal((await db.doc(GIFTS.inbox+"/"+nonexistent).get()).exists,false);
});
test("Different verified phones on same account see ONE gift in هداياي",async()=>{
 const a=await inbox({db,request:request(UID1),serverNowMs:TIME,backendSecret:SECRET});
 const b=await inbox({db,request:request(UID2),serverNowMs:TIME,backendSecret:SECRET});
 assert.deepEqual(a,b);
 assert.equal(a.items.length,1);
 assert.equal(a.items[0].place,1);
 assert.equal(a.items[0].amount,150);
 assert.equal(a.items[0].status,"pending");
 assert.equal(JSON.stringify(a).includes(ACCOUNTS[0]),false);
});
test("Wrong user, fake app, client amount injection or wrong install rejected",async()=>{
 const firstGift=giftId(SECRET,WEEK.weekId,ACCOUNTS[0]);
 await assert.rejects(redeem({db,request:request(UID3),giftId:firstGift,
   serverNowMs:TIME,backendSecret:SECRET}),/not_eligible_recipient/);
 await assert.rejects(redeem({db,request:request(UID1,{diamonds:100000}),
   giftId:firstGift,serverNowMs:TIME,backendSecret:SECRET}),
   /auth_app_check_or_untrusted_request/);
 await assert.rejects(redeem({db,request:{auth:{uid:UID1},data:{}},
   giftId:firstGift,serverNowMs:TIME,backendSecret:SECRET}),
   /auth_app_check_or_untrusted_request/);
 const session=db.doc("deda_sessions/"+UID2);
 await session.update({installId:"unreviewed_device"});
 await assert.rejects(redeem({db,request:request(UID2),giftId:firstGift,
   serverNowMs:TIME,backendSecret:SECRET}),
   /account_or_session_not_verified/);
 await session.update({installId:"stage45_phone_two"});
 assert.equal((await db.collection(GIFTS.shadowWallet).get()).size,0);
});
test("Two phones redeem same gift concurrently; ONE +150 only, replay +0",async()=>{
 const firstGift=giftId(SECRET,WEEK.weekId,ACCOUNTS[0]);
 const [a,b]=await Promise.all([UID1,UID2].map(uid=>redeem({
   db,request:request(uid),giftId:firstGift,serverNowMs:TIME,
   backendSecret:SECRET
 })));
 assert.deepEqual([a.outcome,b.outcome].sort(),
   ["already_received","private_gift_received"]);
 assert.equal(a.creditedDiamonds+b.creditedDiamonds,150);
 const wallet=(await db.doc(GIFTS.shadowWallet+"/"+privateToken(SECRET,ACCOUNTS[0])).get()).data();
 assert.equal(wallet.earnedPrizeDiamonds,150);
 const gift=(await db.doc(GIFTS.inbox+"/"+firstGift).get()).data();
 assert.equal(gift.status,"received");
 const replay=await redeem({db,request:request(UID1),giftId:firstGift,
   serverNowMs:TIME,backendSecret:SECRET});
 assert.equal(replay.creditedDiamonds,0);
 assert.equal((await db.doc("users/"+ACCOUNTS[0]+"/wallet/live_user").get()).data().originalDiamonds,999);
});
test("Second place receives +100 only, no impact on first or other original accounts",async()=>{
 const secondGift=giftId(SECRET,WEEK.weekId,ACCOUNTS[1]);
 const r=await redeem({db,request:request(UID3),giftId:secondGift,
   serverNowMs:TIME,backendSecret:SECRET});
 assert.equal(r.creditedDiamonds,100);
 const wallet=(await db.doc(GIFTS.shadowWallet+"/"+privateToken(SECRET,ACCOUNTS[1])).get()).data();
 assert.equal(wallet.earnedPrizeDiamonds,100);
 assert.equal((await db.doc(GIFTS.shadowWallet+"/"+privateToken(SECRET,ACCOUNTS[0])).get()).data().earnedPrizeDiamonds,150);
 assert.equal((await db.doc("deda_admin_diamond_wallets/gm").get()).data().diamonds,1000000);
});
test("Tampered frozen ranks, amount or signature: NO further gifts or credits",async()=>{
 const ref=db.doc(GIFTS.snapshot+"/"+WEEK.weekId);
 const saved=(await ref.get()).data();
 await ref.update({rows:saved.rows.map((r,i)=>i? r :{...r,amount:90000})});
 await assert.rejects(issue(makeArgs()),/changed_sealed_rows|untrusted_final_rank|sealed_week_conflict/);
 await ref.set(saved);
 const secondGift=giftId(SECRET,WEEK.weekId,ACCOUNTS[1]);
 const gift=db.doc(GIFTS.inbox+"/"+secondGift);
 await gift.update({amount:90000});
 await assert.rejects(redeem({db,request:request(UID3),giftId:secondGift,
   serverNowMs:TIME,backendSecret:SECRET}),/not_eligible_recipient/);
 await gift.update({amount:100});
 const post=await redeem({db,request:request(UID3),giftId:secondGift,
   serverNowMs:TIME,backendSecret:SECRET});
 assert.equal(post.creditedDiamonds,0);
});
test("Production Firebase is blocked; no actual earned wallet or App deployment",async()=>{
 const orig=process.env.GCLOUD_PROJECT;
 process.env.GCLOUD_PROJECT="deda-25b88";
 try{await assert.rejects(issue(makeArgs()),/real_firebase_forbidden/);
     await assert.rejects(prepare(makeArgs()),/real_firebase_forbidden/);}
 finally{process.env.GCLOUD_PROJECT=orig;}
 const original=(await db.doc("users/"+ACCOUNTS[0]+"/wallet/live_user").get()).data();
 assert.deepEqual(original,{originalDiamonds:999,items:["frame-0"],premiumId:"@DEDA-OWN0"});
 assert.equal((await db.doc("deda_admin_diamond_wallets/gm").get()).data().diamonds,1000000);
});
