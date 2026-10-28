import {before,after,test} from "node:test";
import assert from "node:assert/strict";
import {initializeApp,deleteApp} from "firebase/app";
import {getAuth,connectAuthEmulator,signInAnonymously} from "firebase/auth";
import {getFirestore,connectFirestoreEmulator,
  doc,getDoc,setDoc,updateDoc,deleteDoc} from "firebase/firestore";

/* COMPLETE ORIGINAL Firestore Rules, not a QA allow-all rule copy.
 * Must reject client tampering and reading new private migration/asset HOLDs.
 */
const PROJECT="demo-deda-stage55-two-phone-hold";
if(process.env.GCLOUD_PROJECT!==PROJECT||
   process.env.FIREBASE_AUTH_EMULATOR_HOST!=="127.0.0.1:9099"||
   process.env.FIRESTORE_EMULATOR_HOST!=="127.0.0.1:8080")
 throw Error("STAGE56_ORIGINAL_RULES_EMULATOR_ONLY");
const app=initializeApp({
 projectId:PROJECT,apiKey:"stage56-emulator-only",appId:"1:1234:android:stage56"
},"stage56-client-rules-attacker");
const auth=getAuth(app);
connectAuthEmulator(auth,"http://127.0.0.1:9099",{disableWarnings:true});
const db=getFirestore(app);
connectFirestoreEmulator(db,"127.0.0.1",8080);
async function denied(action){
 await assert.rejects(action(),error=>{
  assert.match(String(error.code||error.message),/permission-denied|PERMISSION_DENIED/i);
  return true;
 });
}
before(async()=>{const u=await signInAnonymously(auth);assert.equal(u.user.isAnonymous,true);});
after(async()=>deleteApp(app));

test("01: client cannot GET/CREATE/UPDATE/DELETE private Stage56 asset provenance HOLD",async()=>{
 const r=doc(db,"deda_stage56_private_asset_provenance_holds","a".repeat(64));
 for(const op of [
  ()=>getDoc(r),
  ()=>setDoc(r,{status:"APPROVED",canMigrate:true,canCreditDiamonds:true}),
  ()=>updateDoc(r,{canTransferFrames:true}),
  ()=>deleteDoc(r)
 ])await denied(op);
});
test("02: original Stage55 HOLD and Stage54 UID binding remain denied to app clients",async()=>{
 for(const path of [
   "deda_stage55_private_two_phone_hold_reports/"+"a".repeat(64),
   "deda_stage54_private_account_bindings/stage56_uid_test_01"
 ]){
  const r=doc(db,path);
  await denied(()=>getDoc(r));
  await denied(()=>setDoc(r,{canMigrate:true,accountKey:"07701112233"}));
 }
});
