"use strict";
// Firestore EMULATOR ONLY: true optimistic transactions and concurrency.
// All 100 identifiers used in tests are synthetic (not owner's private list).
// No production deployment or real account mutations.
const test = require("node:test");
const assert = require("node:assert/strict");
const {createRequire} = require("node:module");
const {resolve, join} = require("node:path");
const {readFileSync} = require("node:fs");
const {randomBytes, createCipheriv} = require("node:crypto");
const {deflateSync} = require("node:zlib");
assert.match(process.env.FIRESTORE_EMULATOR_HOST || "",
  /^(127\.0\.0\.1|localhost):[0-9]+$/, "EMULATOR REQUIRED");

const req = createRequire(resolve(__dirname, "../functions/package.json"));
const {initializeApp, deleteApp} = req("firebase-admin/app");
const {getFirestore} = req("firebase-admin/firestore");
const {initializeTestEnvironment,assertFails} = req("@firebase/rules-unit-testing");
const {doc, getDoc, setDoc} = req("firebase/firestore");
const {createStage19ExclusiveGateway} =
  require("../tools/deda_stage19_encrypted_admin100_callable_gateway_2026_10_19.js");

const PROJECT_ID = "demo-deda-stage19-owner100-races";
const names = ["SALEM", ...Array.from({length:98},(_,i)=>"Q"+String(i+2).padStart(3,"0")), "2020"];
const ids = names.map(n=>"@DEDA-"+n);
const KEY_A = "stage19_admin_account";
const KEY_B = "stage19_user_account";
const ORIGINAL_A = "@DEDA-A9B8C7";
const ORIGINAL_B = "@DEDA-D6E5F4";
const UID_A = "stage19_gm_UID";
const UID_B = "stage19_recipient_UID";
const AAD = "DEDA|STAGE19|GROUP001|OWNER_ADMIN100|v1";
let app, db, env;

function fakeEncrypted100() {
  const key=randomBytes(32), iv=randomBytes(12);
  const payload=deflateSync(Buffer.from(JSON.stringify({
    schema:"DEDA_ADMIN_EXCLUSIVE_GROUP001",version:1,names,
  })));
  const cipher=createCipheriv("aes-256-gcm",key,iv);
  cipher.setAAD(Buffer.from(AAD,"utf8"));
  const encrypted=Buffer.concat([
    cipher.update(payload),cipher.final(),cipher.getAuthTag(),
  ]);
  return {encryptedCatalog:{
    kind:"DEDA_ADMIN_EXCLUSIVE_CATALOG_ENCRYPTED",version:1,
    alg:"AES-256-GCM",compression:"zlib",aad:AAD,
    nonce_b64:iv.toString("base64"),
    ciphertext_b64:encrypted.toString("base64"),expected_count:100,
  },ownerPrivateKeyB64:key.toString("base64")};
}

function gateway(flags={}) {
  return createStage19ExclusiveGateway({
    db,...fakeEncrypted100(),flags,
  });
}
function call(uid=UID_A,data={}) {
  return {auth:{uid},app:{appId:"deda.test.emulator.app"},data};
}
async function reset() {
  // Each node:test test runs sequentially; clearing *emulator only*.
  await env.clearFirestore();
  const b=db.batch();
  b.set(db.collection("users").doc(UID_A),{
    accountKey:KEY_A,sharePersonalId:ORIGINAL_A,
  });
  b.set(db.collection("deda_sessions").doc(UID_A),{
    uid:UID_A,accountKey:KEY_A,
  });
  b.set(db.collection("deda_share_ids").doc(ORIGINAL_A),{
    publicId:ORIGINAL_A,kind:"personal",ownerUid:UID_A,active:true,
  });
  b.set(db.collection("admins").doc(UID_A),{
    active:true,status:"active",role:"general_manager",
  });
  b.set(db.collection("admin_entry_access").doc(KEY_A),{
    accountKey:KEY_A,active:true,status:"active",
    allowedRole:"general_manager",accessType:"general_manager_gateway",
  });
  b.set(db.collection("users").doc(UID_B),{
    accountKey:KEY_B,sharePersonalId:ORIGINAL_B,
  });
  b.set(db.collection("deda_sessions").doc(UID_B),{
    uid:UID_B,accountKey:KEY_B,
  });
  b.set(db.collection("deda_share_ids").doc(ORIGINAL_B),{
    publicId:ORIGINAL_B,kind:"personal",ownerUid:UID_B,active:true,
  });
  await b.commit();
}
test.before(async()=>{
  app=initializeApp({projectId:PROJECT_ID},"stage19-exclusive-emulator-only");
  db=getFirestore(app);
  env=await initializeTestEnvironment({
    projectId:PROJECT_ID,
    firestore:{
      host:"127.0.0.1",
      port:Number(process.env.FIRESTORE_EMULATOR_HOST.split(":")[1]),
      rules:readFileSync(resolve(__dirname,"../firestore.rules"),"utf8"),
    },
  });
});
test.after(async()=>{
  if(env)await env.cleanup();
  if(app)await deleteApp(app);
});

test("server read only: ALL 100 are in original synthetic order; no phones or price",async()=>{
  await reset();
  const s=await gateway({read:true}).handle("read",call());
  assert.equal(s.serverConfirmed,true);
  assert.equal(s.total,100);
  assert.deepEqual(s.identifiers.map(x=>x.identifier),ids);
  assert.ok(s.identifiers.every(x=>x.status==="available" &&
    x.permanentColor===null));
  assert.deepEqual(s.history,[]);
  assert.ok(!JSON.stringify(s).includes(KEY_A));
});
test("reader: anonymous, nonmanager, missing AppCheck and forged data denied",async()=>{
  await reset();
  const g=gateway({read:true});
  await assert.rejects(g.handle("read",{auth:null,app:{appId:"a"},data:{}}),
    e=>e.code==="unauthenticated");
  await assert.rejects(g.handle("read",{auth:{uid:UID_A},data:{}}),
    e=>e.code==="permission-denied");
  await assert.rejects(g.handle("read",call(UID_B)),
    e=>e.code==="permission-denied");
  await assert.rejects(g.handle("read",call(UID_A,{role:"general_manager"})),
    e=>e.code==="invalid-argument");
  await db.collection("admin_entry_access").doc(KEY_A).update({active:false});
  await assert.rejects(g.handle("read",call()),e=>e.code==="permission-denied");
});
test("all 3 API operations still CLOSED unless an explicit server flag is true",async()=>{
  await reset();
  const g=gateway();
  for(const [method,data] of [
    ["read",{}],
    ["selfUse",{identifier:ids[0],color:"gold"}],
    ["gift",{identifier:ids[0],color:"gold",
      recipientOriginalId:ORIGINAL_B}],
  ]) await assert.rejects(g.handle(method,call(UID_A,data)),
    e=>e.code==="unavailable");
  assert.equal((await db.collection("deda_owned_identifier_registry")
    .doc(ids[0]).get()).exists,false);
});
test("GM self-use has one permanent color, receipt date and original ID unchanged",async()=>{
  await reset();
  const g=gateway({read:true,managerUse:true});
  const result=await g.handle("selfUse",
    call(UID_A,{identifier:ids[0],color:"diamond"}));
  assert.equal(result.serverConfirmed,true);
  assert.equal(result.permanentColor,"diamond");
  const record=(await db.collection("deda_owned_identifier_registry")
    .doc(ids[0]).get()).data();
  assert.equal(record.assignedColor,"diamond");
  assert.equal(record.acquisition,"general_manager_self_use");
  const read=await g.handle("read",call());
  assert.equal(read.identifiers[0].status,"self_used");
  assert.equal(read.identifiers[0].permanentColor,"diamond");
  assert.equal(read.history.length,1);
  assert.equal(read.history[0].kind,"self_used");
  assert.ok(Date.parse(read.history[0].grantedAt)>0);
  assert.equal((await db.collection("users").doc(UID_A).get()).data()
    .sharePersonalId,ORIGINAL_A);
});
test("real transaction RACE: two managers actions for ONE same ID -> ONE winner",async()=>{
  await reset();
  const g=gateway({read:true,managerUse:true,gift:true});
  const results=await Promise.allSettled([
    g.handle("selfUse",call(UID_A,{identifier:ids[1],color:"gold"})),
    g.handle("gift",call(UID_A,{
      identifier:ids[1],color:"pink",recipientOriginalId:ORIGINAL_B,
    })),
  ]);
  assert.equal(results.filter(x=>x.status==="fulfilled").length,1);
  assert.equal(results.filter(x=>x.status==="rejected").length,1);
  const row=(await db.collection("deda_owned_identifier_registry")
    .doc(ids[1]).get()).data();
  assert.ok(["gold","pink"].includes(row.assignedColor));
  const read=await g.handle("read",call());
  assert.equal(read.history.length,1);
  assert.equal(read.identifiers[1].permanentColor,row.assignedColor);
  assert.equal((await db.collection("deda_owned_identifier_aliases")
    .doc(ids[1]).get()).exists,true);
  assert.equal((await db.collection("users").doc(UID_B).get()).data()
    .sharePersonalId,ORIGINAL_B);
});
test("REAL transaction RACE: ten parallel gifts same ID -> exactly ONE grant",async()=>{
  await reset();
  const g=gateway({read:true,gift:true});
  const results=await Promise.allSettled(
    Array.from({length:10},(_,i)=>
      g.handle("gift",call(UID_A,{
        identifier:ids[2],color:i%2?"royal":"gold",
        recipientOriginalId:ORIGINAL_B,
      }))));
  assert.equal(results.filter(x=>x.status==="fulfilled").length,1);
  assert.equal(results.filter(x=>x.status==="rejected").length,9);
  const read=await g.handle("read",call());
  assert.equal(read.history.length,1);
  assert.equal(read.identifiers[2].status,"gifted");
  assert.ok(["gold","royal"].includes(read.identifiers[2].permanentColor));
  const original=(await db.collection("users").doc(UID_B).get()).data()
    .sharePersonalId;
  assert.equal(original,ORIGINAL_B);
});
test("even after gift, fixed color cannot be changed and owner cannot be replaced",async()=>{
  await reset();
  const g=gateway({read:true,managerUse:true,gift:true});
  await g.handle("gift",call(UID_A,{
    identifier:ids[3],color:"royal",recipientOriginalId:ORIGINAL_B,
  }));
  for(const [method,payload] of [
    ["gift",{identifier:ids[3],color:"pink",
      recipientOriginalId:ORIGINAL_A}],
    ["selfUse",{identifier:ids[3],color:"gold"}],
  ]) await assert.rejects(g.handle(method,call(UID_A,payload)),
    e=>["already-exists","failed-precondition"].includes(e.code));
  const read=await g.handle("read",call());
  assert.equal(read.identifiers[3].permanentColor,"royal");
  assert.equal(read.identifiers[3].ownerOriginalId,ORIGINAL_B);
});
test("catalog NEVER claims 'available' when global original-share or alias collisions exist",async()=>{
  await reset();
  const g=gateway({read:true});
  await db.collection("deda_share_ids").doc(ids[20]).set({
    publicId:ids[20],ownerUid:UID_B,kind:"personal",active:true,
  });
  await assert.rejects(g.handle("read",call()),
    e=>e.code==="failed-precondition" &&
      e.message==="exclusive-id-original-share-collision");
  await db.collection("deda_share_ids").doc(ids[20]).delete();
  await db.collection("deda_owned_identifier_aliases").doc(ids[21]).set({
    identifier:ids[21],originalId:ORIGINAL_B,accountKey:KEY_B,
    kind:"permanent_alias",
  });
  await assert.rejects(g.handle("read",call()),
    e=>e.code==="failed-precondition" &&
      e.message==="exclusive-id-orphan-alias");
});

test("canonical admin role revocation immediately denies private list, self-use and gifts",async()=>{
  await reset();
  const g=gateway({read:true,managerUse:true,gift:true});
  // Leave earlier admin_entry_access allowlisted, to prove a stale
  // gateway record alone can NEVER retain exclusive privileges.
  await db.collection("admins").doc(UID_A).update({role:"employee"});
  const actions=[
    ["read",{}],
    ["selfUse",{identifier:ids[7],color:"pink"}],
    ["gift",{identifier:ids[8],color:"royal",
      recipientOriginalId:ORIGINAL_B}],
  ];
  for(const [method,data] of actions) {
    await assert.rejects(g.handle(method,call(UID_A,data)),
      e=>e.code==="permission-denied");
  }
  for(const id of [ids[7],ids[8]]) {
    assert.equal((await db.collection("deda_owned_identifier_registry")
      .doc(id).get()).exists,false);
  }
});

test("real Firestore: Secret Manager read-only Cloud Callable returns 100 only for current GM",async()=>{
  await reset();
  const {createReadOnlyStage19Callable} = require(
    "../functions/stage19_private/stage19_owner100_readonly_NOT_EXPORTED.js");
  const {decryptOwnerPrivate100} = require(
    "../tools/deda_stage19_private_admin100_decrypt_server_only_2026_10_19.js");
  const {createPrivate100AdminReader} = require(
    "../tools/deda_stage19_private_exclusive_catalog_reader_2026_10_19.js");
  const fixture=fakeEncrypted100();
  let secretReads=0;
  class HttpsError extends Error {
    constructor(code,msg) {super(msg);this.code=code;}
  }
  const exports=createReadOnlyStage19Callable({
    onCall:(options,handler)=>({options,handler}),
    HttpsError,
    defineSecret:(name)=>{
      assert.equal(name,"DEDA_STAGE19_ADMIN100_AES_KEY_B64");
      return {value:()=>{secretReads++;
        return fixture.ownerPrivateKeyB64;}};
    },
    getFirestore:()=>db,
    encryptedCatalog:fixture.encryptedCatalog,
    decryptCatalog:decryptOwnerPrivate100,
    createReader:createPrivate100AdminReader,
  });
  assert.deepEqual(Object.keys(exports),["dedaStage19Exclusive100Read"]);
  const fn=exports.dedaStage19Exclusive100Read;
  assert.equal(fn.options.enforceAppCheck,true);
  assert.equal(fn.options.secrets.length,1);
  const list=await fn.handler(call());
  assert.equal(list.total,100);
  assert.deepEqual(list.identifiers.map(x=>x.identifier),ids);
  assert.equal(secretReads,1);
  await db.collection("admins").doc(UID_A).update({status:"disabled"});
  await assert.rejects(fn.handler(call()),e=>
    e.code==="permission-denied" &&
    !e.message.includes(fixture.ownerPrivateKeyB64));
  const previous=secretReads;
  await assert.rejects(fn.handler({...call(),app:null}),e=>
    e.code==="permission-denied");
  await assert.rejects(fn.handler(call(UID_A,{role:"general_manager"})),e=>
    e.code==="invalid-argument");
  assert.equal(secretReads,previous);
});

test("client Firestore SDK cannot grant a reserved ID by bypassing callables",async()=>{
  await reset();
  const client=env.authenticatedContext(UID_B).firestore();
  await assertFails(setDoc(doc(client,"deda_owned_identifier_registry",ids[4]),{
    status:"owned",identifier:ids[4],assignedColor:"pink",
  }));
  await assertFails(getDoc(doc(client,"deda_owned_identifier_registry",ids[4])));
});
