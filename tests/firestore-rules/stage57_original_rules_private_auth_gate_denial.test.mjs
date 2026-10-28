import {before,after,test} from "node:test";
import assert from "node:assert/strict";
import {initializeApp,deleteApp} from "firebase/app";
import {getAuth,connectAuthEmulator,signInAnonymously} from "firebase/auth";
import {getFirestore,connectFirestoreEmulator,doc,getDoc,
 setDoc,updateDoc,deleteDoc} from "firebase/firestore";

/* Actual ORIGINAL source firestore.rules in Auth+Firestore Emulator.
 * An authenticated anonymous client can never write/approve/mutate
 * private backend-owned Stage54, Stage55 or Stage56 proof documents.
 */
const PROJECT="demo-deda-stage55-two-phone-hold";
if(process.env.GCLOUD_PROJECT!==PROJECT||
   process.env.FIRESTORE_EMULATOR_HOST!=="127.0.0.1:8080"||
   process.env.FIREBASE_AUTH_EMULATOR_HOST!=="127.0.0.1:9099")
 throw Error("STAGE57_ORIGINAL_RULES_EMULATOR_ONLY");
const app=initializeApp({
 projectId:PROJECT,apiKey:"stage57-local-only",
 appId:"1:998877:android:stage57-auth-client"
},"stage57-private-proof-rules-attacker");
const auth=getAuth(app);
connectAuthEmulator(auth,"http://127.0.0.1:9099",{disableWarnings:true});
const db=getFirestore(app);
connectFirestoreEmulator(db,"127.0.0.1",8080);
before(async()=>{
 const r=await signInAnonymously(auth);
 assert.equal(r.user.isAnonymous,true);
});
after(async()=>deleteApp(app));
async function denied(work){
 await assert.rejects(work(),e=>{
  assert.match(String(e.code||e.message),/permission-denied|PERMISSION_DENIED/i);
  return true;
 });
}
test("1: client cannot read/write Stage54 private UID account binding even with Auth",async()=>{
 const uid=auth.currentUser.uid;
 const ref=doc(db,"deda_stage54_private_account_bindings",uid);
 await denied(()=>getDoc(ref));
 await denied(()=>setDoc(ref,{accountKey:"07701112233",canMigrate:true}));
 await denied(()=>deleteDoc(ref));
});
test("2: client cannot forge Stage55/56 private report or migration approval",async()=>{
 for(const root of [
  "deda_stage55_private_two_phone_hold_reports",
  "deda_stage56_private_asset_provenance_holds"
 ]){
  const ref=doc(db,root,"a".repeat(64));
  await denied(()=>getDoc(ref));
  await denied(()=>setDoc(ref,{state:"APPROVED",canCreditDiamonds:true}));
  await denied(()=>updateDoc(ref,{productionReady:true}));
  await denied(()=>deleteDoc(ref));
 }
});
