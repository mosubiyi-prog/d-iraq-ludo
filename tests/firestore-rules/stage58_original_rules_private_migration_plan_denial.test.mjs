import {before,after,test} from "node:test";
import assert from "node:assert/strict";
import {initializeApp,deleteApp} from "firebase/app";
import {getAuth,connectAuthEmulator,signInAnonymously} from "firebase/auth";
import {getFirestore,connectFirestoreEmulator,doc,getDoc,setDoc,updateDoc,deleteDoc} from "firebase/firestore";
/* Test against unchanged production firestore.rules with actual client SDK.
 * No client can create, alter, read or abort server-only rehearsal plans.
 */
const PROJECT="demo-deda-stage55-two-phone-hold";
if(process.env.GCLOUD_PROJECT!==PROJECT||
   process.env.FIREBASE_AUTH_EMULATOR_HOST!=="127.0.0.1:9099"||
   process.env.FIRESTORE_EMULATOR_HOST!=="127.0.0.1:8080")
  throw Error("STAGE58_REAL_RULES_LOCAL_EMULATOR_REQUIRED");
const app=initializeApp({projectId:PROJECT,apiKey:"stage58-test-only",appId:"1:44:android:stage58"},"stage58-original-rules-attack");
const auth=getAuth(app);
connectAuthEmulator(auth,"http://127.0.0.1:9099",{disableWarnings:true});
const db=getFirestore(app);
connectFirestoreEmulator(db,"127.0.0.1",8080);
before(async()=>{
 const u=await signInAnonymously(auth);
 assert.equal(u.user.isAnonymous,true);
});
after(async()=>deleteApp(app));
async function expectDenied(op){
 await assert.rejects(op(),error=>{
  assert.match(String(error.code||error.message),/permission-denied|PERMISSION_DENIED/i);
  return true;
 });
}
test("01: original Firestore Rules deny all GET/CREATE/UPDATE/DELETE of Stage58 private migration plans",async()=>{
 const ref=doc(db,"deda_stage58_private_cross_phone_rehearsal_plans","a".repeat(64));
 for(const attempt of [
  ()=>getDoc(ref),
  ()=>setDoc(ref,{status:"APPROVED",canMigrate:true,dataMoved:true}),
  ()=>updateDoc(ref,{status:"ABORTED_NO_TRANSFER"}),
  ()=>deleteDoc(ref),
 ])await expectDenied(attempt);
});
test("02: client cannot forge old Stage55 or Stage56 private evidence to allow transferring wallet",async()=>{
 for(const root of ["deda_stage55_private_two_phone_hold_reports",
   "deda_stage56_private_asset_provenance_holds"]){
  const ref=doc(db,root,"b".repeat(64));
  await expectDenied(()=>getDoc(ref));
  await expectDenied(()=>setDoc(ref,{canTransferWallet:true,productionReady:true}));
 }
});
