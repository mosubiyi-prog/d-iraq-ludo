"use strict";
const test=require("node:test");
const assert=require("node:assert/strict");
const fs=require("node:fs"),path=require("node:path");
const {createReadOnlyStage19Callable,createPackagedReadOnlyStage19Callable}=
  require("../functions/stage19_private/stage19_owner100_readonly_NOT_EXPORTED.js");
const key="X".repeat(43)+"=";

class HttpsError extends Error {
  constructor(code,message){super(message);this.code=code;}
}
function setup({active=true,validSecret=true}={}) {
  const track={reads:0,secretAccess:0,catalog:0,dbAccess:0,definitions:[]};
  const keySecret={value(){track.secretAccess++;
    return validSecret ? key : undefined;}};
  const actualNames=Array.from({length:100},(_,i)=>"P"+
    String(i+1).padStart(3,"0"));
  const methods={
    onCall(options,handler) {
      track.definitions.push(options);
      return {options,handler};
    },
    HttpsError,
    defineSecret(name) {
      assert.equal(name,"DEDA_STAGE19_ADMIN100_AES_KEY_B64");
      return keySecret;
    },
    getFirestore(){track.dbAccess++;return {test:"memorydb"};},
    encryptedCatalog:{expected_count:100},
    decryptCatalog(catalog,keyReceived){
      assert.strictEqual(catalog,methods.encryptedCatalog);
      assert.equal(keyReceived,key);
      track.catalog++;
      return actualNames;
    },
    createReader(db,names){
      assert.equal(db.test,"memorydb");
      assert.deepEqual(names,actualNames);
      return {async readForGeneralManager(uid) {
        track.reads++;
        if(!active){
          const err=Error("private role details should NOT leak");
          err.code="permission-denied";throw err;
        }
        assert.equal(uid,"admin_verified_uid");
        return {serverConfirmed:true,total:100,
          identifiers:names.map((id,index)=>({
            sequence:index+1,identifier:"@DEDA-"+id,
            status:"available",permanentColor:null,
            ownerOriginalId:null,
          })),history:[]};
      }};
    },
  };
  const exports=createReadOnlyStage19Callable(methods);
  return {exports,track};
}
const signedReq={auth:{uid:"admin_verified_uid"},
  app:{appId:"verified.deda.test"},data:{}};

test("source wrapper exports READ-ONLY single Callable and uses Firebase Secret Manager",()=>{
  const {exports,track}=setup();
  assert.deepEqual(Object.keys(exports),["dedaStage19Exclusive100Read"]);
  assert.equal(Object.isFrozen(exports),true);
  const opts=track.definitions[0];
  assert.equal(opts.enforceAppCheck,true);
  assert.equal(opts.secrets.length,1);
  assert.equal(opts.timeoutSeconds,60);
  assert.ok(opts.maxInstances<=2);
});
test("anonymous, missing AppCheck or forged client parameters denied BEFORE secret key is touched",async()=>{
  const {exports,track}=setup();
  const fn=exports.dedaStage19Exclusive100Read.handler;
  const bad=[
    {auth:null,app:{appId:"valid"},data:{}},
    {auth:{uid:"admin_verified_uid"},app:null,data:{}},
    {auth:{uid:"admin_verified_uid"},app:{appId:""},data:{}},
    {...signedReq,data:{uid:"admin_verified_uid"}},
    {...signedReq,data:{role:"general_manager"}},
    {...signedReq,data:{ownerPrivateKeyB64:key}},
    {...signedReq,data:null},
  ];
  for(const x of bad)await assert.rejects(fn(x),
    e=>["unauthenticated","permission-denied","invalid-argument"].includes(e.code));
  assert.equal(track.secretAccess,0);
  assert.equal(track.dbAccess,0);
});
test("signed manager read returns 100 server-confirmed and nothing can write",async()=>{
  const {exports,track}=setup();
  const row=await exports.dedaStage19Exclusive100Read.handler(signedReq);
  assert.equal(row.total,100);
  assert.equal(row.identifiers.length,100);
  assert.equal(row.serverConfirmed,true);
  assert.equal(row.identifiers[0].identifier,"@DEDA-P001");
  assert.deepEqual(row.history,[]);
  assert.equal(track.secretAccess,1);
  assert.equal(track.reads,1);
});
test("revoked role is sanitized and no raw secret, manager row, or catalog data leaks",async()=>{
  const {exports,track}=setup({active:false});
  await assert.rejects(exports.dedaStage19Exclusive100Read.handler(signedReq),
    e=>e.code==="permission-denied" &&
      !e.message.includes("private role") &&
      !e.message.includes(key));
  assert.equal(track.reads,1);
});
test("missing secret denies all reads and does not load decrypted catalog",async()=>{
  const {exports,track}=setup({validSecret:false});
  await assert.rejects(exports.dedaStage19Exclusive100Read.handler(signedReq),
    e=>e.code==="unavailable");
  assert.equal(track.catalog,0);
  assert.equal(track.reads,0);
});
test("package includes encrypted real manifest, but never private key or plaintext owner list",()=>{
  const root=path.resolve(__dirname,"..");
  const target=path.join(root,"functions","stage19_private","runtime");
  const allowed=[
    "deda_intakadha_point15_identifier_ownership_admin_gifts_2026_10_19.js",
    "deda_stage19_private_exclusive_catalog_reader_2026_10_19.js",
    "deda_stage19_private_admin100_decrypt_server_only_2026_10_19.js",
    "catalogs/DEDA_GROUP001_ADMIN100_AES256GCM_2026-10-19.enc.json",
  ];
  for(const p of allowed)assert.ok(fs.existsSync(path.join(target,p)),p);
  const payload=JSON.parse(fs.readFileSync(path.join(target,
    allowed.at(-1)),"utf8"));
  assert.equal(payload.alg,"AES-256-GCM");
  assert.equal(payload.expected_count,100);
  assert.equal(typeof payload.ciphertext_b64,"string");
  assert.equal(payload.names,undefined);
  const pub=fs.readFileSync(path.join(root,"functions","index.js"),"utf8");
  assert.equal(pub.includes("stage19_owner100_readonly_NOT_EXPORTED"),false);
  assert.equal(pub.includes("dedaStage19Exclusive100Read"),false);
});
test("packaged preview factory loads ciphertext, but fails closed without actual private key",async()=>{
  const repoRoot=path.resolve(__dirname,"..");
  const src=path.join(repoRoot,"functions","stage19_private","runtime");
  assert.ok(fs.existsSync(src));
  const mock={
    onCall:(opts,fn)=>({opts,fn}),
    HttpsError,
    defineSecret:()=>({value:()=>key}),
    getFirestore:()=>({}),
  };
  const out=createPackagedReadOnlyStage19Callable(mock);
  assert.deepEqual(Object.keys(out),["dedaStage19Exclusive100Read"]);
  await assert.rejects(out.dedaStage19Exclusive100Read.fn(signedReq),
    e=>e.code==="unavailable");
});
