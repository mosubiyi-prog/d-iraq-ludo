"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {createRequire} = require("node:module");
const {resolve} = require("node:path");
const {readFileSync} = require("node:fs");
assert.match(process.env.FIRESTORE_EMULATOR_HOST || "",
    /^(127\.0\.0\.1|localhost):[0-9]+$/, "SAFE_STOP emulator required");
const projectId = "demo-deda-point16-gateway";
const req = createRequire(resolve(__dirname, "../functions/package.json"));
const {initializeApp, deleteApp} = req("firebase-admin/app");
const {getFirestore} = req("firebase-admin/firestore");
const {initializeTestEnvironment, assertFails} = req("@firebase/rules-unit-testing");
const {doc, getDoc, setDoc, updateDoc} = req("firebase/firestore");
const {accountHash} = require("../tools/deda_intakadha_point13_atomic_id_card_checkout_2026_10_19.js");
const {readOwnedIdentifiers, activateOwnedIdentifier, adminGrantReservedIdentifier,
  privateReservedCatalog, resolveIdentifierAlias, hashed} =
    require("../tools/deda_intakadha_point15_identifier_ownership_admin_gifts_2026_10_19.js");

let db;
let app;
let env;
let serial = 0;
function fresh(label) {
  serial++;
  return label + "_" + String(serial).padStart(5, "0");
}
function matchesError(code) {
  return (err) => Boolean(err && err.code === code);
}
async function registered({
  balance = 20000, account = null, uid = null, registeredUid = null,
} = {}) {
  const key = account || fresh("account");
  const currentUid = uid || fresh("user");
  const originalUid = registeredUid || currentUid;
  const publicId = "@DEDA-" + String(serial).padStart(6, "0");
  const batch = db.batch();
  batch.set(db.collection("users").doc(currentUid), {
    accountKey: key, sharePersonalId: publicId, name: "Stable User",
  });
  batch.set(db.collection("deda_sessions").doc(currentUid), {
    accountKey: key, uid: currentUid,
  });
  if (originalUid !== currentUid) {
    batch.set(db.collection("users").doc(originalUid), {accountKey: key});
  }
  batch.set(db.collection("deda_share_ids").doc(publicId), {
    publicId, kind: "personal", active: true, ownerUid: originalUid,
  });
  batch.set(db.collection("deda_diamond_gift_balances").doc(publicId), {
    publicId, balance,
  });
  await batch.commit();
  return {
    uid: currentUid, account: key, publicId,
    wallet: db.collection("deda_diamond_gift_balances").doc(publicId),
    entitlement: db.collection("deda_id_card_entitlements").doc(accountHash(key)),
  };
}
test.before(async () => {
  app = initializeApp({projectId}, "point16-gateway-emulator-only");
  db = getFirestore(app);
  env = await initializeTestEnvironment({
    projectId,
    firestore: {
      host: "127.0.0.1",
      port: Number(process.env.FIRESTORE_EMULATOR_HOST.split(":")[1]),
      rules: readFileSync(resolve(__dirname, "../firestore.rules"), "utf8"),
    },
  });
});
test.after(async () => {
  if (env) await env.cleanup();
  if (app) await deleteApp(app);
});


const {createPoint16Gateway,buildStagedCallableDefinitions} =
  require("../tools/deda_intakadha_point16_gated_callable_gateway_2026_10_19.js");
const privateNames = Array.from({length:100},(_,i)=>"R"+String(i).padStart(3,"0"));
const privateCatalog = privateReservedCatalog(privateNames);
const grantId=(i)=>"@DEDA-"+privateNames[i];
const call=(user,data={})=>({auth:{uid:user.uid},app:{appId:"verified.deda.app"},data});
const flagsAll={
  read:true, cardPurchase:true, cardUse:true, identifierUse:true,
  alias:true, adminGrant:true,
};
function gateway(flags={},catalog=null) {
  return createPoint16Gateway({db,flags,privateCatalog:catalog});
}
async function gmUser() {
  const a=await registered({balance:18000});
  await db.collection("admin_entry_access").doc(a.account).set({
    accountKey:a.account,status:"active",active:true,
    allowedRole:"general_manager",accessType:"general_manager_gateway",
  });
  return a;
}

test("default-off release gate denies ALL 7 callable methods without any write",async()=>{
 const a=await registered();const before=(await a.wallet.get()).data();
 const g=gateway();
 for(const [method,data] of [
   ["readCards",{}],["buyCard",{color:"gold",requestId:"buy_1000000"}],
   ["activateCard",{color:"gold"}],["readIdentifiers",{}],
   ["activateIdentifier",{identifier:a.publicId}],
   ["resolveAlias",{identifier:a.publicId}],
   ["adminGrant",{recipientOriginalId:a.publicId,identifier:grantId(0),color:"gold"}],
 ]) await assert.rejects(g.handle(method,call(a,data)),matchesError("unavailable"));
 assert.deepEqual((await a.wallet.get()).data(),before);
 assert.equal((await a.entitlement.get()).exists,false);
});
test("authenticate AND enforce AppCheck for every call, even read-only",async()=>{
 const a=await registered();
 const g=gateway({read:true,alias:true});
 await assert.rejects(g.handle("readCards",{app:{appId:"ok"},data:{}}),
    matchesError("unauthenticated"));
 await assert.rejects(g.handle("readCards",{auth:{uid:a.uid},data:{}}),
    matchesError("permission-denied"));
 await assert.rejects(g.handle("readCards",{auth:{uid:a.uid},app:{appId:""},data:{}}),
    matchesError("permission-denied"));
 const s=await g.handle("readCards",call(a));
 assert.deepEqual(s,{identifier:a.publicId,ownedColors:[],activeColor:null});
});
test("purchase is exact 5k confirmed debit; retry idempotent without double spend",async()=>{
 const a=await registered({balance:12000});
 const g=gateway({read:true,cardPurchase:true,cardUse:true});
 const request={color:"gold",requestId:"point16_request_1000001"};
 const first=await g.handle("buyCard",call(a,request));
 assert.equal(first.serverConfirmed,true);
 assert.equal(first.diamondsCharged,5000);
 assert.equal((await a.wallet.get()).data().balance,7000);
 const second=await g.handle("buyCard",call(a,request));
 assert.deepEqual(second,first);
 assert.equal((await a.wallet.get()).data().balance,7000);
 const state=await g.handle("readCards",call(a));
 assert.deepEqual(state.ownedColors,["gold"]);
 assert.equal(state.activeColor,null);
 const used=await g.handle("activateCard",call(a,{color:"gold"}));
 assert.equal(used.activeColor,"gold");
 assert.equal((await a.wallet.get()).data().balance,7000);
});
test("wrong color, forged client price, account, UID or wallet rejected",async()=>{
 const a=await registered({balance:5000});
 const g=gateway({read:true,cardPurchase:true});
 for(const invalid of [
  {color:"gold",requestId:"point16_100002",uid:"another"},
  {color:"gold",requestId:"point16_100003",price:0},
  {color:"gold",requestId:"point16_100004",accountKey:"spoofed"},
  {color:"gold",requestId:"point16_100005",diamonds:10000},
  {color:"silver",requestId:"point16_100006"},
 ]) await assert.rejects(g.handle("buyCard",call(a,invalid)),
      matchesError("invalid-argument"));
 assert.equal((await a.wallet.get()).data().balance,5000);
});
test("card read cannot switch ownership of another user; unowned use rejected",async()=>{
 const owner=await registered({balance:20000});
 const other=await registered({balance:20000});
 const g=gateway({read:true,cardPurchase:true,cardUse:true});
 await g.handle("buyCard",call(owner,{color:"diamond",requestId:"owner_1000002"}));
 await assert.rejects(g.handle("activateCard",call(other,{color:"diamond"})),
    matchesError("permission-denied"));
 assert.deepEqual((await g.handle("readCards",call(other))).ownedColors,[]);
});
test("read identifiers returns ONLY current verified account's original ID",async()=>{
 const a=await registered();
 const g=gateway({read:true,identifierUse:true});
 const s=await g.handle("readIdentifiers",call(a));
 assert.deepEqual(s,{
   accountUid:a.uid, originalId:a.publicId,activeId:a.publicId,
   ownedIds:[a.publicId],serverConfirmed:true,
 });
 assert.equal(JSON.stringify(s).includes(a.account),false);
 await assert.rejects(g.handle("activateIdentifier",call(a,{
  identifier:"@DEDA-FAKE",
 })),matchesError("permission-denied"));
});
test("GM reserved grant requires verified backend GM and private catalog",async()=>{
 const g=await gmUser();
 const target=await registered();
 const other=await registered();
 const locked=gateway({adminGrant:true});
 await assert.rejects(locked.handle("adminGrant",call(g,{
   recipientOriginalId:target.publicId,identifier:grantId(1),color:"gold",
 })),matchesError("unavailable"));
 const enabled=gateway({read:true,adminGrant:true,identifierUse:true,alias:true},
    privateCatalog);
 await assert.rejects(enabled.handle("adminGrant",call(other,{
   recipientOriginalId:target.publicId,identifier:grantId(1),color:"gold",
 })),matchesError("permission-denied"));
 const gift=await enabled.handle("adminGrant",call(g,{
   recipientOriginalId:target.publicId,identifier:grantId(1),color:"gold",
 }));
 assert.equal(gift.giftedIdentifier,grantId(1));
 assert.equal(gift.assignedColor,"gold");
 assert.equal(gift.ownedIds[0],target.publicId);
 assert.equal((await target.wallet.get()).data().balance,20000);
});
test("GM grant cannot be spoofed via caller-supplied adminUid, role or catalog",async()=>{
 const gm=await gmUser(),target=await registered();
 const g=gateway({adminGrant:true},privateCatalog);
 for(const extra of [
  {adminUid:gm.uid},{role:"general_manager"},{privateCatalog:privateNames},
  {targetAccountKey:target.account},
 ]) await assert.rejects(g.handle("adminGrant",call(gm,{
  recipientOriginalId:target.publicId,identifier:grantId(2),
  color:"pink",...extra,
 })),matchesError("invalid-argument"));
 assert.equal((await g.handle("readIdentifiers",call(gm)).catch(e=>e.code)),
  "unavailable");
 assert.equal((await db.collection("deda_owned_identifier_registry")
  .doc(grantId(2)).get()).exists,false);
});
test("alias resolves to original ID only, never location, UID or account key",async()=>{
 const gm=await gmUser(),target=await registered();
 const g=gateway({read:true,alias:true,adminGrant:true,identifierUse:true},
   privateCatalog);
 await g.handle("adminGrant",call(gm,{
  recipientOriginalId:target.publicId,identifier:grantId(3),color:"royal",
 }));
 await g.handle("activateIdentifier",call(target,{identifier:grantId(3)}));
 for(const identifier of [grantId(3),target.publicId]){
  const result=await g.handle("resolveAlias",call(gm,{identifier}));
  assert.deepEqual(result,{originalId:target.publicId});
  const bytes=JSON.stringify(result);
  assert.equal(bytes.includes("accountKey"),false);
  assert.equal(bytes.includes("location"),false);
  assert.equal(bytes.includes(target.account),false);
  assert.equal(bytes.includes(target.uid),false);
 }
 assert.deepEqual(await g.handle("resolveAlias",call(gm,{
   identifier:"@DEDA-UNKNOWN",
 })),{originalId:null});
});
test("no public identity or location leak on unauthenticated alias request",async()=>{
 const owner=await registered();
 const g=gateway({alias:true});
 await assert.rejects(g.handle("resolveAlias",{data:{identifier:owner.publicId},
  app:{appId:"ok"}}),matchesError("unauthenticated"));
 await assert.rejects(g.handle("resolveAlias",call(owner,{
  identifier:owner.publicId,includeLocation:true,
 })),matchesError("invalid-argument"));
});
test("stale account session fails closed without changing diamonds, ID or gifts",async()=>{
 const owner=await registered();
 const g=gateway({read:true,identifierUse:true,cardPurchase:true});
 await db.collection("deda_sessions").doc(owner.uid).update({accountKey:"tampered"});
 await assert.rejects(g.handle("readIdentifiers",call(owner)),
  matchesError("permission-denied"));
 await assert.rejects(g.handle("buyCard",call(owner,{
   color:"gold",requestId:"stale_session_100",
  })),matchesError("permission-denied"));
 assert.equal((await owner.wallet.get()).data().balance,20000);
});
test("callable definitions all require enforceAppCheck with no deployment",async()=>{
 const owner=await registered();
 const g=gateway({read:true});
 const opts=[];
 class HttpsError extends Error{
  constructor(code,message){super(message);this.code=code;}
 }
 const functions=buildStagedCallableDefinitions(g,{
  onCall(options,callback){opts.push(options);return callback;},
  HttpsError,
 });
 assert.equal(Object.keys(functions).length,7);
 assert.equal(opts.every(x=>x.enforceAppCheck===true),true);
 const returned=await functions.dedaPremiumReadCards(call(owner));
 assert.equal(returned.identifier,owner.publicId);
 await assert.rejects(functions.dedaPremiumBuyCard(call(owner,{
  color:"gold",requestId:"req_1000001",accountKey:owner.account,
 })),e=>e.code==="unavailable"&&e.message==="deda-premium-unavailable");
 await assert.rejects(functions.dedaPremiumReadCards(call(owner,{
   accountKey:owner.account,
 })),e=>e.code==="invalid-argument"&&e.message==="deda-premium-invalid-argument");
});
test("unknown operation denied, no Firestore writes",async()=>{
 const owner=await registered();
 const g=gateway(flagsAll,privateCatalog);
 await assert.rejects(g.handle("dropUser",call(owner)),matchesError("unimplemented"));
 await assert.rejects(g.handle("readCards",call(owner,{targetUid:"victim"})),
  matchesError("invalid-argument"));
});
test("public rules deny direct reads/writes to new ownership, alias and entitlement",async()=>{
 const a=await registered();
 const client=env.authenticatedContext(a.uid).firestore();
 for(const [path,value] of [
   ["deda_owned_identifier_accounts/"+hashed(a.account),
     {accountKey:a.account,ownedIds:[a.publicId]}],
   ["deda_owned_identifier_aliases/"+grantId(10),{accountKey:a.account}],
   ["deda_owned_identifier_registry/"+grantId(10),{accountKey:a.account}],
   ["deda_id_card_entitlements/"+accountHash(a.account),{accountKey:a.account}],
 ]) {
   const ref=doc(client,...path.split("/"));
   await assertFails(getDoc(ref));
   await assertFails(setDoc(ref,value));
 }
});
