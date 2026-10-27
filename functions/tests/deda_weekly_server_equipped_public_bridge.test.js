"use strict";
const test=require("node:test");
const assert=require("node:assert/strict");
const crypto=require("node:crypto");
const {enrichVerifiedPairWithPublicAppearance:enrich}=
  require("../deda_weekly_server_equipped_public_bridge_NOT_EXPORTED.js");
const KEY=Buffer.alloc(32,17);
const NOW=Date.UTC(2026,9,28,0);
const ACC="07712345678",OTHER="07709876543";
const PID="leader-participant-0123456789";
const OID="leader-participant-9876543210";
const CURRENT="week-current", PREVIOUS="week-previous";
const idPath=a=> "deda_weekly_verified_equipped_public/"+
  crypto.createHmac("sha256",KEY).update("equip-proof|"+a).digest("hex");
const signed=p=>({
  ...p,
  signature:crypto.createHmac("sha256",KEY)
    .update(JSON.stringify([
      p.issuer,p.status,p.accountKey,p.publicCompetitorId,
      p.originalPublicId,p.activePublicId,p.displayName,
      p.avatarStyle,p.equippedFrameStyle,p.equipmentOwnedVerified,
      p.verifiedAtMs,
    ])).digest("hex"),
});
const proof=(changes={})=>signed({
  issuer:"privileged_server_owned_equipped_appearance_v1",
  status:"verified",accountKey:ACC,publicCompetitorId:PID,
  originalPublicId:"@DEDA-ABC123",activePublicId:"@DEDA-AAAA",
  displayName:"لاعب ديدا",avatarStyle:2,equippedFrameStyle:9,
  equipmentOwnedVerified:true,verifiedAtMs:NOW-2000,...changes,
});
const raw=(week,account=ACC,token=PID,active="@DEDA-AAAA",name="لاعب ديدا")=>({
  weekId:week,rows:[{
    place:1,accountKey:account,publicCompetitorId:token,
    activePublicId:active,displayName:name,earnedLevelXp:40,
    taskClaims:2,potentialDiamonds:150,
  }],
});
const visible=(week,token=PID,active="@DEDA-AAAA",name="لاعب ديدا")=>({
  verified:true,weekId:week,status:week===CURRENT?"live":"closed",
  remainingMs:week===CURRENT?1000:0,
  viewerParticipantId:token,viewerPlace:1,rewardsCredited:false,
  rows:[{place:1,participantId:token,activePublicId:active,
    displayName:name,weeklyPoints:40,verifiedTaskCompletions:2,
    diamondsIfFinalWinner:150}],
});
const pair=(current=visible(CURRENT),previous=visible(PREVIOUS))=>({
  source:"future_server_issued_only",readOnly:true,current,previous,
});
function mock(docs={}) {
  let read=0,write=0;
  return {get read(){return read},get write(){return write},
    doc(path){return {async get(){read++;
      return path in docs
        ?{exists:true,data:()=>structuredClone(docs[path])}:{exists:false};
    }};},
    async set(){write++;throw Error("NO_SERVER_WRITES");},
    async runTransaction(){write++;throw Error("NO_SERVER_WRITES");},
  };
}
function args(db,current=raw(CURRENT),previous=raw(PREVIOUS),response=pair()) {
  return {db,rawCurrent:current,rawPrevious:previous,
    serverPair:response,serverNowMs:NOW,serverSecret:KEY};
}
test("authentic signed equipped frame paired to the SAME original account survives privacy projection",async()=>{
  const db=mock({[idPath(ACC)]:proof()});
  const result=await enrich(args(db));
  assert.equal(result.current.rows[0].publicAppearance.originalPublicId,"@DEDA-ABC123");
  assert.equal(result.current.rows[0].publicAppearance.activePublicId,"@DEDA-AAAA");
  assert.equal(result.current.rows[0].publicAppearance.equippedFrameStyle,9);
  assert.equal(result.previous.rows[0].publicAppearance.avatarStyle,2);
  assert.equal(db.read,1,"same canonical account must be read once across two weeks");
  assert.equal(db.write,0);
  const packet=JSON.stringify(result);
  for(const secret of [ACC,"accountKey","signature","verifiedAtMs",
      "equipmentOwnedVerified","managerBalance","giftedBalance"]) {
    assert.ok(!packet.includes(secret),"leak: "+secret);
  }
});
test("missing equipment proof is neutral, never fabricates portrait or enables social actions",async()=>{
  const db=mock();
  const result=await enrich(args(db));
  assert.equal(result.current.rows[0].publicAppearance,undefined);
  assert.equal(result.previous.rows[0].publicAppearance,undefined);
  assert.equal(db.write,0);
});
test("forged frame, wrong owner, stale proof, bad HMAC all fail closed",async()=>{
  const changes=[
    {accountKey:OTHER},{publicCompetitorId:OID},{equippedFrameStyle:99},
    {equipmentOwnedVerified:false},{originalPublicId:"@DEDA-INVALID-!!!"},
    {verifiedAtMs:NOW+1},{verifiedAtMs:NOW-3*86400000},
    {activePublicId:"@DEDA-BBBB",displayName:"لاعب آخر"},
  ];
  for(const fields of changes) {
    const doc=proof(fields);
    if(fields.activePublicId) {
      // A truly renamed owner's old alias is non-interactive, not a fraud.
      const safe=await enrich(args(mock({[idPath(ACC)]:doc})));
      assert.equal(safe.current.rows[0].publicAppearance,undefined);
    }else await assert.rejects(enrich(args(mock({
      [idPath(ACC)]:doc,
    }))),/STAGE21_PUBLIC_APPEARANCE_BLOCK_/);
  }
  const altered=proof();
  altered.equippedFrameStyle=10;
  await assert.rejects(enrich(args(mock({[idPath(ACC)]:altered}))),
    /equipment_proof_tampered/);
});
test("rank-to-owner binding rejects swapping rows and fake competition placement",async()=>{
  const db=mock({[idPath(ACC)]:proof()});
  const mismatch=raw(CURRENT,OTHER);
  await assert.rejects(enrich(args(db,mismatch)),
    /raw_display_owner_mismatch|invalid_signed_equipment/);
  const changed=pair();
  changed.current.rows[0].weeklyPoints=999;
  await assert.rejects(enrich(args(db,raw(CURRENT),raw(PREVIOUS),changed)),
    /raw_display_owner_mismatch/);
  const wrongWeek=raw("alien-week");
  await assert.rejects(enrich(args(db,wrongWeek)),
    /verified_view_required/);
});
test("historical renamed alias stays on scoreboard but never borrows current equipped frame",async()=>{
  const db=mock({[idPath(ACC)]:proof()});
  const previous=raw(PREVIOUS,ACC,PID,"@DEDA-OLDID","لاعب سابق");
  const response=pair(visible(CURRENT),visible(PREVIOUS,PID,
     "@DEDA-OLDID","لاعب سابق"));
  const result=await enrich(args(db,raw(CURRENT),previous,response));
  assert.equal(result.current.rows[0].publicAppearance.equippedFrameStyle,9);
  assert.equal(result.previous.rows[0].publicAppearance,undefined);
  assert.equal(result.previous.rows[0].activePublicId,"@DEDA-OLDID");
});
test("no secret, untrusted request fields and client-supplied wallet fields rejected",async()=>{
  await assert.rejects(enrich({...args(mock()),serverSecret:null}),
    /backend_hmac_secret_required/);
  await assert.rejects(enrich({...args(mock()),serverPair:{
    ...pair(),walletBalance:20000,
  }}),/privileged_verified_pair_required/);
});
