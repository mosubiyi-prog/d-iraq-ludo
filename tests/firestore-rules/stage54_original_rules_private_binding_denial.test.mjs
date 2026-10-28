import {test} from 'node:test';
import assert from 'node:assert/strict';
import {initializeApp,deleteApp} from 'firebase/app';
import {getAuth,connectAuthEmulator,signInAnonymously} from 'firebase/auth';
import {getFirestore,connectFirestoreEmulator,doc,getDoc,setDoc,deleteDoc} from 'firebase/firestore';

/* Test the original full Firestore Rules for the NEW stage54 private namespaces:
 * unauthenticated and anonymously authenticated app clients get NO access.
 * Server-only Admin SDK writes are tested separately in functions/tests.
 */
const PROJECT='demo-deda-stage54-pin-binding';
if(process.env.GCLOUD_PROJECT!==PROJECT ||
   process.env.FIREBASE_AUTH_EMULATOR_HOST!=='127.0.0.1:9099' ||
   process.env.FIRESTORE_EMULATOR_HOST!=='127.0.0.1:8080')
 throw Error('STAGE54_ORIGINAL_LIVE_SOURCE_RULES_EMULATOR_REQUIRED');
const app=initializeApp({
  projectId:PROJECT,apiKey:'stage54-local-emulator-only',
  appId:'1:999999:android:stage54-emulator-only'
},'stage54-rules-client');
const auth=getAuth(app);
connectAuthEmulator(auth,'http://127.0.0.1:9099',{disableWarnings:true});
const db=getFirestore(app);
connectFirestoreEmulator(db,'127.0.0.1',8080);

test('original Firestore rules deny SDK client GET/SET/DELETE for stage54 private binding and throttle',async()=>{
 const user=await signInAnonymously(auth);
 assert.ok(user.user.uid);
 for(const path of [
   'deda_stage54_private_account_bindings/'+user.user.uid,
   'deda_stage54_private_pin_limits/'+'a'.repeat(64),
 ]){
   const r=doc(db,path);
   for(const operation of [
      ()=>getDoc(r),
      ()=>setDoc(r,{canGrant:true,accountKey:'07701234567'}),
      ()=>deleteDoc(r),
   ])await assert.rejects(operation(),error=>{
     assert.match(String(error.code||error.message),/permission-denied|PERMISSION_DENIED/i);
     return true;
   });
 }
});
test.after(async()=>deleteApp(app));
