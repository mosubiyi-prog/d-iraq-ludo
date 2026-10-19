"use strict";
const test=require("node:test"),assert=require("node:assert/strict");
const {randomBytes,createCipheriv}=require("node:crypto");
const {deflateSync}=require("node:zlib");
const {createStage19ExclusiveGateway,stage19CallableDefinitions}=
  require("../tools/deda_stage19_encrypted_admin100_callable_gateway_2026_10_19.js");
const AAD="DEDA|STAGE19|GROUP001|OWNER_ADMIN100|v1";
const names=["SALEM",...Array.from({length:98},(_,i)=>"P"+String(i).padStart(3,"0")),"2020"];
function manifest() {
  const key=randomBytes(32),nonce=randomBytes(12);
  const plaintext=deflateSync(Buffer.from(JSON.stringify({
    schema:"DEDA_ADMIN_EXCLUSIVE_GROUP001",version:1,names,
  })));
  const cipher=createCipheriv("aes-256-gcm",key,nonce);
  cipher.setAAD(Buffer.from(AAD));
  const ciphertext=Buffer.concat([cipher.update(plaintext),
    cipher.final(),cipher.getAuthTag()]);
  return {
    privateKeyB64:key.toString("base64"),
    encryptedCatalog:{
      kind:"DEDA_ADMIN_EXCLUSIVE_CATALOG_ENCRYPTED",version:1,
      alg:"AES-256-GCM",compression:"zlib",aad:AAD,expected_count:100,
      nonce_b64:nonce.toString("base64"),
      ciphertext_b64:ciphertext.toString("base64"),
    },
  };
}
class Ref {
  constructor(path) {this.path=path;}
  doc(x) {return new Ref(this.path+"/"+x);}
}
class DB {
  constructor() {this.docs=new Map();}
  collection(x) {return new Ref(x);}
  put(p,x) {this.docs.set(p,x);}
  runTransaction(f) {return f({
    get:async(ref)=>{
      const value=this.docs.get(ref.path);
      return {exists:value!==undefined,data:()=>value};
    },
  });}
}
const original="@DEDA-X1Y2Z3";
function seed(manager=true) {
  const db=new DB();
  db.put("users/u_admin",{accountKey:"account_admin",sharePersonalId:original});
  db.put("deda_sessions/u_admin",{uid:"u_admin",accountKey:"account_admin"});
  db.put("deda_share_ids/"+original,{
    kind:"personal",active:true,publicId:original,ownerUid:"u_admin",
  });
  db.put("admin_entry_access/account_admin",{
    accountKey:"account_admin",active:true,status:"active",
    allowedRole:manager?"general_manager":"employee",
    accessType:"general_manager_gateway",
  });
  return db;
}
const authed={auth:{uid:"u_admin"},app:{appId:"test-app"},data:{}};
function svc(db,flags={}) {return createStage19ExclusiveGateway({
  db,...manifest(),flags,
});}

test("all 100 hidden while stage19 read flag off, even GM",async()=>{
  await assert.rejects(svc(seed()).handle("read",authed),
    /deda-stage19-unavailable/);
});

test("read exposes verified 100 only after manager role, app check and explicit read flag",async()=>{
  const gateway=svc(seed(),{read:true});
  const data=await gateway.handle("read",authed);
  assert.equal(data.total,100);
  assert.equal(data.serverConfirmed,true);
  assert.deepEqual(data.identifiers.map(x=>x.identifier),
    names.map(x=>"@DEDA-"+x));
  assert.ok(data.identifiers.every(x=>x.status==="available"));
});

test("non manager denied before confidential ID reads",async()=>{
  await assert.rejects(svc(seed(false),{read:true}).handle("read",authed),
    /verified-general-manager-only/);
});

test("read requires app check, valid auth and EMPTY payload",async()=>{
  const gateway=svc(seed(),{read:true});
  await assert.rejects(gateway.handle("read",{...authed,app:null}),
    /deda-stage19-permission-denied/);
  await assert.rejects(gateway.handle("read",{...authed,auth:null}),
    /deda-stage19-unauthenticated/);
  await assert.rejects(gateway.handle("read",{...authed,data:{adminUid:"u_admin"}}),
    /deda-stage19-invalid-argument/);
});

test("gift and selfUse remain off even when admin read enabled",async()=>{
  const gateway=svc(seed(),{read:true});
  await assert.rejects(gateway.handle("selfUse",{
    ...authed,data:{identifier:"@DEDA-SALEM",color:"royal"},
  }),/deda-stage19-unavailable/);
  await assert.rejects(gateway.handle("gift",{
    ...authed,data:{identifier:"@DEDA-SALEM",color:"gold",
      recipientOriginalId:"@DEDA-Z1Y2X3"},
  }),/deda-stage19-unavailable/);
});

test("callable definitions enforce App Check and wrap raw errors",async()=>{
  const definitions=stage19CallableDefinitions(svc(seed(),{read:true}),{
    onCall:(options,handler)=>({options,handler}),
    HttpsError:class HttpsError extends Error {
      constructor(code,message) {super(message);this.code=code;}
    },
  });
  assert.deepEqual(Object.keys(definitions),[
    "dedaStage19Exclusive100Read",
    "dedaStage19Exclusive100SelfUse",
    "dedaStage19Exclusive100Gift",
  ]);
  for(const fn of Object.values(definitions)) {
    assert.equal(fn.options.enforceAppCheck,true);
  }
  await assert.rejects(definitions.dedaStage19Exclusive100Read.handler({
    ...authed,app:null,
  }),err=>err.code==="permission-denied" &&
    !err.message.includes("u_admin"));
});

test("a corrupted key fails before gateway or client can read private catalog",()=>{
  const db=seed(),fixture=manifest();
  assert.throws(()=>createStage19ExclusiveGateway({
    db,encryptedCatalog:fixture.encryptedCatalog,
    ownerPrivateKeyB64:randomBytes(32).toString("base64"),
    flags:{read:true},
  }),/private-admin100-unavailable-or-invalid/);
});
