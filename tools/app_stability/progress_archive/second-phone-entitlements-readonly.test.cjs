"use strict";
const test=require("node:test");
const assert=require("node:assert/strict");
const {createHash}=require("node:crypto");
const {readOwnedEntitlements:read,FRAMES,COLORS}=
  require("./second-phone-entitlements-readonly.cjs");
const ACCOUNT="07701234567",ORIGINAL="@DEDA-ABC123";
const O="original_owner_firebase_uid_00001";
const ID="@DEDA-ABCD12";
function fixture(){
 const docs=new Map();
 const hash=createHash("sha256").update(ACCOUNT).digest("hex");
 docs.set("deda_share_ids/"+ORIGINAL,{
   publicId:ORIGINAL,kind:"personal",active:true,ownerUid:O});
 docs.set("users/"+O,{accountKey:ACCOUNT,sharePersonalId:ORIGINAL});
 const tx={get:async path=>docs.get(path)??null};
 return {docs,tx,hash};
}
function frame(f,id=FRAMES[0]){
 f.docs.set("deda_lab_frame_receipts/"+ORIGINAL+"/frames/"+id,{
   kind:"lab_frame",publicId:ORIGINAL,frameId:id,cost:1000,
 });
 f.docs.set("deda_lab_owned_frames/"+ORIGINAL+"/frames/"+id,{
   publicId:ORIGINAL,frameId:id,receiptId:ORIGINAL+"_"+id,
 });
}
function card(f,style=COLORS[0]){
 const id=ORIGINAL+"_"+style;
 f.docs.set("deda_stage66_card_receipts/"+id,{
   kind:"card",publicId:ORIGINAL,style,cost:5000,
 });
 f.docs.set("deda_stage66_owned_cards/"+id,{
   publicId:ORIGINAL,style,receiptId:id,
 });
}
function premium(f){
 f.docs.set("deda_owned_identifier_accounts/"+f.hash,{
   accountKey:ACCOUNT,originalId:ORIGINAL,
   activeId:ID,ownedIds:[ORIGINAL,ID],
 });
 f.docs.set("deda_owned_identifier_registry/"+ID,{
   accountKey:ACCOUNT,originalId:ORIGINAL,
   identifier:ID,status:"owned",acquisition:"general_manager_gift",
 });
 f.docs.set("deda_owned_identifier_aliases/"+ID,{
   accountKey:ACCOUNT,originalId:ORIGINAL,
   identifier:ID,kind:"permanent_alias",
 });
}
test("01 no matching receipts never fabricates ownership; unknown ID ledger stays unresolved",async()=>{
 const f=fixture(),r=await read(f.tx,ACCOUNT,ORIGINAL);
 assert.deepEqual(r.ownedFrames,[]);
 assert.deepEqual(r.ownedCards,[]);
 assert.deepEqual(r.ownedPremiumIds,[]);
 assert.equal(r.premiumLedgerStatus,"missing-needs-review");
 assert.equal(r.fullySettled,false);
 assert.equal(r.spendable,false);
 assert.equal(r.grantAuthority,false);
});
test("02 actual receipt and owned record pair restores verified frame and card view only",async()=>{
 const f=fixture();
 frame(f);card(f);
 const r=await read(f.tx,ACCOUNT,ORIGINAL);
 assert.deepEqual(r.ownedFrames,[FRAMES[0]]);
 assert.deepEqual(r.ownedCards,[COLORS[0]]);
 assert.equal(r.grantAuthority,false);
});
test("03 ledger + registry + alias proves original premium ID without creating one",async()=>{
 const f=fixture();premium(f);
 const old=new Map(f.docs);
 const r=await read(f.tx,ACCOUNT,ORIGINAL);
 assert.deepEqual(r.ownedPremiumIds,[ID]);
 assert.equal(r.activePremiumId,ID);
 assert.equal(r.premiumLedgerStatus,"registry-confirmed");
 assert.deepEqual(f.docs,old);
});
test("04 a lone purchase receipt, forged price or wrong owner never counts",async()=>{
 const f=fixture();frame(f);
 let rkey="deda_lab_frame_receipts/"+ORIGINAL+"/frames/"+FRAMES[0];
 const valid=f.docs.get(rkey);
 f.docs.set(rkey,{...valid,cost:1});
 await assert.rejects(read(f.tx,ACCOUNT,ORIGINAL),/LAB_FRAME_RECEIPT/);
 f.docs.set(rkey,valid);
 f.docs.delete("deda_lab_owned_frames/"+ORIGINAL+"/frames/"+FRAMES[0]);
 await assert.rejects(read(f.tx,ACCOUNT,ORIGINAL),/LAB_FRAME_RECEIPT/);
 const g=fixture();card(g);
 const cr="deda_stage66_card_receipts/"+ORIGINAL+"_"+COLORS[0];
 g.docs.set(cr,{...g.docs.get(cr),publicId:"@DEDA-WRONG1"});
 await assert.rejects(read(g.tx,ACCOUNT,ORIGINAL),/ID_CARD_RECEIPT/);
});
test("05 client-writable native frame ownership is preserved for REVIEW, never treated as paid",async()=>{
 const f=fixture();
 f.docs.set("deda_native_account_cosmetics/"+ORIGINAL,{
   originalId:ORIGINAL,ownedFrames:[FRAMES[1]],
   pendingFrames:[FRAMES[2]],
 });
 const r=await read(f.tx,ACCOUNT,ORIGINAL);
 assert.deepEqual(r.ownedFrames,[]);
 assert.deepEqual(r.unreviewedNativeFrames,[FRAMES[1]]);
 assert.deepEqual(r.pendingNativeFrames,[FRAMES[2]]);
 assert.equal(r.fullySettled,false);
});
test("06 forged or cross-account premium ID registry and alias must fail closed",async()=>{
 const f=fixture();premium(f);
 const ledger="deda_owned_identifier_accounts/"+f.hash;
 const reg="deda_owned_identifier_registry/"+ID;
 const alias="deda_owned_identifier_aliases/"+ID;
 const row=f.docs.get(reg);
 f.docs.set(reg,{...row,accountKey:"07709999999"});
 await assert.rejects(read(f.tx,ACCOUNT,ORIGINAL),/PREMIUM_ID_REGISTRY/);
 f.docs.set(reg,row);
 const ali=f.docs.get(alias);
 f.docs.set(alias,{...ali,originalId:"@DEDA-WRONG1"});
 await assert.rejects(read(f.tx,ACCOUNT,ORIGINAL),/PREMIUM_ID_REGISTRY/);
 f.docs.set(alias,ali);
 f.docs.set(ledger,{...f.docs.get(ledger),ownedIds:[ORIGINAL,ID,ID]});
 await assert.rejects(read(f.tx,ACCOUNT,ORIGINAL),/PREMIUM_ID_ACCOUNT_LEDGER/);
});
test("07 mismatched original ID route, changed UID or shared phone number alone denies assets",async()=>{
 const f=fixture(),route="deda_share_ids/"+ORIGINAL;
 f.docs.set(route,{...f.docs.get(route),active:false});
 await assert.rejects(read(f.tx,ACCOUNT,ORIGINAL),/ORIGINAL_ID_ROUTE/);
 f.docs.set(route,{publicId:ORIGINAL,kind:"personal",active:true,ownerUid:"foreign_uid_12345"});
 await assert.rejects(read(f.tx,ACCOUNT,ORIGINAL),/ORIGINAL_ID_OWNER/);
});
test("08 all 13 receipt-backed frames and four cards can be inspected without writes",async()=>{
 const f=fixture();
 for(const id of FRAMES)frame(f,id);
 for(const color of COLORS)card(f,color);
 let reads=0;
 const r=await read({get:async path=>{reads++;return f.docs.get(path)??null;}},ACCOUNT,ORIGINAL);
 assert.equal(r.ownedFrames.length,13);
 assert.equal(r.ownedCards.length,4);
 assert.ok(reads<70);
});
