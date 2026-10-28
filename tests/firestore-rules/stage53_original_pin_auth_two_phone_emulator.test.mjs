import {before, after, test} from 'node:test';
import assert from 'node:assert/strict';
import {initializeApp, deleteApp} from 'firebase/app';
import {getAuth, connectAuthEmulator, signInAnonymously, signOut} from 'firebase/auth';
import {getFirestore, connectFirestoreEmulator, doc, getDoc, setDoc,
  runTransaction, updateDoc, serverTimestamp, arrayUnion} from 'firebase/firestore';

/*
 * Actual original DEDA Firestore rules + REAL Auth Emulator anonymous tokens.
 * Replays lib/deda_pin_auth.dart client document protocol, NOT the Dart UI.
 * All accounts/UIDs/PINs/install strings are disposable synthetic emulator data.
 * In particular this is NOT safe server-authoritative authentication or migration.
 */
const PROJECT='demo-deda-stage53-original-pin';
if (process.env.GCLOUD_PROJECT!==PROJECT ||
    !process.env.FIREBASE_AUTH_EMULATOR_HOST ||
    !process.env.FIRESTORE_EMULATOR_HOST ||
    process.env.FIREBASE_AUTH_EMULATOR_HOST!=='127.0.0.1:9099' ||
    process.env.FIRESTORE_EMULATOR_HOST!=='127.0.0.1:8080') {
  throw Error('stage53-emulators-required-no-real-firebase');
}
const API_KEY='stage53-disposable-emulator-only';
const ACCOUNT='07701112233';
const WRONG='07709998877';
const PIN='581742'; // synthetic never-used fixture, not user data
const BAD_PIN='111111';
const APPS=[];
let first, second, outsider, borrowed;

async function client(label) {
  const app=initializeApp({apiKey:API_KEY,authDomain:'demo-stage53.firebaseapp.com',
    projectId:PROJECT,appId:'1:123456:android:stage53-emulator-only'},label);
  APPS.push(app);
  const auth=getAuth(app);
  connectAuthEmulator(auth,'http://127.0.0.1:9099',{disableWarnings:true});
  const db=getFirestore(app);
  connectFirestoreEmulator(db,'127.0.0.1',8080);
  const cred=await signInAnonymously(auth);
  assert.ok(cred.user.isAnonymous && cred.user.uid.length>4);
  return {app,auth,db,uid:cred.user.uid};
}

function session(c, account, install) {
  return setDoc(doc(c.db,'deda_sessions',c.uid),{
    uid:c.uid, accountKey:account, installId:install,
    signedInAt:serverTimestamp(),lastSeenAt:serverTimestamp()
  });
}
function pinProof(c, account, pin) {
  return setDoc(doc(c.db,'deda_auth_attempts',c.uid),{
    uid:c.uid,accountKey:account,pin,createdAt:serverTimestamp()
  });
}
async function createAccount(c) {
  // DedaPinAuth.createAccount() transaction semantics, not an alternative login.
  await runTransaction(c.db,async tx=>{
    const dir=doc(c.db,'deda_account_directory',ACCOUNT);
    const credentials=doc(c.db,'deda_credentials',ACCOUNT);
    const existing=await tx.get(dir);
    if(existing.exists())throw Error('account-already-exists');
    tx.set(credentials,{accountKey:ACCOUNT,pin:PIN,active:true,createdUid:c.uid,
      createdAt:serverTimestamp(),updatedAt:serverTimestamp()});
    tx.set(dir,{accountKey:ACCOUNT,active:true,createdUid:c.uid,
      createdAt:serverTimestamp(),updatedAt:serverTimestamp()});
  });
  await pinProof(c,ACCOUNT,PIN);
  await session(c,ACCOUNT,'stage53-original-install-01');
  await setDoc(doc(c.db,'deda_account_profiles',ACCOUNT),{
    accountKey:ACCOUNT,name:'Synthetic emulator account',phone:ACCOUNT,
    accountType:'user',trustedInstallIds:['stage53-original-install-01'],
    createdAt:serverTimestamp(),updatedAt:serverTimestamp(),
    lastSeenAt:serverTimestamp()
  });
  await setDoc(doc(c.db,'users',c.uid),{
    name:'Synthetic emulator account',phone:ACCOUNT,accountKey:ACCOUNT,
    accountType:'user',authMethod:'deda_pin_firestore_v1',
    trustedInstallIds:['stage53-original-install-01'],
    createdAt:serverTimestamp(),updatedAt:serverTimestamp(),
    lastSeenAt:serverTimestamp()
  });
}

async function denied(operation) {
  await assert.rejects(operation, error=>{
    assert.match(String(error.code||error.message),/permission-denied|PERMISSION_DENIED/);
    return true;
  });
}
before(async()=>{
  first=await client('stage53-original-account');
  second=await client('stage53-second-phone');
  outsider=await client('stage53-outsider-phone');
});
after(async()=>{
  for(const app of APPS)await deleteApp(app);
});

test('actual anonymous Auth emulator yields different UID per app/phone',()=>{
  assert.notEqual(first.uid,second.uid);
  assert.notEqual(first.uid,outsider.uid);
  assert.notEqual(second.uid,outsider.uid);
});

test('original account creation: atomic credential/directory; valid PIN→session→profile',async()=>{
  await createAccount(first);
  const directory=await getDoc(doc(first.db,'deda_account_directory',ACCOUNT));
  assert.equal(directory.exists(),true);
  assert.equal(directory.data().createdUid,first.uid);
  const profile=await getDoc(doc(first.db,'deda_account_profiles',ACCOUNT));
  assert.equal(profile.data().accountKey,ACCOUNT);
  const sessionDoc=await getDoc(doc(first.db,'deda_sessions',first.uid));
  assert.equal(sessionDoc.data().uid,first.uid);
});

test('original PIN credentials cannot be directly read by an ordinary signed-in client',async()=>{
  await denied(getDoc(doc(first.db,'deda_credentials',ACCOUNT)));
  await denied(getDoc(doc(outsider.db,'deda_credentials',ACCOUNT)));
});

test('wrong six-digit PIN is refused at original Firestore proof boundary',async()=>{
  await denied(pinProof(second,ACCOUNT,BAD_PIN));
  await denied(session(second,ACCOUNT,'stage53-new-install-02'));
  await denied(getDoc(doc(second.db,'deda_account_profiles',ACCOUNT)));
});

test('distinct second phone can enter same canonical account after correct PIN',async()=>{
  await pinProof(second,ACCOUNT,PIN);
  await session(second,ACCOUNT,'stage53-new-install-02');
  const account=await getDoc(doc(second.db,'deda_account_profiles',ACCOUNT));
  assert.equal(account.data().accountKey,ACCOUNT);
  await setDoc(doc(second.db,'deda_account_profiles',ACCOUNT),{
    trustedInstallIds:arrayUnion('stage53-new-install-02'),
    lastSeenAt:serverTimestamp(),updatedAt:serverTimestamp()
  },{merge:true});
  const ownDoc=doc(second.db,'users',second.uid);
  await setDoc(ownDoc,{name:account.data().name,phone:ACCOUNT,
    accountKey:ACCOUNT,accountType:'user',authMethod:'deda_pin_firestore_v1',
    trustedInstallIds:['stage53-new-install-02'],
    createdAt:serverTimestamp(),updatedAt:serverTimestamp(),
    lastSeenAt:serverTimestamp()});
  assert.equal((await getDoc(ownDoc)).data().accountKey,ACCOUNT);
  assert.notEqual(first.uid,second.uid,'different Firebase UID means old UID data not automatically migrated');
});

test('unrelated account or unsigned outsider cannot directly read authenticated DEDA profile',async()=>{
  await denied(getDoc(doc(outsider.db,'deda_account_profiles',ACCOUNT)));
  await denied(pinProof(outsider,WRONG,PIN));
});

test('client can edit trusted install list under ORIGINAL rules: not server-authoritative hardware identity',async()=>{
  await updateDoc(doc(second.db,'deda_account_profiles',ACCOUNT),{
    trustedInstallIds:arrayUnion('stage53-copyable-install-03')});
  const profile=await getDoc(doc(second.db,'deda_account_profiles',ACCOUNT));
  assert.ok(profile.data().trustedInstallIds.includes('stage53-copyable-install-03'));
});

test('third anonymous UID can reuse copied install ID without PIN: security blocker, not approval',async()=>{
  borrowed=await client('stage53-copied-install');
  await session(borrowed,ACCOUNT,'stage53-copyable-install-03');
  const profile=await getDoc(doc(borrowed.db,'deda_account_profiles',ACCOUNT));
  assert.equal(profile.data().accountKey,ACCOUNT);
  assert.notEqual(borrowed.uid,first.uid);
  assert.notEqual(borrowed.uid,second.uid);
});

test('legacy PIN check is not server rate-limiting: repeated invalid client writes denied but correct PIN remains allowed',async()=>{
  const again=await client('stage53-rate-limit-probe');
  for(let n=0;n<6;n++)await denied(pinProof(again,ACCOUNT,BAD_PIN));
  await pinProof(again,ACCOUNT,PIN);
  await session(again,ACCOUNT,'stage53-confirmed-no-global-throttle');
  assert.equal((await getDoc(doc(again.db,'deda_sessions',again.uid))).data().accountKey,ACCOUNT);
});

test('new authenticated UIDs do not automatically transfer original users/{uid} row or local XP/diamonds',async()=>{
  assert.equal((await getDoc(doc(first.db,'users',first.uid))).data().accountKey,ACCOUNT);
  assert.equal((await getDoc(doc(second.db,'users',second.uid))).data().accountKey,ACCOUNT);
  // NO server XP or wallet transfer invoked by any Stage53 flow.
  // SharedPreferences data cannot exist in the Node emulator.
  assert.notEqual(first.uid,second.uid);
});
