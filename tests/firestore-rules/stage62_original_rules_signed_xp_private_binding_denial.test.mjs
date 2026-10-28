import {before,after,test} from "node:test";
import assert from "node:assert/strict";
import {initializeApp,deleteApp} from "firebase/app";
import {getAuth,connectAuthEmulator,signInAnonymously} from "firebase/auth";
import {getFirestore,connectFirestoreEmulator,doc,getDoc,setDoc,updateDoc} from "firebase/firestore";
if(process.env.GCLOUD_PROJECT!=="demo-deda-weekly-xp-stage9"||
   process.env.FIREBASE_AUTH_EMULATOR_HOST!=="127.0.0.1:9099"||
   process.env.FIRESTORE_EMULATOR_HOST!=="127.0.0.1:8080")
 throw Error("STAGE62_FIRESTORE_RULES_LOCAL_ONLY");
const app=initializeApp({projectId:"demo-deda-weekly-xp-stage9",
 apiKey:"stage62-demo-only",appId:"1:62:android:emulator"}, "stage62-original-rules-client");
const auth=getAuth(app);
connectAuthEmulator(auth,"http://127.0.0.1:9099",{disableWarnings:true});
const db=getFirestore(app);
connectFirestoreEmulator(db,"127.0.0.1",8080);
const denied=async(fn)=>assert.rejects(fn(),e=>{
 assert.match(String(e.code||e.message),/permission-denied|PERMISSION_DENIED/i);
 return true;
});
before(async()=>{assert.equal((await signInAnonymously(auth)).user.isAnonymous,true);});
after(async()=>{await deleteApp(app);});
test("17: actual original Rules deny read/create/overwrite private UID binding",async()=>{
 const ref=doc(db,"deda_weekly_stage62_private_qa_auth_account_bindings","forgeAccount");
 await denied(()=>getDoc(ref));
 await denied(()=>setDoc(ref,{accountKey:"07701234567",emulatorOnly:true}));
 await denied(()=>updateDoc(ref,{accountKey:"07709998888"}));
});
test("18: original client cannot forge signed Stage46 task claim HMAC",async()=>{
 const ref=doc(db,"deda_weekly_stage46_private_server_signed_task_claims","a".repeat(64));
 await denied(()=>getDoc(ref));
 await denied(()=>setDoc(ref,{signature:"b".repeat(64),canAuthorizeProduction:true}));
});
