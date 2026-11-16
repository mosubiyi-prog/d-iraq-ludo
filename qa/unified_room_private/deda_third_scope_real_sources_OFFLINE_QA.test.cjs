"use strict";
const {test}=require("node:test");
const assert=require("node:assert/strict");
const {projectDedaThirdSchema}=require("./deda_wallet_places_REAL_SCHEMA_EMULATOR_ONLY.cjs");
const A="QA_ORIGINAL_UID_A",B="QA_CREATION_UID_B",C="QA_SOCIAL_UID_C";
const originalId="@DEDA-ABC123",accountKey="9647712345678";
const cid="DEDA_QA_POINT3_CANONICAL_123456";
const room={canonicalAccountId:cid,originalId,accountKey,historicalUids:[A,B,C]};
const seed=new Map([
 ["qa_room_accounts/"+cid,room],
 ["users/"+A,{accountKey,sharePersonalId:originalId,name:"QA"}],
 ["users/"+B,{accountKey,name:"QA B"}],
 ["deda_sessions/"+A,{uid:A,accountKey}],
 ["deda_sessions/"+B,{uid:B,accountKey}],
 ["deda_share_ids/"+originalId,{publicId:originalId,active:true,kind:"personal",ownerUid:A}],
 ["deda_diamond_gift_balances/"+originalId,{publicId:originalId,balance:440,privatePin:"NEVER_OUTPUT"}]
]);
const wallet={readerUid:B,sourceUid:A,originalId,canonicalAccountId:cid,domain:"wallet"};
const places={...wallet,domain:"places"};
const published=[{id:"place-123",data:{published:true,accountKey,ownerUid:A,placeName:"PRIVATE NAME"}}];
const project=(plan,db=seed,rows=published)=>
 projectDedaThirdSchema(plan,path=>Promise.resolve(db.get(path)||null),
   (kind,ref)=>{
     assert.equal(kind,"deda_published_places_by_account");
     assert.equal(ref,accountKey);
     return Promise.resolve(rows);
   });
test("POINT3 existing gifted diamond balance is scoped, read-only and labelled",async()=>{
 const before=structuredClone([...seed.entries()]);
 assert.deepEqual(await project(wallet),{giftWalletBalance:440});
 assert.deepEqual([...seed.entries()],before);
});
test("POINT3 does not invent lost local/ad diamonds or a total balance",async()=>{
 const out=await project(wallet);
 assert.deepEqual(Object.keys(out),["giftWalletBalance"]);
 assert.ok(!("balanceDisplay" in out));
 assert.ok(!("earnedDiamonds" in out));
});
test("POINT3 unknown gift balance is HOLD, not fake zero",async()=>{
 const db=new Map(seed);db.delete("deda_diamond_gift_balances/"+originalId);
 assert.equal(await project(wallet,db),null);
});
test("POINT3 rejects mismatch of original ID owner and selected source UID",async()=>{
 const db=new Map(seed);db.set("deda_share_ids/"+originalId,
  {...seed.get("deda_share_ids/"+originalId),ownerUid:C});
 assert.equal(await project(wallet,db),null);
});
test("POINT3 rejects spoofed account identity and negative/invalid balance",async()=>{
 const db=new Map(seed);db.set("users/"+A,{accountKey:"9999999999999"});
 assert.equal(await project(wallet,db),null);
 const db2=new Map(seed);
 db2.set("deda_diamond_gift_balances/"+originalId,{publicId:originalId,balance:-1});
 assert.equal(await project(wallet,db2),null);
});
test("POINT3 published places give count only, not address/location or phone",async()=>{
 assert.deepEqual(await project(places),{publishedPlaceCount:1});
});
test("POINT3 mismatched historical owner/duplicate id HALTs, not silent split",async()=>{
 assert.equal(await project(places,seed,[{id:"p1",data:{published:true,accountKey,ownerUid:C}}]),null);
 assert.equal(await project(places,seed,[published[0],published[0]]),null);
});
test("POINT3 empty verified published list is 0, unlike unknown gift wallet",async()=>{
 assert.deepEqual(await project(places,seed,[]),{publishedPlaceCount:0});
});
test("POINT3 no account-key-only authority and no accepted other domain",async()=>{
 assert.equal(await project({...places,domain:"admin"}),null);
 assert.equal(await project({...places,readerUid:"UNREVIEWED"}),null);
 assert.equal(await project({...wallet,sourceUid:C}),null);
});
