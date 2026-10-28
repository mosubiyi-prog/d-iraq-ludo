"use strict";
/**
 * STAGE45 — PRIVATE emulator-only bridge:
 * Stage44 reviewed-applied XP top ten -> sealed private week -> 10 PENDING
 * gift-inbox entries -> once-only redeem to PRIVATE shadow diamond wallet.
 *
 * NOT A DEPLOYED CLOUD FUNCTION. No real "هداياي", wallet or Play writes.
 * Stage44's review, original task source, cutover and profiles are still
 * synthetic emulator fixtures; this integration cannot authorize production.
 * A real server-wide snapshot needs atomic/versioned finalization while writes
 * occur, plus real Auth/App Check and actual spendable wallet integration.
 */
const crypto=require("node:crypto");
const {PROJECT,LEAGUE_ROOT,qaId,
  previewPrivateTopTenFromAppliedXp}=require(
    "./deda_weekly_stage44_verified_ledger_top10_archive_NOT_EXPORTED.js");
const {windowFor,PRIZES}=require(
    "./deda_weekly_stage31_frozen_league_winner_card_NOT_EXPORTED.js");
const ROOT=Object.freeze({
  snapshot:"deda_weekly_stage45_private_sealed_top10",
  settlement:"deda_weekly_stage45_private_gift_settlements",
  inbox:"deda_weekly_stage45_private_gift_inbox",
  shadowWallet:"deda_weekly_stage45_private_shadow_earned_diamonds"
});
const ISSUER="stage45_backend_fixture_only_NOT_LIVE";
const ACCOUNT=/^[0-9]{10,16}$/;
const UID=/^[A-Za-z0-9_-]{1,128}$/;
const ID=/^[a-f0-9]{64}$/;
const WEEK=/^[A-Za-z0-9_-]{1,80}$/;
function fail(label){throw Error("DEDA_STAGE45_PRIVATE_BLOCK_"+label);}
function positive(n){return Number.isSafeInteger(n)&&n>=0;}
function local(db,secret){
  if(process.env.GCLOUD_PROJECT!==PROJECT||
     !process.env.FIRESTORE_EMULATOR_HOST||
     !db||typeof db.runTransaction!=="function"||
     !Buffer.isBuffer(secret)||secret.length<32)
    fail("real_firebase_forbidden");
}
function sign(secret,obj){
  return crypto.createHmac("sha256",secret).update(
    JSON.stringify(obj),"utf8").digest("hex");
}
function privateToken(secret,account){
  if(!ACCOUNT.test(account||""))fail("account");
  return sign(secret,["recipient",account]);
}
function giftId(secret,weekId,account){
  if(!WEEK.test(weekId||""))fail("week");
  return sign(secret,["gift",weekId,account]);
}
function canonicalRows(rows){
  if(!Array.isArray(rows)||rows.length<1||rows.length>10)fail("winners");
  const seenAccount=new Set(),seenParticipants=new Set();
  return rows.map((r,i)=>{
    if(!r||r.place!==i+1||!ACCOUNT.test(r.accountKey||"")||
       !/^qa-player-[A-Za-z0-9_-]{25}$/.test(r.participantId||"")||
       !positive(r.weeklyXp)||r.weeklyXp===0||r.weeklyXp%20!==0||
       !positive(r.verifiedTaskCount)||r.verifiedTaskCount!==r.weeklyXp/20||
       r.amount!==PRIZES[i]||seenAccount.has(r.accountKey)||
       seenParticipants.has(r.participantId))
      fail("untrusted_final_rank");
    seenAccount.add(r.accountKey);seenParticipants.add(r.participantId);
    return {place:r.place,accountKey:r.accountKey,participantId:r.participantId,
      weeklyXp:r.weeklyXp,verifiedTaskCount:r.verifiedTaskCount,amount:r.amount};
  });
}
function digest(secret,weekId,rows){
  return sign(secret,["stage45-frozen-fixture",weekId,rows]);
}
async function retryTransient(fn){
  // QA ONLY: retry the *entire* security-checking transaction, no partial
  // wallet writes. Domain/auth/shape errors never retried.
  for(let i=0;i<4;i++){
    try{return await fn();}
    catch(e){
      if(i===3||e?.code!==3||
         !/Transaction is invalid or closed/.test(e.message||""))throw e;
    }
  }
  fail("transaction_retry_limit");
}
async function preparePrivateFrozenWeek({db,firstOpenMs,weekIndex,
  serverNowMs,backendSecret,...overrides}){
  local(db,backendSecret);
  if(Object.keys(overrides).length||!positive(serverNowMs))
    fail("client_supplied_parameters");
  const week=windowFor(firstOpenMs,weekIndex);
  // No prize notification or gift until AFTER 06:00 Baghdad, per owner.
  if(serverNowMs<week.nextOpenMs)fail("not_released_0600_baghdad");
  const projection=await previewPrivateTopTenFromAppliedXp({
    db,firstOpenMs,weekIndex,serverNowMs,backendSecret
  });
  if(projection.state!=="frozen"||!projection.snapshot||
     projection.previewOnly!==true||projection.productionReady!==false||
     projection.actuallyCreditedDiamonds!==0)fail("non_private_frozen_result");
  // Stage44's public result intentionally drops canonical accountKey.
  // Reconstruct the mapping exclusively from the private XP receipt root;
  // never accept accountKey, winners, amounts or rank from the client.
  const docs=await db.collection(LEAGUE_ROOT)
    .where("weekId","==",week.weekId).get();
  const ids=new Map();
  for(const item of docs.docs){
    const p=item.data();
    if(!ACCOUNT.test(p.accountKey||""))fail("invalid_private_receipt_owner");
    const pseudo=qaId(p.accountKey,backendSecret);
    const existing=ids.get(pseudo);
    if(existing&&existing!==p.accountKey)fail("ambiguous_recipient_mapping");
    ids.set(pseudo,p.accountKey);
  }
  const rows=canonicalRows(projection.topTen.map((p,i)=>{
    const accountKey=ids.get(p.participantId);
    if(!accountKey||qaId(accountKey,backendSecret)!==p.participantId)
      fail("unresolved_winner_owner");
    return {place:p.place,participantId:p.participantId,accountKey,
      weeklyXp:p.weeklyXp,verifiedTaskCount:p.verifiedTaskCount,
      amount:p.plannedDiamonds};
  }));
  const signature=digest(backendSecret,week.weekId,rows);
  const ref=db.doc(ROOT.snapshot+"/"+week.weekId);
  return retryTransient(()=>db.runTransaction(async tx=>{
    const prior=await tx.get(ref);
    if(prior.exists){
      const stored=prior.data();
      if(stored.issuer!==ISSUER||stored.emulatorOnly!==true||
         stored.canAuthorizeProduction!==false||
         stored.weekId!==week.weekId||stored.signature!==signature||
         JSON.stringify(stored.rows)!==JSON.stringify(rows)||
         stored.state!=="closed_preview")
        fail("sealed_week_conflict");
      return Object.freeze({outcome:"already_sealed",weekId:week.weekId,
        winnerCount:rows.length,emulatorOnly:true});
    }
    tx.create(ref,{issuer:ISSUER,emulatorOnly:true,
      canAuthorizeProduction:false,weekId:week.weekId,
      state:"closed_preview",closedAtMs:week.closeAtMs,
      releasedAtMs:week.nextOpenMs,createdAtMs:serverNowMs,
      signature,rows});
    return Object.freeze({outcome:"private_week_sealed",
      weekId:week.weekId,winnerCount:rows.length,emulatorOnly:true});
  }));
}
function checkedSealed(snapshot,week,secret){
  if(!snapshot||snapshot.issuer!==ISSUER||snapshot.emulatorOnly!==true||
     snapshot.canAuthorizeProduction!==false||
     snapshot.weekId!==week.weekId||
     snapshot.state!=="closed_preview"||
     snapshot.closedAtMs!==week.closeAtMs||
     snapshot.releasedAtMs!==week.nextOpenMs||
     !positive(snapshot.createdAtMs)||
     snapshot.createdAtMs<week.nextOpenMs)
    fail("untrusted_sealed_week");
  const rows=canonicalRows(snapshot.rows);
  if(digest(secret,week.weekId,rows)!==snapshot.signature)
    fail("changed_sealed_rows");
  for(const r of rows)
    if(r.participantId!==qaId(r.accountKey,secret))
      fail("invalid_signed_recipient");
  if(rows.length===10&&rows.reduce((n,r)=>n+r.amount,0)!==370)
    fail("owner_prize_budget");
  return rows;
}
/** One transaction issues ten PENDING inbox entries, not spendable diamonds. */
async function simulateIssuePrivateGiftInbox({db,firstOpenMs,weekIndex,
  serverNowMs,backendSecret,...overrides}){
  local(db,backendSecret);
  if(Object.keys(overrides).length||!positive(serverNowMs))
    fail("client_supplied_parameters");
  const week=windowFor(firstOpenMs,weekIndex);
  if(serverNowMs<week.nextOpenMs)fail("not_released_0600_baghdad");
  const snapshotRef=db.doc(ROOT.snapshot+"/"+week.weekId);
  const settleRef=db.doc(ROOT.settlement+"/"+week.weekId);
  return retryTransient(()=>db.runTransaction(async tx=>{
    const [s,old]=await Promise.all([
      tx.get(snapshotRef),tx.get(settleRef)]);
    if(!s.exists)fail("verified_week_not_sealed");
    const snapshot=s.data();
    const rows=checkedSealed(snapshot,week,backendSecret);
    // For both first issuance and replay, read ALL ten inbox receipts in
    // the SAME transaction before issuing a success response. A missing,
    // changed or partially redeemed gift must not be silently accepted.
    const refs=rows.map(r=>db.doc(ROOT.inbox+"/"+giftId(
      backendSecret,week.weekId,r.accountKey)));
    const oldGifts=await Promise.all(refs.map(ref=>tx.get(ref)));
    if(old.exists){
      const x=old.data();
      if(x.issuer!==ISSUER||x.emulatorOnly!==true||
         x.canAuthorizeProduction!==false||
         x.weekId!==week.weekId||
         x.snapshotSignature!==snapshot.signature||
         x.winnerCount!==rows.length||
         x.totalDiamonds!==rows.reduce((n,r)=>n+r.amount,0)||
         x.state!=="pending_gifts_issued")
        fail("settlement_mismatch");
      rows.forEach((winner,i)=>{
        if(!oldGifts[i].exists)fail("missing_previously_issued_gift");
        const g=oldGifts[i].data();
        if(g.issuer!==ISSUER||g.emulatorOnly!==true||
           g.canAuthorizeProduction!==false||
           g.giftId!==refs[i].id||g.weekId!==week.weekId||
           g.place!==winner.place||
           g.participantId!==winner.participantId||
           g.recipientToken!==privateToken(backendSecret,winner.accountKey)||
           g.amount!==winner.amount||
           g.snapshotSignature!==snapshot.signature||
           !["pending","received"].includes(g.status))
          fail("changed_previously_issued_gift");
      });
      return Object.freeze({outcome:"already_issued",
        giftCount:0,pendingDiamondsIssued:0,
        actuallyCreditedDiamonds:0,emulatorOnly:true});
    }
    if(oldGifts.some(x=>x.exists))fail("partial_existing_gift");
    rows.forEach((r,i)=>{
      tx.create(refs[i],{
        issuer:ISSUER,emulatorOnly:true,canAuthorizeProduction:false,
        giftId:refs[i].id,weekId:week.weekId,place:r.place,
        participantId:r.participantId,
        recipientToken:privateToken(backendSecret,r.accountKey),
        amount:r.amount,status:"pending",
        snapshotSignature:snapshot.signature,
        createdAtMs:serverNowMs
      });
    });
    tx.create(settleRef,{
      issuer:ISSUER,emulatorOnly:true,canAuthorizeProduction:false,
      state:"pending_gifts_issued",weekId:week.weekId,
      snapshotSignature:snapshot.signature,winnerCount:rows.length,
      totalDiamonds:rows.reduce((n,r)=>n+r.amount,0),
      createdAtMs:serverNowMs
    });
    return Object.freeze({outcome:"private_pending_gifts_issued",
      giftCount:rows.length,
      pendingDiamondsIssued:rows.reduce((n,r)=>n+r.amount,0),
      actuallyCreditedDiamonds:0,emulatorOnly:true});
  }));
}
function requestUid(request){
  const uid=request?.auth?.uid;
  if(!UID.test(uid||"")||
     request?.auth?.token?.firebase?.sign_in_provider==="anonymous"||
     typeof request?.app?.appId!=="string"||request.app.appId.length<4||
     !request.data||typeof request.data!=="object"||
     Array.isArray(request.data)||Object.keys(request.data).length)
    fail("auth_app_check_or_untrusted_request");
  return uid;
}
function snapData(s,label){
  if(!s.exists)fail("missing_"+label);
  return s.data();
}
async function verifiedAccount(tx,db,uid,now){
  const [u,s,a]=await Promise.all([
    tx.get(db.doc("users/"+uid)),
    tx.get(db.doc("deda_sessions/"+uid)),
    tx.get(db.doc("deda_weekly_identity_attestations/"+uid)),
  ]);
  const user=snapData(u,"user"),session=snapData(s,"session"),
    att=snapData(a,"identity");
  const account=user.accountKey;
  if(!ACCOUNT.test(account||"")||
     user.uid!==uid||session.uid!==uid||
     session.accountKey!==account||
     !UID.test(session.installId||"")||
     att.issuer!=="privileged_identity_verifier_v1"||
     att.state!=="verified"||att.uid!==uid||
     att.accountKey!==account||
     att.installId!==session.installId||
     !positive(att.issuedAtMs)||att.issuedAtMs>now||
     !positive(att.expiresAtMs)||att.expiresAtMs<=now)
    fail("account_or_session_not_verified");
  const profile=snapData(await tx.get(
    db.doc("deda_account_profiles/"+account)),"account_profile");
  if(profile.accountKey!==account||
     !Array.isArray(profile.trustedInstallIds)||
     !profile.trustedInstallIds.includes(session.installId))
    fail("install_not_in_account_profile");
  return account;
}
/** Private preview of "هداياي" needs verified account, no account input. */
async function previewPrivateGiftInbox({db,request,serverNowMs,
  backendSecret,...overrides}){
  local(db,backendSecret);
  if(Object.keys(overrides).length||!positive(serverNowMs))
    fail("untrusted_inbox_parameters");
  const uid=requestUid(request);
  return db.runTransaction(async tx=>{
    const account=await verifiedAccount(tx,db,uid,serverNowMs);
    const token=privateToken(backendSecret,account);
    // Query outside transaction is not admissible for authenticated client
    // list on real backend; here read-only Admin SDK QA only.
    return {account,token};
  }).then(async({token})=>{
    const all=await db.collection(ROOT.inbox)
      .where("recipientToken","==",token).get();
    const rows=all.docs.map(s=>s.data());
    if(rows.some(x=>x.issuer!==ISSUER||x.emulatorOnly!==true||
       x.canAuthorizeProduction!==false||
       !ID.test(x.giftId||"")||
       !["pending","received"].includes(x.status)||
       !positive(x.amount)||!positive(x.place)||x.place>10))
      fail("untrusted_inbox_fixture");
    return Object.freeze({emulatorOnly:true,readOnly:true,
      actuallyCreditedDiamonds:0,items:Object.freeze(rows.map(r=>({
        giftId:r.giftId,weekId:r.weekId,place:r.place,amount:r.amount,
        status:r.status,
      })))});
  });
}
/** Redeem one pending "هداياي" gift to SHADOW wallet (never real DEDA). */
async function simulateRedeemPrivateGift({db,request,giftId:claimedGiftId,
  serverNowMs,backendSecret,...overrides}){
  local(db,backendSecret);
  if(Object.keys(overrides).length||!positive(serverNowMs)||
     !ID.test(claimedGiftId||""))fail("untrusted_claim_inputs");
  const uid=requestUid(request);
  return retryTransient(()=>db.runTransaction(async tx=>{
    const account=await verifiedAccount(tx,db,uid,serverNowMs);
    const giftRef=db.doc(ROOT.inbox+"/"+claimedGiftId);
    const giftSnap=await tx.get(giftRef);
    const gift=snapData(giftSnap,"pending_gift");
    if(gift.issuer!==ISSUER||gift.emulatorOnly!==true||
       gift.canAuthorizeProduction!==false||
       !WEEK.test(gift.weekId||"")||
       gift.giftId!==claimedGiftId||
       gift.giftId!==giftId(backendSecret,gift.weekId,account)||
       gift.recipientToken!==privateToken(backendSecret,account)||
       !positive(gift.place)||gift.place<1||gift.place>10||
       gift.amount!==PRIZES[gift.place-1]||
       gift.participantId!==qaId(account,backendSecret)||
       !["pending","received"].includes(gift.status))
      fail("not_eligible_recipient");
    const settlementRef=db.doc(ROOT.settlement+"/"+gift.weekId);
    const snapshotRef=db.doc(ROOT.snapshot+"/"+gift.weekId);
    const [settleSnap,snapshotSnap]=await Promise.all([
      tx.get(settlementRef),tx.get(snapshotRef)]);
    const settlement=snapData(settleSnap,"settled_week"),
      frozen=snapData(snapshotSnap,"frozen_week");
    if(settlement.issuer!==ISSUER||settlement.emulatorOnly!==true||
       settlement.state!=="pending_gifts_issued"||
       settlement.snapshotSignature!==gift.snapshotSignature||
       settlement.weekId!==gift.weekId||
       frozen.signature!==gift.snapshotSignature)
      fail("untrusted_settlement");
    const rows=canonicalRows(frozen.rows);
    const matched=rows.find(r=>r.accountKey===account);
    if(!matched||matched.place!==gift.place||
       matched.amount!==gift.amount||
       digest(backendSecret,gift.weekId,rows)!==gift.snapshotSignature)
      fail("altered_original_rank");
    if(gift.status==="received")
      return Object.freeze({outcome:"already_received",
        creditedDiamonds:0,emulatorOnly:true});
    const walletRef=db.doc(ROOT.shadowWallet+"/"+privateToken(
      backendSecret,account));
    const walletSnap=await tx.get(walletRef);
    const old=walletSnap.exists?walletSnap.data():null;
    if(old&&(old.issuer!==ISSUER||old.emulatorOnly!==true||
       old.canAuthorizeProduction!==false||
       old.recipientToken!==gift.recipientToken||
       !positive(old.earnedPrizeDiamonds)))
      fail("untrusted_shadow_wallet");
    const balance=(old?.earnedPrizeDiamonds||0)+gift.amount;
    if(!positive(balance))fail("overflow");
    const write={issuer:ISSUER,emulatorOnly:true,
      canAuthorizeProduction:false,recipientToken:gift.recipientToken,
      earnedPrizeDiamonds:balance,updatedAtMs:serverNowMs};
    if(walletSnap.exists)tx.update(walletRef,write);
    else tx.create(walletRef,write);
    tx.update(giftRef,{status:"received",receivedAtMs:serverNowMs});
    return Object.freeze({outcome:"private_gift_received",
      creditedDiamonds:gift.amount,emulatorOnly:true,
      realDEDAWalletChanged:false});
  }));
}
module.exports=Object.freeze({
  PROJECT,ROOT,ISSUER,privateToken,giftId,
  preparePrivateFrozenWeek,simulateIssuePrivateGiftInbox,
  previewPrivateGiftInbox,simulateRedeemPrivateGift
});
