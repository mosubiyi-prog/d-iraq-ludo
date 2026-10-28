"use strict";
/*
 * Actual network integration: anonymous Auth Emulator-issued ID tokens ->
 * real HTTP Functions Emulator v2 callable -> Firestore Admin SDK records,
 * including immutable Stage55 and Stage56 private HOLDs.
 * Emulator Auth JWTs are UNSIGNED. No production App Check, device proof,
 * user migration, credits, frame transfer, diamonds or prize issuance.
 */
const test=require("node:test");
const assert=require("node:assert/strict");
const {initializeApp,deleteApp}=require("firebase-admin/app");
const {getFirestore}=require("firebase-admin/firestore");
const {migrationHold,PROJECT,ROOT:ROOT55}=require(
  "../../tools/app_stability/stage55/private_two_phone_migration_hold.cjs");
const {auditAssetProvenance,ROOT:ROOT56}=require(
  "../../tools/app_stability/stage56/private_original_asset_provenance_audit.cjs");
if(process.env.GCLOUD_PROJECT!==PROJECT||
   process.env.FIRESTORE_EMULATOR_HOST!=="127.0.0.1:8080"||
   process.env.FIREBASE_AUTH_EMULATOR_HOST!=="127.0.0.1:9099"||
   process.env.FIREBASE_FUNCTIONS_EMULATOR_HOST!=="127.0.0.1:5001"||
   process.env.DEDA_STAGE55_EMULATOR_ONLY!=="true"||
   process.env.DEDA_STAGE56_EMULATOR_ONLY!=="true"||
   process.env.DEDA_STAGE57_EMULATOR_ONLY!=="true")
 throw Error("STAGE57_REQUIRES_REAL_NETWORK_LOCAL_FIREBASE_EMULATORS");
const app=initializeApp({projectId:PROJECT},"stage57-real-network-fixtures");
const db=getFirestore(app);
const ACCOUNT="07701112233",PIN="484656",OTHER="07702223334";
const SECRET=Buffer.from(process.env.STAGE57_EMULATOR_KEY_HEX,"hex");
const AUTH="http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:";
const FUNC="http://127.0.0.1:5001/"+PROJECT+
  "/us-central1/dedaStage57OriginalAnonymousMigrationReadOnlyPreflight";
const CAPTURE="stage57_original_purchase_cap_0001",RECEIPT="a".repeat(64);
const GIFT="b".repeat(64),ALIAS="@DEDA-STAGE57";
const OWNER_WALLET={diamonds:923,xp:2200,coins:55,level:13,
  purchasedFrames:["royal","gold"],premiumId:"@DEDA-ORIGINAL"};
const NEW_WALLET={diamonds:0,xp:0,coins:0,level:1,
  purchasedFrames:[],premiumId:"@DEDA-NEW"};
const SAFE_FIELDS=["canMigrate","canTransferAccount","canTransferWallet",
 "canTransferFrames","canReplacePremiumId","canCreditTaskPoints",
 "canCreditLifetimeXp","canCreditSocialCoins","canCreditLeagueXp",
 "canCreditDiamonds","canIssueWinnerGift","canSettlePurchase"];
let oldUser,newUser,outsider,passwordUser,token,originalStage55,originalStage56;
async function auth(method,body){
 const r=await fetch(AUTH+method+"?key=stage57-only-fixture",{
  method:"POST",headers:{"Content-Type":"application/json"},
  body:JSON.stringify(body)
 });
 const data=await r.json();
 if(!r.ok)throw Error("STAGE57_LOCAL_AUTH_CREATION_FAILED_"+r.status);
 assert.ok(data.localId);assert.ok(data.idToken);
 return data;
}
async function probe(user,body={},opts={}){
 const headers={"Content-Type":"application/json"};
 if(user)headers.Authorization="Bearer "+user.idToken;
 if(opts.rawAuth)headers.Authorization=opts.rawAuth;
 if(opts.appCheck)headers["X-Firebase-AppCheck"]=opts.appCheck;
 const r=await fetch(FUNC,{method:"POST",headers,
   body:JSON.stringify({data:body})});
 let result;
 try{result=await r.json();}
 catch(_){result={error:"non-json-transport-error"};}
 return {code:r.status,result};
}
function hold(r){
 assert.equal(r.code,200,JSON.stringify(r).slice(0,300));
 const v=r.result?.result;
 assert.equal(v?.readOnly,true);
 assert.equal(v?.emulatorOnly,true);
 assert.equal(v?.state,"HOLD_NEEDS_PRODUCTION_VERIFIED_AUTH_AND_APP_CHECK");
 assert.equal(v?.productionReady,false);
 assert.equal(v?.productionAppCheckVerified,false);
 assert.equal(v?.verifiedOriginalPhoneOwnership,false);
 assert.equal(v?.verifiedOldApkCutover,false);
 assert.equal(v?.verifiedAssetSettlement,false);
 for(const f of SAFE_FIELDS)assert.equal(v[f],false,f);
 const rendered=JSON.stringify(r);
 for(const secret of [ACCOUNT,PIN,oldUser.localId,newUser.localId,
   "@DEDA-ORIGINAL","923","copyable_device_string"]) {
   if(secret==="923")continue; // Numeric token may coincide by chance.
   assert.equal(rendered.includes(secret),false,"no leaked principal/private input");
 }
}
function denied(r){
 assert.notEqual(r.code,200,JSON.stringify(r).slice(0,260));
 assert.equal(r.result?.result,undefined);
 const printed=JSON.stringify(r);
 for(const privateValue of [ACCOUNT,PIN,"@DEDA-ORIGINAL"])
   assert.equal(printed.includes(privateValue),false);
}
async function prepare(){
 [oldUser,newUser,outsider,passwordUser]=await Promise.all([
  auth("signUp",{returnSecureToken:true}),
  auth("signUp",{returnSecureToken:true}),
  auth("signUp",{returnSecureToken:true}),
  auth("signUp",{email:"stage57@example.invalid",
     password:"Stage57_PRIVATE_TEST_PASSWORD_!321",returnSecureToken:true})
 ]);
 const batch=db.batch();
 const ref=p=>db.doc(p);
 batch.set(ref("deda_account_directory/"+ACCOUNT),{
   accountKey:ACCOUNT,createdUid:oldUser.localId,active:true});
 batch.set(ref("deda_account_profiles/"+ACCOUNT),{
   accountKey:ACCOUNT,name:"synthetic account",trustedInstallIds:["copyable_device_string"]});
 batch.set(ref("deda_credentials/"+ACCOUNT),{
   accountKey:ACCOUNT,pin:PIN,active:true,createdUid:oldUser.localId});
 for(const [i,u] of [oldUser,newUser].entries()){
  batch.set(ref("deda_stage54_private_account_bindings/"+u.localId),{
    uid:u.localId,accountKey:ACCOUNT,authProvider:"anonymous",
    state:"LOCAL_VERIFIED_HOLD_ONLY",emulatorOnly:true,
    canMigrate:false,canGrant:false
  });
  batch.set(ref("users/"+u.localId),{
   uid:u.localId,accountKey:ACCOUNT,authMethod:"deda_pin_firestore_v1",
   premiumId:i?"@DEDA-NEW":"@DEDA-ORIGINAL",
   diamonds:i?0:923,xp:i?0:2200
  });
  batch.set(ref("users/"+u.localId+"/wallet/original"),
   i?NEW_WALLET:OWNER_WALLET);
  batch.set(ref("deda_sessions/"+u.localId),{
   uid:u.localId,accountKey:ACCOUNT,installId:"copyable_device_string",
   signedInAt:1,lastSeenAt:1
  });
 }
 batch.set(ref("deda_admin_diamond_wallets/general_manager"),
    {diamonds:1000000,ids:["@DEDA-000001"]});
 await batch.commit();
 const s=await migrationHold({db,accountKey:ACCOUNT,
   originalUid:oldUser.localId,newPhoneUid:newUser.localId,serverKey:SECRET});
 assert.equal(s.status,"NEW_HOLD");
 const q=await auditAssetProvenance({db,accountKey:ACCOUNT,
   originalUid:oldUser.localId,newPhoneUid:newUser.localId,serverKey:SECRET,
   purchaseCaptureId:CAPTURE,receiptId:RECEIPT,giftId:GIFT,
   originalPersonalId:ALIAS});
 assert.equal(q.status,"NEW_HOLD");
 token=s.reportId;
 originalStage55=(await ref(ROOT55+"/"+token).get()).data();
 originalStage56=(await ref(ROOT56+"/"+token).get()).data();
}
test.before(prepare);
test.after(async()=>deleteApp(app));

test("01: true anonymous Auth Emulator original phone UID reads server-held chain, no grants",async()=>{
 hold(await probe(oldUser));
});
test("02: second independent original-PIN account anonymous UID sees identical HOLD",async()=>{
 const a=await probe(oldUser),b=await probe(newUser);
 hold(a);hold(b);assert.deepEqual(a.result,b.result);
 assert.notEqual(oldUser.localId,newUser.localId);
});
test("03: tokenless caller is denied",async()=>denied(await probe(null)));
test("04: unrelated anonymous Firebase account cannot borrow same copied install ID",async()=>{
 denied(await probe(outsider));
});
test("05: real password Auth Emulator UID is not original anonymous PIN session",async()=>{
 denied(await probe(passwordUser));
});
test("06: request cannot inject canonical account key",async()=>{
 denied(await probe(newUser,{accountKey:ACCOUNT}));
});
test("07: request cannot inject original or other authenticated UID",async()=>{
 for(const body of [{uid:oldUser.localId},{uid:outsider.localId}])
  denied(await probe(newUser,body));
});
test("08: request cannot inject cached install ID or mutable trustedInstallIds",async()=>{
 for(const body of [{installId:"copyable_device_string"},
   {trustedInstallIds:["copyable_device_string"]}])
   denied(await probe(newUser,body));
});
test("09: score, task, premium ID, rank or diamond manipulations denied before any IO",async()=>{
 for(const body of [
   {xp:20},{diamonds:150},{coins:10},{rank:1},
   {premiumId:"@DEDA-OWNED"},{taskId:"share_personal_location"},
   {canMigrate:true},{canTransferWallet:true},{ownerApproved:true},
  ])denied(await probe(newUser,body));
});
test("10: forged invalid Firebase bearer tokens cannot create migration authorization",async()=>{
 for(const rawAuth of ["Bearer broken","Basic faked",
   "Bearer eyJhbGciOiJub25lIn0.eyJzdWIiOiJzdGFnZTc1In0."])
   denied(await probe(null,{}, {rawAuth}));
});
test("11: fake App Check header cannot turn emulator-only HOLD into live approval",async()=>{
 const r=await probe(newUser,{},{
   appCheck:"fake-play-integrity-attestation-not-a-signed-appcheck-token"
 });
 if(r.code===200)hold(r);else denied(r);
});
test("12: mutable legacy trustedInstallIds update does not authorize a new outsider",async()=>{
 const profile=db.doc("deda_account_profiles/"+ACCOUNT);
 await profile.update({trustedInstallIds:["copied_by_outsider"]});
 denied(await probe(outsider));
 denied(await probe(newUser));
 await profile.update({trustedInstallIds:["copyable_device_string"]});
 hold(await probe(newUser));
});
test("13: user wallet manipulation invalidates Stage55 source fingerprint and fails closed",async()=>{
 const ref=db.doc("users/"+oldUser.localId+"/wallet/original");
 await ref.update({diamonds:99999999});
 denied(await probe(newUser));
 await ref.set(OWNER_WALLET);
 hold(await probe(newUser));
});
test("14: legacy client-written session install ID cannot bypass fingerprint fencing",async()=>{
 const ref=db.doc("deda_sessions/"+newUser.localId);
 await ref.update({installId:"borrowed-install-token"});
 denied(await probe(newUser));
 await ref.update({installId:"copyable_device_string"});
 hold(await probe(newUser));
});
test("15: server-held binding cannot be reassigned to another canonical account",async()=>{
 const ref=db.doc("deda_stage54_private_account_bindings/"+newUser.localId);
 await ref.update({accountKey:OTHER});
 denied(await probe(newUser));
 await ref.update({accountKey:ACCOUNT});
 hold(await probe(newUser));
});
test("16: Stage55 private HOLD cannot be edited to APPROVED and still pass",async()=>{
 const ref=db.doc(ROOT55+"/"+token);
 await ref.update({canMigrate:true});
 denied(await probe(oldUser));denied(await probe(newUser));
 await ref.set(originalStage55);
 hold(await probe(oldUser));
});
test("17: Stage56 private HOLD cannot credit diamonds or migrate when forged",async()=>{
 const ref=db.doc(ROOT56+"/"+token);
 await ref.update({canCreditDiamonds:true,productionReady:true});
 denied(await probe(newUser));
 await ref.set(originalStage56);
 hold(await probe(newUser));
});
test("18: missing stage56 report always denies rather than guessing from stage55",async()=>{
 const ref=db.doc(ROOT56+"/"+token);
 await ref.delete();
 denied(await probe(newUser));
 await ref.set(originalStage56);
 hold(await probe(newUser));
});
test("19: changed legacy original user account key breaks source digest",async()=>{
 const ref=db.doc("users/"+oldUser.localId);
 await ref.update({accountKey:OTHER});
 denied(await probe(newUser));
 await ref.update({accountKey:ACCOUNT});
 hold(await probe(newUser));
});
test("20: repeated read-only preflight requests cannot write duplicate settlements",async()=>{
 const results=await Promise.all(Array.from({length:4},()=>probe(newUser)));
 results.forEach(hold);
 assert.equal((await db.collection(ROOT55).get()).size,1);
 assert.equal((await db.collection(ROOT56).get()).size,1);
});
test("21: no user wallet, GM diamonds, original premium ID or receipts altered",async()=>{
 assert.deepEqual((await db.doc("users/"+oldUser.localId+"/wallet/original").get()).data(),OWNER_WALLET);
 assert.deepEqual((await db.doc("users/"+newUser.localId+"/wallet/original").get()).data(),NEW_WALLET);
 assert.equal((await db.doc("deda_admin_diamond_wallets/general_manager").get()).data().diamonds,1000000);
 assert.equal((await db.doc("users/"+oldUser.localId).get()).data().premiumId,"@DEDA-ORIGINAL");
 assert.equal((await db.collection("deda_progress_receipts/"+ACCOUNT+"/events").get()).size,0);
 assert.equal((await db.collection("deda_weekly_stage45_private_gift_inbox").get()).size,0);
});
test("22: no genuine AppCheck/PlayIntegrity or old APK writer cutoff can be inferred from emulator HOLD",async()=>{
 const r=await probe(oldUser);
 hold(r);
 const v=r.result.result;
 assert.equal(v.verifiedOldApkCutover,false);
 assert.equal(v.productionAppCheckVerified,false);
 assert.equal(v.verifiedAssetSettlement,false);
});
