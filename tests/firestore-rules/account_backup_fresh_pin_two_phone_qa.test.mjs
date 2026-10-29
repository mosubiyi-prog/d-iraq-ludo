import {before,after,test} from 'node:test';
import assert from 'node:assert/strict';
import {initializeApp,deleteApp} from 'firebase/app';
import {getAuth,connectAuthEmulator,signInAnonymously} from 'firebase/auth';
import {getFirestore,connectFirestoreEmulator,doc,setDoc,getDoc,
  updateDoc,deleteDoc,runTransaction,serverTimestamp,
  collection,query,orderBy,limit,getDocs,arrayUnion} from 'firebase/firestore';

/**
 * Real ORIGINAL DEDA client protocol on real Firebase Auth + Firestore
 * emulators. Candidate archive rule is NOT deployed. The contents are
 * untrusted local evidence, NEVER original level XP, coins or diamonds.
 */
const PROJECT='demo-deda-account-backup-qa';
if(process.env.GCLOUD_PROJECT!==PROJECT||
   process.env.FIREBASE_AUTH_EMULATOR_HOST!=='127.0.0.1:9099'||
   process.env.FIRESTORE_EMULATOR_HOST!=='127.0.0.1:8080')
 throw Error('BACKUP_QA_REAL_FIRESTORE_AND_AUTH_EMULATORS_REQUIRED');

const ACCOUNT='07701234567',OTHER='07709876543',PIN='753184',BAD_PIN='222222';
const CAPTURE='archive_original_claims_00000001';
const INSTALL_A='deda-original-install-a',INSTALL_B='deda-second-install-b';
const apps=[];
let a,b,borrowed,outsider;
async function open(label){
 const app=initializeApp({
   projectId:PROJECT,apiKey:'backup-qa-fake-key',
   appId:'1:123456789:android:backup-qa-emulator-only',
 },label);
 apps.push(app);
 const auth=getAuth(app);
 connectAuthEmulator(auth,'http://127.0.0.1:9099',{disableWarnings:true});
 const db=getFirestore(app);
 connectFirestoreEmulator(db,'127.0.0.1',8080);
 const credential=await signInAnonymously(auth);
 return {app,auth,db,uid:credential.user.uid};
}
function ref(c,id=CAPTURE,account=ACCOUNT){
 return doc(c.db,'deda_progress_evidence',account,'captures',id);
}
function envelope(c,id=CAPTURE,install=INSTALL_A){
 return {
  format:1,kind:'legacy-local-evidence',accountKey:ACCOUNT,
  sourceUid:c.uid,installId:install,captureId:id,
  records:{
   taskPoints:JSON.stringify({points:90,awards:{'task|day|friend':{id:'test'}}}),
   socialCoinsAndXp:JSON.stringify({xp:730,coins:200}),
   earnedDiamonds:JSON.stringify({balance:1000,spend:40,reservations:[]})
  },
  createdAt:serverTimestamp()
 };
}
const denied=async operation=>assert.rejects(operation(),e=>{
 assert.match(String(e.code||e.message),/permission-denied|PERMISSION_DENIED/i);
 return true;
});
async function pinProof(c,pin=PIN,account=ACCOUNT){
 return setDoc(doc(c.db,'deda_auth_attempts',c.uid),{
  uid:c.uid,accountKey:account,pin,createdAt:serverTimestamp()
 });
}
async function session(c,account,install){
 return setDoc(doc(c.db,'deda_sessions',c.uid),{
  uid:c.uid,accountKey:account,installId:install,
  signedInAt:serverTimestamp(),lastSeenAt:serverTimestamp()
 });
}
async function userRow(c,account=ACCOUNT,install=INSTALL_A){
 return setDoc(doc(c.db,'users',c.uid),{
  name:'QA DEDA',phone:account,accountKey:account,
  accountType:'user',authMethod:'deda_pin_firestore_v1',
  trustedInstallIds:[install],
  createdAt:serverTimestamp(),updatedAt:serverTimestamp(),
  lastSeenAt:serverTimestamp()
 });
}
async function createOriginalAccount(c){
 await runTransaction(c.db,async tx=>{
  const dir=doc(c.db,'deda_account_directory',ACCOUNT);
  const cred=doc(c.db,'deda_credentials',ACCOUNT);
  if((await tx.get(dir)).exists())throw Error('duplicate-fixture-account');
  tx.set(cred,{
   accountKey:ACCOUNT,pin:PIN,active:true,createdUid:c.uid,
   createdAt:serverTimestamp(),updatedAt:serverTimestamp()
  });
  tx.set(dir,{
   accountKey:ACCOUNT,active:true,createdUid:c.uid,
   createdAt:serverTimestamp(),updatedAt:serverTimestamp()
  });
 });
 await pinProof(c);
 await session(c,ACCOUNT,INSTALL_A);
 await setDoc(doc(c.db,'deda_account_profiles',ACCOUNT),{
  accountKey:ACCOUNT,name:'QA DEDA',phone:ACCOUNT,accountType:'user',
  trustedInstallIds:[INSTALL_A],createdAt:serverTimestamp(),
  updatedAt:serverTimestamp(),lastSeenAt:serverTimestamp()
 });
 await userRow(c);
}
before(async()=>{
 a=await open('account-a-original');
 b=await open('account-b-new-phone');
 borrowed=await open('account-c-copied-install-no-pin');
 outsider=await open('account-d-unrelated');
 await createOriginalAccount(a);
});
after(async()=>{for(const app of apps)await deleteApp(app);});

test('1. Original first phone saves exact immutable raw evidence with current PIN',async()=>{
 const event=await setDoc(ref(a),envelope(a));
 assert.ok(event===undefined);
 const got=await getDoc(ref(a));
 assert.equal(got.exists(),true);
 assert.equal(got.data().accountKey,ACCOUNT);
 assert.equal(got.data().sourceUid,a.uid);
 assert.equal(got.data().records.taskPoints.includes('points'),true);
 assert.equal(got.data().records.earnedDiamonds.includes('reservations'),true);
});
test('2. New phone or unknown UID BEFORE correct PIN cannot read or upload',async()=>{
 await denied(()=>getDoc(ref(b)));
 await denied(()=>setDoc(ref(b,'unauthorized_new_phone_claim_00001'),
   envelope(b,'unauthorized_new_phone_claim_00001',INSTALL_B)));
 await denied(()=>getDoc(ref(outsider)));
 await denied(()=>getDoc(ref(outsider,CAPTURE,OTHER)));
});
test('3. Wrong PIN does not produce second-phone session or archive access',async()=>{
 await denied(()=>pinProof(b,BAD_PIN));
 await denied(()=>session(b,ACCOUNT,INSTALL_B));
 await denied(()=>getDoc(ref(b)));
});
test('4. Correct original DEDA PIN authorizes second Firebase UID to read same immutable archive',async()=>{
 assert.notEqual(a.uid,b.uid);
 await pinProof(b,PIN);
 await session(b,ACCOUNT,INSTALL_B);
 await setDoc(doc(b.db,'deda_account_profiles',ACCOUNT),{
  trustedInstallIds:arrayUnion(INSTALL_B),updatedAt:serverTimestamp(),
  lastSeenAt:serverTimestamp(),
 },{merge:true});
 await userRow(b,ACCOUNT,INSTALL_B);
 const got=await getDoc(ref(b));
 assert.equal(got.exists(),true);
 assert.equal(got.data().sourceUid,a.uid);
 assert.equal(got.data().records.taskPoints, (await getDoc(ref(a))).data().records.taskPoints);
});
test('5. Same account second phone can LIST bounded history but cannot alter source',async()=>{
 const rows=await getDocs(query(collection(b.db,'deda_progress_evidence',ACCOUNT,'captures'),
  orderBy('createdAt','desc'),limit(20)));
 assert.equal(rows.size,1);
 assert.equal(rows.docs[0].id,CAPTURE);
 await denied(()=>getDocs(query(collection(b.db,'deda_progress_evidence',ACCOUNT,'captures'),
  orderBy('createdAt','desc'),limit(50))));
 await denied(()=>updateDoc(ref(b),{'records.taskPoints':'{"points":999999}'}));
 await denied(()=>deleteDoc(ref(b)));
});
test('6. Copied original installation ID can sign into old DEDA but CANNOT read sensitive archive without PIN',async()=>{
 // Legacy weakness is explicitly reproducible in original rules; this
 // candidate closes it for progress evidence ONLY, not the entire app.
 await session(borrowed,ACCOUNT,INSTALL_A);
 await userRow(borrowed,ACCOUNT,INSTALL_A);
 assert.equal((await getDoc(doc(borrowed.db,'deda_account_profiles',ACCOUNT))).exists(),true);
 await denied(()=>getDoc(ref(borrowed)));
 await denied(()=>setDoc(ref(borrowed,'copied_install_attack_00000001'),
  envelope(borrowed,'copied_install_attack_00000001')));
});
test('7. Existing capture is immutable: retry, update and deletion denied',async()=>{
 await denied(()=>setDoc(ref(a),envelope(a)));
 await denied(()=>updateDoc(ref(a),{'records.taskPoints':'{"points":8000}'}));
 await denied(()=>deleteDoc(ref(a)));
 assert.equal((await getDoc(ref(a))).data().records.socialCoinsAndXp,
  JSON.stringify({xp:730,coins:200}));
});
test('8. Wrong actor, account, install, kind, timestamp, or extra fields rejected',async()=>{
 const shapes=[
  {sourceUid:b.uid},
  {accountKey:OTHER},
  {installId:INSTALL_B},
  {kind:'spendable-wallet-authority'},
  {createdAt:new Date('2025-01-01T00:00:00Z')},
  {canCreditDiamonds:true},
 ];
 for(let i=0;i<shapes.length;i++){
  const id='invalid_identity_or_wallet_claim_'+String(i).padStart(6,'0');
  await denied(()=>setDoc(ref(a,id),{...envelope(a,id),...shapes[i]}));
 }
});
test('9. Only the three original raw evidence parts allowed, never fabricated ledger keys',async()=>{
 const invalid=[
  {records:{taskPoints:'{}',socialCoinsAndXp:'{}'}},
  {records:{taskPoints:'{}',socialCoinsAndXp:'{}',earnedDiamonds:'{}',leagueXp:9999}},
  {records:{taskPoints:42,socialCoinsAndXp:'{}',earnedDiamonds:'{}'}},
  {records:{taskPoints:'x'.repeat(200001),socialCoinsAndXp:'{}',earnedDiamonds:'{}'}},
  {records:{taskPoints:'{}',socialCoinsAndXp:'{}',earnedDiamonds:'{}'},format:99},
 ];
 for(let i=0;i<invalid.length;i++){
  const id='invalid_records_archive_claim_'+String(i).padStart(6,'0');
  await denied(()=>setDoc(ref(a,id),{...envelope(a,id),...invalid[i]}));
 }
});
test('10. Evidence cannot fabricate original XP, ranks, gifts or diamonds',async()=>{
 const row=(await getDoc(doc(a.db,'users',a.uid))).data();
 assert.equal(row.accountKey,ACCOUNT);
 assert.equal(row.xp,undefined);
 assert.equal(row.diamonds,undefined);
 assert.equal((await getDoc(ref(b))).data().kind,'legacy-local-evidence');
 await denied(()=>setDoc(doc(a.db,'deda_weekly_private_friend_signed_frozen_top10','fake'),
  {weeklyXp:999999,diamonds:999999}));
});

test('11. Archived progress access expires after ten minutes of PIN proof and fresh PIN restores read',async()=>{
 const backdated=new Date(Date.now()-11*60*1000).toISOString();
 const rest='http://127.0.0.1:8080/v1/projects/'+PROJECT+
  '/databases/(default)/documents/deda_auth_attempts/'+b.uid+
  '?updateMask.fieldPaths=createdAt';
 const patched=await fetch(rest,{
  method:'PATCH',
  headers:{Authorization:'Bearer owner','Content-Type':'application/json'},
  body:JSON.stringify({fields:{createdAt:{timestampValue:backdated}}}),
 });
 assert.equal(patched.ok,true,'emulator-admin should backdate synthetic proof');
 await denied(()=>getDoc(ref(b)));
 await pinProof(b,PIN);
 const fresh=await getDoc(ref(b));
 assert.equal(fresh.exists(),true);
});
