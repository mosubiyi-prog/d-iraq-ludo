"use strict";
const test=require("node:test");
const assert=require("node:assert/strict");
const {inspectDomainSources}=
  require("../deda_logical_room_domain_readback_OFFLINE_ONLY.js");
const A="fixture-original-owner-A",B="fixture-registration-B",
  C="fixture-social-C",D="fixture-untrusted-D";
const acct="07700000000", id="@DEDA-ABC123";
const fuid="fixture-external-friend-Z";
function base(){
  return {accountKey:acct,originalId:id,
    route:{ownerUid:A,publicId:id,kind:"personal",active:true},
    directory:{createdUid:B,accountKey:acct,active:true},
    credentials:{createdUid:B,accountKey:acct,active:true},
    social:{ownerUid:C,publicId:id},
    originalUser:{accountKey:acct,sharePersonalId:id},
    registeredUser:{accountKey:acct},
    socialUser:{accountKey:acct,sharePersonalId:id}};
}
const pair=[A,fuid].sort().join("__");
function sources(){
  return {
    friends:[{id:pair,pairKey:pair,members:[A,fuid],
      requesterUid:A,recipientUid:fuid,status:"accepted",
      cached:false,pendingWrites:false}],
    gifts:[{id:"deda-weekly-2026-11-14-DEDA-ABC123",giftId:"deda-weekly-2026-11-14-DEDA-ABC123",
      sourceType:"weekly_league",targetPublicId:id,
      amount:100,status:"received",createdAtMs:1794700000000,
      cached:false,pendingWrites:false}],
    giftWallet:{publicId:id,balance:120,cached:false,pendingWrites:false},
    premium:{originalId:id,activeId:"@DEDA-GOLD1",cached:false,pendingWrites:false},
    leagueAccount:{publicId:id,accountKey:acct,cached:false,pendingWrites:false},
    leagueControl:{weekId:"2026-11-14",cached:false,pendingWrites:false},
    leagueScore:{publicId:id,weekId:"2026-11-14",weeklyXp:65,cached:false,pendingWrites:false},
  };
}
const run=(overrides={})=>inspectDomainSources({
  roomSnapshot:base(),sourceRows:sources(),sessionUid:B,...overrides,
});
function locked(x){
  assert.equal(x.loginPermitted,false);
  assert.equal(x.crossUidReadPermitted,false);
  assert.equal(x.crossUidWritePermitted,false);
  assert.equal(x.createUidPermitted,false);
  assert.equal(x.createTokenPermitted,false);
  assert.equal(x.adminEntryPermitted,false);
  assert.equal(x.financialGrantPermitted,false);
  assert.equal(x.createsReceipt,false);
  assert.equal(x.overwritesSource,false);
  x.domains.forEach(d=>{
    assert.equal(d.authorization,"NOT_GRANTED");
    assert.equal(d.sourceWrite,false);
    assert.equal(d.sourceUidReassignment,false);
    assert.equal(d.receiptReissue,false);
  });
}
const domain=(x,n)=>x.domains.find(y=>y.domain===n);
test("all 14 DEDA domains have isolated, denied results",()=>{
  const x=run();assert.equal(x.domains.length,14);locked(x);
  assert.equal(x.decision,"HOLD_FOR_INDEPENDENT_OWNER_PROOF");
});
test("A B C and non-historical D cannot gain access",()=>{
  for(const uid of [A,B,C,D,null])locked(run({sessionUid:uid}));
});
test("friends stay keyed to original UID pair and no invitation created",()=>{
  const x=run();locked(x);
  assert.equal(domain(x,"friends").status,
    "FRIEND_UID_PAIRS_SHAPE_MATCHED_NOT_AUTHORIZED");
});
test("duplicate friends pair is rejected, not merged silently",()=>{
  const s=sources();s.friends.push({...s.friends[0]});
  const x=run({sourceRows:s});assert.equal(x.reason,"DOMAIN_SOURCE_CONFLICT");locked(x);
});
test("foreign or malformed friend relation rejected",()=>{
  const s=sources();s.friends[0].members=[D,fuid];
  const x=run({sourceRows:s});assert.equal(x.reason,"DOMAIN_SOURCE_CONFLICT");locked(x);
});
test("invalid pair key rejected instead of creating new one",()=>{
  const s=sources();s.friends[0].pairKey="fake";
  const x=run({sourceRows:s});assert.equal(x.reason,"DOMAIN_SOURCE_CONFLICT");locked(x);
});
test("intra-room historical friend pair is flagged, not auto-transferred",()=>{
  const s=sources();const self=[A,C].sort().join("__");
  s.friends=[{id:self,pairKey:self,members:[A,C],requesterUid:A,
    recipientUid:C,status:"accepted",cached:false,pendingWrites:false}];
  const x=run({sourceRows:s});locked(x);
  assert.equal(domain(x,"friends").status,
    "INTERNAL_ALIAS_RELATION_REVIEW_REQUIRED");
});
test("duplicate gift receipt is rejected; never reissued",()=>{
  const s=sources();s.gifts.push({...s.gifts[0]});
  const x=run({sourceRows:s});assert.equal(x.reason,"DOMAIN_SOURCE_CONFLICT");locked(x);
});
test("weekly prize receipt must tie to original public ID",()=>{
  const s=sources();s.gifts[0].targetPublicId="@DEDA-XXXXXX";
  assert.equal(run({sourceRows:s}).reason,"DOMAIN_SOURCE_CONFLICT");
});
test("weekly gift id and time mismatch fail closed",()=>{
  for(const key of ["giftId","createdAtMs"]) {
    const s=sources();s.gifts[0][key]=key==="giftId"?"other":-1;
    assert.equal(run({sourceRows:s}).reason,"DOMAIN_SOURCE_CONFLICT");
  }
});
test("wallet balance never credited or added to weekly prize",()=>{
  const x=run();locked(x);
  assert.equal(domain(x,"diamonds").status,
    "GIFT_WALLET_SHAPE_MATCHED_NOT_TOTAL_BALANCE");
  assert.equal(JSON.stringify(x).includes("120"),false);
  assert.equal(JSON.stringify(x).includes("100"),false);
});
test("missing wallet is unknown not zero",()=>{
  const s=sources();delete s.giftWallet;
  const x=run({sourceRows:s});
  assert.equal(domain(x,"diamonds").status,"SOURCE_ABSENT_UNKNOWN_NOT_ZERO");
  locked(x);
});
test("invalid wallet and negative amount fail closed",()=>{
  for(const value of [-1,Number.MAX_SAFE_INTEGER+1,"120"]) {
    const s=sources();s.giftWallet.balance=value;
    assert.equal(run({sourceRows:s}).reason,"DOMAIN_SOURCE_CONFLICT");
  }
});
test("premium ID display status does not grant ownership",()=>{
  const x=run();locked(x);
  assert.equal(domain(x,"premium_id").status,
    "DISPLAY_SELECTION_SHAPE_MATCHED_NOT_OWNERSHIP");
});
test("premium ID wrong original route rejected",()=>{
  const s=sources();s.premium.originalId="@DEDA-ZZZZZZ";
  assert.equal(run({sourceRows:s}).reason,"DOMAIN_SOURCE_CONFLICT");
});
test("weekly score mismatch, negative or absent week blocked",()=>{
  for(const bad of [()=>{const s=sources();s.leagueScore.publicId="@DEDA-AAAAAA";return s;},
    ()=>{const s=sources();s.leagueScore.weeklyXp=-2;return s;},
    ()=>{const s=sources();delete s.leagueControl;return s;}]) {
    assert.equal(run({sourceRows:bad()}).reason,"DOMAIN_SOURCE_CONFLICT");
  }
});
test("league XP remains a readback shape not claimable score",()=>{
  const x=run();locked(x);
  assert.equal(domain(x,"league").status,
    "LEAGUE_SOURCE_SHAPE_MATCHED_NOT_AWARD_AUTHORITY");
});
test("empty friends and gifts are historically unknown",()=>{
  const s=sources();s.friends=[];s.gifts=[];
  const x=run({sourceRows:s});locked(x);
  assert.equal(domain(x,"friends").status,"SOURCE_EMPTY_HISTORICAL_UNKNOWN");
  assert.equal(domain(x,"gifts").status,"SOURCE_EMPTY_HISTORICAL_UNKNOWN");
});
test("missing friends and gift receipts do not turn to zero",()=>{
  const s=sources();delete s.friends;delete s.gifts;
  const x=run({sourceRows:s});locked(x);
  assert.equal(domain(x,"friends").status,"SOURCE_ABSENT_UNKNOWN");
  assert.equal(domain(x,"gifts").status,"SOURCE_ABSENT_UNKNOWN");
});
test("admin authorization is separate regardless of mock current UID",()=>{
  const x=run({sessionUid:A});locked(x);
  assert.equal(domain(x,"administration").status,
    "SEPARATE_ADMIN_VERIFICATION_REQUIRED");
});
test("original proof is still absent even with matching source metadata",()=>{
  const s=base();s.directory.createdUid=A;s.credentials.createdUid=A;
  s.social.ownerUid=A;const x=run({roomSnapshot:s,sessionUid:A});
  locked(x);assert.equal(x.decision,"HOLD_FOR_INDEPENDENT_OWNER_PROOF");
});
test("foreign account or conflicting owner route blocks every domain",()=>{
  for(const alter of [s=>s.socialUser.accountKey="07799999999",
    s=>s.route.publicId="@DEDA-OTHER1"]) {
    const s=base();alter(s);const x=run({roomSnapshot:s});
    locked(x);assert.equal(x.reason,"ROOM_SOURCE_CONFLICT");
    assert.equal(x.domains.length,0);
  }
});
test("untrusted caller claims are ignored and output contains no ids",()=>{
  const s=base();s.customClaims={admin:true};s.pin="123456";
  const x=run({roomSnapshot:s,independentProof:{verified:true}});
  locked(x);const json=JSON.stringify(x);
  for(const value of [A,B,C,D,acct,id,"123456"])assert.equal(json.includes(value),false);
});
test("readback does not mutate mock source or owner references",()=>{
  const s=sources(),b=base(),sb=JSON.stringify(s),bb=JSON.stringify(b);
  const x=run({roomSnapshot:b,sourceRows:s});locked(x);
  assert.equal(JSON.stringify(s),sb);assert.equal(JSON.stringify(b),bb);
});
test("oversized or non-array receipt sources rejected",()=>{
  const s=sources();s.friends={};
  assert.equal(run({sourceRows:s}).reason,"DOMAIN_SOURCE_CONFLICT");
  s.friends=Array.from({length:5001},()=>({}));
  assert.equal(run({sourceRows:s}).reason,"DOMAIN_SOURCE_CONFLICT");
});
test("invalid domain source container denied",()=>{
  for(const sourceRows of [null,[],42,"a"]){
    const x=run({sourceRows});locked(x);
    assert.equal(x.reason,"INVALID_READBACK_INPUT");
  }
});
test("two historical aliases with one external friend are not merged",()=>{
  const s=sources();const aliasPair=[C,fuid].sort().join("__");
  s.friends.push({id:aliasPair,pairKey:aliasPair,
    members:[C,fuid],requesterUid:C,recipientUid:fuid,
    status:"accepted",cached:false,pendingWrites:false});
  const x=run({sourceRows:s});locked(x);
  assert.equal(domain(x,"friends").status,
    "ALIAS_FRIEND_DUPLICATE_REVIEW_REQUIRED");
  assert.equal(x.domains.length,14);
});
test("alias duplicate friend remains flagged if member order is reversed",()=>{
  const s=sources();const aliasPair=[C,fuid].sort().join("__");
  s.friends.push({id:aliasPair,pairKey:aliasPair,
    members:[fuid,C],requesterUid:fuid,recipientUid:C,
    status:"pending",cached:false,pendingWrites:false});
  const x=run({sourceRows:s});locked(x);
  assert.equal(domain(x,"friends").status,
    "ALIAS_FRIEND_DUPLICATE_REVIEW_REQUIRED");
});
test("missing or cached friend provenance fails closed",()=>{
  for (const mutate of [
    row=>delete row.cached,row=>row.cached=true,
    row=>row.pendingWrites=true,row=>delete row.pendingWrites
  ]) {
    const s=sources();mutate(s.friends[0]);
    const x=run({sourceRows:s});locked(x);
    assert.equal(x.reason,"DOMAIN_SOURCE_CONFLICT");
  }
});
test("missing or cached gift provenance fails closed",()=>{
  for (const mutate of [
    row=>delete row.cached,row=>row.cached=true,
    row=>row.pendingWrites=true,row=>delete row.pendingWrites
  ]) {
    const s=sources();mutate(s.gifts[0]);
    const x=run({sourceRows:s});locked(x);
    assert.equal(x.reason,"DOMAIN_SOURCE_CONFLICT");
  }
});
test("league score without account link cannot be marked consistent",()=>{
  const s=sources();delete s.leagueAccount;
  const x=run({sourceRows:s});locked(x);
  assert.equal(x.reason,"DOMAIN_SOURCE_CONFLICT");
});
test("league account without control is historical unknown not a zero",()=>{
  const s=sources();delete s.leagueControl;delete s.leagueScore;
  const x=run({sourceRows:s});locked(x);
  assert.equal(domain(x,"league").status,
    "LEAGUE_CONTROL_MISSING_HISTORICAL_UNKNOWN");
});
test("internal historical friend and external friend remain isolated",()=>{
  const s=sources();const internal=[A,C].sort().join("__");
  s.friends.push({id:internal,pairKey:internal,members:[A,C],
    requesterUid:A,recipientUid:C,status:"accepted",
    cached:false,pendingWrites:false});
  const x=run({sourceRows:s});locked(x);
  assert.equal(domain(x,"friends").status,
    "INTERNAL_ALIAS_RELATION_REVIEW_REQUIRED");
});

test("valid admin gift is metadata-only and never credits wallet",()=>{
  const s=sources();s.gifts.push({id:"admin-gift-01",giftId:"admin-gift-01",
    sourceType:"admin",targetPublicId:id,amount:1000000,
    status:"pending",createdAtMs:1794700000000,cached:false,pendingWrites:false});
  const x=run({sourceRows:s});locked(x);
  assert.equal(domain(x,"gifts").status,"GIFT_RECEIPTS_SHAPE_MATCHED_NO_REISSUE");
  assert.equal(x.financialGrantPermitted,false);
});
test("admin gift claimed once is a receipt, not authority to reissue",()=>{
  const s=sources();s.gifts.push({id:"admin-gift-02",giftId:"admin-gift-02",
    sourceType:"admin",targetPublicId:id,amount:120,
    status:"received",createdAtMs:1794700000000,
    claimedAtMs:1794700002000,cached:false,pendingWrites:false});
  const x=run({sourceRows:s});locked(x);
  assert.equal(domain(x,"gifts").status,"GIFT_RECEIPTS_SHAPE_MATCHED_NO_REISSUE");
});
test("admin gift ID mismatch or excessive amount fails closed",()=>{
  for (const fn of [
    x=>x.giftId="OTHER",x=>x.amount=1000001,
    x=>x.amount=-1,x=>x.amount="50"
  ]) {
    const s=sources(),item={id:"admin-gift-03",giftId:"admin-gift-03",
      sourceType:"admin",targetPublicId:id,amount:200,status:"pending",
      createdAtMs:1794700000000,cached:false,pendingWrites:false};
    fn(item);s.gifts.push(item);
    const x=run({sourceRows:s});locked(x);
    assert.equal(x.reason,"DOMAIN_SOURCE_CONFLICT");
  }
});
test("admin gift requires consistent claim transition metadata",()=>{
  for (const fn of [
    x=>x.status="claimed",
    x=>x.claimedAtMs=1794700003000,
    x=>x.createdAtMs=0
  ]) {
    const s=sources(),item={id:"admin-gift-04",giftId:"admin-gift-04",
      sourceType:"admin",targetPublicId:id,amount:20,status:"pending",
      createdAtMs:1794700000000,cached:false,pendingWrites:false};
    fn(item);s.gifts.push(item);
    const x=run({sourceRows:s});locked(x);
    assert.equal(x.reason,"DOMAIN_SOURCE_CONFLICT");
  }
});
test("received admin gift must have claim time after creation",()=>{
  for(const claimedAtMs of [null,0,1794699999999]){
    const s=sources();s.gifts.push({id:"admin-gift-05",giftId:"admin-gift-05",
      sourceType:"admin",targetPublicId:id,amount:20,status:"received",
      createdAtMs:1794700000000,claimedAtMs,cached:false,pendingWrites:false});
    const x=run({sourceRows:s});locked(x);
    assert.equal(x.reason,"DOMAIN_SOURCE_CONFLICT");
  }
});
test("unknown historical gift source gets review, not deletion or credit",()=>{
  const s=sources();s.gifts.push({id:"legacy-receipt-06",
    targetPublicId:id,sourceType:"legacy",amount:250,
    cached:false,pendingWrites:false});
  const x=run({sourceRows:s});locked(x);
  assert.equal(domain(x,"gifts").status,"UNKNOWN_GIFT_SOURCE_REVIEW_REQUIRED");
  assert.equal(JSON.stringify(x).includes("250"),false);
});

test("cache and pending flags must be explicitly fresh on gift wallet",()=>{
  for(const mutate of [x=>delete x.cached,x=>x.cached=true,x=>delete x.pendingWrites,
    x=>x.pendingWrites=true]){
    const s=sources();mutate(s.giftWallet);
    const out=run({sourceRows:s});locked(out);
    assert.equal(out.reason,"DOMAIN_SOURCE_CONFLICT");
  }
});
test("premium display selection from cache cannot look server verified",()=>{
  for(const mutate of [x=>delete x.cached,x=>x.cached=true,
    x=>delete x.pendingWrites,x=>x.pendingWrites=true]){
    const s=sources();mutate(s.premium);
    const out=run({sourceRows:s});locked(out);
    assert.equal(out.reason,"DOMAIN_SOURCE_CONFLICT");
  }
});
test("league account requires fresh server read metadata",()=>{
  for(const mutate of [x=>delete x.cached,x=>x.cached=true,x=>x.pendingWrites=true]){
    const s=sources();mutate(s.leagueAccount);
    const out=run({sourceRows:s});locked(out);
    assert.equal(out.reason,"DOMAIN_SOURCE_CONFLICT");
  }
});
test("league week control cannot be stale cached data",()=>{
  for(const mutate of [x=>delete x.pendingWrites,x=>x.cached=true,x=>x.pendingWrites=true]){
    const s=sources();mutate(s.leagueControl);
    const out=run({sourceRows:s});locked(out);
    assert.equal(out.reason,"DOMAIN_SOURCE_CONFLICT");
  }
});
test("league score cannot be from cache or pending local writes",()=>{
  for(const mutate of [x=>delete x.cached,x=>x.cached=true,x=>x.pendingWrites=true]){
    const s=sources();mutate(s.leagueScore);
    const out=run({sourceRows:s});locked(out);
    assert.equal(out.reason,"DOMAIN_SOURCE_CONFLICT");
  }
});
test("absent week score remains unknown, not confirmed zero",()=>{
  const s=sources();delete s.leagueScore;
  const out=run({sourceRows:s});locked(out);
  assert.equal(domain(out,"league").status,"LEAGUE_SCORE_MISSING_HISTORICAL_UNKNOWN");
});
test("valid existing zero gift wallet is not authorization or gift credit",()=>{
  const s=sources();s.giftWallet.balance=0;
  const out=run({sourceRows:s});locked(out);
  assert.equal(domain(out,"diamonds").status,
    "GIFT_WALLET_SHAPE_MATCHED_NOT_TOTAL_BALANCE");
  assert.equal(out.financialGrantPermitted,false);
});
test("mock server-fresh flags do not constitute independent ownership",()=>{
  const out=run({sessionUid:A});locked(out);
  assert.equal(out.decision,"HOLD_FOR_INDEPENDENT_OWNER_PROOF");
});
