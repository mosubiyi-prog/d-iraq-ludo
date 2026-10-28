import {before,after,test} from "node:test";
import assert from "node:assert/strict";
import {initializeApp,deleteApp} from "firebase/app";
import {getAuth,connectAuthEmulator,signInAnonymously} from "firebase/auth";
import {getFirestore,connectFirestoreEmulator,doc,getDoc,setDoc,updateDoc,deleteDoc} from "firebase/firestore";
if(process.env.GCLOUD_PROJECT!=="demo-deda-weekly-xp-stage9"||
   process.env.FIREBASE_AUTH_EMULATOR_HOST!=="127.0.0.1:9099"||
   process.env.FIRESTORE_EMULATOR_HOST!=="127.0.0.1:8080")
 throw Error("STAGE63_ORIGINAL_RULES_LOCAL_ONLY");
const app=initializeApp({projectId:"demo-deda-weekly-xp-stage9",
 apiKey:"stage63-emulator-only",appId:"1:63:android:qa"},"stage63-orig-rules");
const auth=getAuth(app);
connectAuthEmulator(auth,"http://127.0.0.1:9099",{disableWarnings:true});
const db=getFirestore(app);
connectFirestoreEmulator(db,"127.0.0.1",8080);
const deny=async call=>assert.rejects(call(),e=>{
 assert.match(String(e.code||e.message),/permission-denied|PERMISSION_DENIED/i);
 return true;
});
before(async()=>assert.equal((await signInAnonymously(auth)).user.isAnonymous,true));
after(async()=>deleteApp(app));
test("31: original production rules deny GET/SET/UPDATE/DELETE frozen private QA ranking seal",async()=>{
 const ref=doc(db,"deda_weekly_stage63_private_immutable_frozen_xp_snapshots","a".repeat(64));
 await deny(()=>getDoc(ref));
 await deny(()=>setDoc(ref,{state:"APPROVED",canCreditDiamonds:true}));
 await deny(()=>updateDoc(ref,{canIssueGift:true}));
 await deny(()=>deleteDoc(ref));
});
test("32: original client cannot forge signed XP claims or private account binding",async()=>{
 for(const collection of [
  "deda_weekly_stage46_private_server_signed_task_claims",
  "deda_weekly_stage62_private_qa_auth_account_bindings"
 ]){
  const ref=doc(db,collection,"b".repeat(64));
  await deny(()=>getDoc(ref));
  await deny(()=>setDoc(ref,{canAuthorizeProduction:true,weeklyXp:999}));
 }
});
