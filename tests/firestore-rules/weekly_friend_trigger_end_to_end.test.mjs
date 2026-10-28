import {before,after,test} from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import {createRequire} from "node:module";
import {initializeTestEnvironment,assertSucceeds,assertFails} from "@firebase/rules-unit-testing";
import {doc,setDoc,getDoc,updateDoc,serverTimestamp} from "firebase/firestore";
const require=createRequire(import.meta.url);
const {originalClaim,ROOT}=require(
 "../../functions/deda_weekly_original_friend_accepted_action_NOT_EXPORTED.js");
const {dayInIraq}=require(
 "../../functions/deda_weekly_xp_atomic_shadow_issuer_NOT_EXPORTED.js");
const PROJECT="demo-deda-weekly-xp-stage9";
if(process.env.GCLOUD_PROJECT!==PROJECT||
   process.env.FIRESTORE_EMULATOR_HOST!=="127.0.0.1:8080"||
   process.env.FIREBASE_FUNCTIONS_EMULATOR_HOST!=="127.0.0.1:5001"||
   process.env.DEDA_WEEKLY_FRIEND_TRIGGER_EMULATOR_ONLY!=="true")
 throw Error("ORIGINAL_FRIEND_TRIGGER_E2E_LOCAL_ONLY");
const original=fs.readFileSync("../../firestore.rules","utf8");
const candidate=fs.readFileSync("../../firebase.weekly-social.candidate.rules","utf8");
assert.ok(candidate.includes("match /deda_friendships/{relationId}"));
assert.ok(!original.includes("match /deda_friendships/{relationId}"));
const A="original_e2e_friend_a",B="original_e2e_friend_b",C="original_e2e_friend_c";
const a={uid:A,account:"07701234567",id:"@DEDA-AA1111",name:"لاعب أ"};
const b={uid:B,account:"07707654321",id:"@DEDA-BB2222",name:"لاعب ب"};
const c={uid:C,account:"07705555555",id:"@DEDA-CC3333",name:"لاعب ج"};
const pair=[A,B].sort().join("__");
let env;
const auth=uid=>env.authenticatedContext(uid).firestore();
const anonymous=()=>env.unauthenticatedContext().firestore();
const profile=p=>({
 publicId:p.id,ownerUid:p.uid,displayName:p.name,
 avatarStyle:2,frameStyle:2,backgroundStyle:0,level:2,badges:[],
 createdAt:serverTimestamp(),updatedAt:serverTimestamp(),
});
const request=()=>({
 pairKey:pair,members:[A,B],requesterUid:A,recipientUid:B,
 requesterPublicId:a.id,recipientPublicId:b.id,
 requesterName:a.name,recipientName:b.name,status:"pending",
 createdAt:serverTimestamp(),updatedAt:serverTimestamp(),
});
async function adminGet(collectionId,id){
 let data;
 await env.withSecurityRulesDisabled(async x=>{
  const snap=await getDoc(doc(x.firestore(),collectionId,id));
  data=snap.exists()?snap.data():null;
 });
 return data;
}
async function until(action,maxMs=24000){
 const started=Date.now();
 for(;;){
  const result=await action();
  if(result) return result;
  if(Date.now()-started>maxMs)throw Error("E2E_TRIGGER_NOT_CALLED_AFTER_ORIGINAL_ACCEPTANCE");
  await new Promise(r=>setTimeout(r,300));
 }
}
before(async()=>{
 env=await initializeTestEnvironment({projectId:PROJECT,
  firestore:{host:"127.0.0.1",port:8080,rules:candidate}});
 await env.withSecurityRulesDisabled(async ctx=>{
  const db=ctx.firestore();
  for(const p of [a,b,c]){
   await setDoc(doc(db,"users",p.uid),{
    uid:p.uid,accountKey:p.account,sharePersonalId:p.id,name:p.name,
   });
   await setDoc(doc(db,"deda_share_ids",p.id),{
    publicId:p.id,ownerUid:p.uid,kind:"personal",active:true,
   });
   await setDoc(doc(db,"deda_sessions",p.uid),{
    uid:p.uid,accountKey:p.account,installId:p.uid+"_install",
   });
   await setDoc(doc(db,"deda_account_profiles",p.account),{
    accountKey:p.account,trustedInstallIds:[p.uid+"_install"],
   });
   await setDoc(doc(db,"users",p.uid,"wallet","original"),{
    points:316,xp:1445,coins:88,diamonds:657,
   });
  }
 });
});
after(async()=>env?.cleanup());
test("REAL CLIENT: original pending send does not create XP, proof or grant",async()=>{
 for(const p of [a,b])await assertSucceeds(setDoc(
  doc(auth(p.uid),"deda_social_profiles",p.id),profile(p)));
 await assertSucceeds(setDoc(doc(auth(A),"deda_friendships",pair),request()));
 await new Promise(r=>setTimeout(r,600));
 const today=dayInIraq(Date.now());
 const key=originalClaim(a.account,today).eventKey;
 assert.equal(await adminGet(ROOT,key),null);
 await assertFails(setDoc(doc(auth(A),ROOT,key),{
  issuer:"pretend",xpGranted:9999,diamondsGranted:9999,
 }));
});
test("REAL CLIENT: only recipient can ACCEPT, automatic Firestore onUpdate creates two read-only proofs",async()=>{
 const ref=uid=>doc(auth(uid),"deda_friendships",pair);
 await assertFails(updateDoc(ref(A),{
  status:"accepted",updatedAt:serverTimestamp(),respondedAt:serverTimestamp(),
 }));
 await assertFails(updateDoc(ref(C),{
  status:"accepted",updatedAt:serverTimestamp(),respondedAt:serverTimestamp(),
 }));
 await assertSucceeds(updateDoc(ref(B),{
  status:"accepted",updatedAt:serverTimestamp(),respondedAt:serverTimestamp(),
 }));
 const when=Date.now(),day=dayInIraq(when);
 const keys=[originalClaim(a.account,day).eventKey,
  originalClaim(b.account,day).eventKey];
 const both=await until(async()=>{
  const one=await adminGet(ROOT,keys[0]);
  const two=await adminGet(ROOT,keys[1]);
  return one&&two?[one,two]:null;
 });
 for(const [i,proof] of both.entries()){
  assert.equal(proof.taskId,"long_trip");
  assert.equal(proof.approvedAction,"friend_accepted");
  assert.equal(proof.originalRelationId,pair);
  assert.equal(proof.eventKey,keys[i]);
  assert.equal(proof.emulatorOnly,true);
  assert.equal(proof.canAuthorizeProduction,false);
  assert.equal(proof.originalLocalClaimAwarded,"UNKNOWN_REQUIRES_MIGRATION_REVIEW");
  for(const k of ["pointsGranted","coinsGranted","xpGranted","leagueXpGranted","diamondsGranted"])
   assert.equal(proof[k],0);
 }
 for(const p of [a,b]){
  const wallet=await adminGet("users/"+p.uid+"/wallet","original");
  assert.deepEqual(wallet,{points:316,xp:1445,coins:88,diamonds:657});
 }
});
test("REAL CLIENT: third-party read/forged receipt/reaccept all fail closed",async()=>{
 await assertFails(getDoc(doc(auth(C),"deda_friendships",pair)));
 await assertFails(getDoc(doc(anonymous(),"deda_friendships",pair)));
 await assertFails(updateDoc(doc(auth(B),"deda_friendships",pair),{
  status:"accepted",updatedAt:serverTimestamp(),respondedAt:serverTimestamp(),
 }));
 const key=originalClaim(a.account,dayInIraq(Date.now())).eventKey;
 await assertFails(setDoc(doc(auth(C),ROOT,key),{
  approvedAction:"friend_accepted",xpGranted:200000,
 }));
 const proof=await adminGet(ROOT,key);
 assert.equal(proof.xpGranted,0);
});
