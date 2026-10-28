import {test} from 'node:test';
import assert from 'node:assert/strict';
import {initializeApp,deleteApp} from 'firebase/app';
import {getAuth,connectAuthEmulator,signInAnonymously} from 'firebase/auth';
import {getFirestore,connectFirestoreEmulator,
  doc,getDoc,setDoc,updateDoc,deleteDoc} from 'firebase/firestore';

/* Original UNCHANGED full firestore.rules loaded in real Firestore Emulator.
 * Mobile SDK clients must not read or create fake backend migration reports.
 * This is a local source-rules check, NOT a deployed security check.
 */
const PROJECT='demo-deda-stage55-two-phone-hold';
if(process.env.GCLOUD_PROJECT!==PROJECT||
   process.env.FIREBASE_AUTH_EMULATOR_HOST!=='127.0.0.1:9099'||
   process.env.FIRESTORE_EMULATOR_HOST!=='127.0.0.1:8080')
 throw Error('STAGE55_ORIGINAL_FIRESTORE_RULES_LOCAL_EMULATOR_REQUIRED');
const app=initializeApp({
 projectId:PROJECT,apiKey:'stage55-disposable-emulator-only',
 appId:'1:998877:android:stage55-test-only'
},'stage55-original-rules-client');
const auth=getAuth(app);
connectAuthEmulator(auth,'http://127.0.0.1:9099',{disableWarnings:true});
const db=getFirestore(app);
connectFirestoreEmulator(db,'127.0.0.1',8080);
test('original DEDA mobile client denied read/create/update/delete in stage55 private hold namespace',async()=>{
 const current=await signInAnonymously(auth);
 assert.ok(current.user.isAnonymous);
 const id='a'.repeat(64);
 const r=doc(db,'deda_stage55_private_two_phone_hold_reports',id);
 for(const action of [
   ()=>getDoc(r),
   ()=>setDoc(r,{state:'FAKE_APPROVED',canCreditDiamonds:true,canMigrate:true}),
   ()=>updateDoc(r,{canCreditXp:true}),
   ()=>deleteDoc(r),
 ])await assert.rejects(action(),err=>{
   assert.match(String(err.code||err.message),/permission-denied|PERMISSION_DENIED/i);
   return true;
 });
});
test.after(async()=>deleteApp(app));
