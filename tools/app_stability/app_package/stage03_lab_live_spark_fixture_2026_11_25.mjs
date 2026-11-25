// Lab-only, owner-authorized, fixed synthetic fixture. No rules deploy or real reward issuer.
import {createHash} from 'node:crypto';
import {createRequire} from 'node:module';
import {readFileSync} from 'node:fs';
import {initializeApp,deleteApp} from 'firebase/app';
import {initializeAuth,inMemoryPersistence,signInWithEmailAndPassword,getIdTokenResult} from 'firebase/auth';
import {initializeFirestore,memoryLocalCache,doc,getDocFromServer,writeBatch,serverTimestamp,setLogLevel} from 'firebase/firestore';
const require=createRequire(import.meta.url);
const {build,base,uid:fixtureUid,project:fixtureProject}=require('./uid-trusted-fixture.cjs');
const {markerPath}=require('./uid-spark-fixture-rules.cjs');
const projectId='deda-qa-uid-lab-20261108',uid='PLmG06Uhhheef1hDE2MLfX6DEpg2',email='deda-qa-test@example.com';
const expectedHash='705e70c89ef87374a56ed7cf1f31fc408050935b04a9b4120b8b11685872a323';
const apps=[];
let stage='preflight';
function check(ok){if(!ok)throw Error('check-failed');}
function sorted(x){return Array.isArray(x)?x.map(sorted):x!==null&&typeof x==='object'?Object.fromEntries(Object.keys(x).sort().map(k=>[k,sorted(x[k])])):x;}
const same=(a,b)=>JSON.stringify(sorted(a))===JSON.stringify(sorted(b));
async function denied(f){try{await f();}catch(e){check(e.code==='permission-denied');return;}throw Error('unexpected-permission');}
async function main(){
  check(process.env.GITHUB_REPOSITORY==='mosubiyi-prog/d-iraq-ludo'&&process.env.GITHUB_REF==='refs/heads/deda-100451-owner-admin-session-safe-repair-2026-11-20'&&process.env.GITHUB_EVENT_NAME==='push');
  check(process.env.STAGE03_LIVE_AUTHORIZED==='LAB_SYNTHETIC_ONLY');
  check(readFileSync(process.env.STAGE03_ACTIVATION_FILE,'utf8').trim()==='LAB_SYNTHETIC_ONLY');
  check(fixtureUid===uid&&fixtureProject===projectId&&base==='deda_lab_uid_authority/'+uid);
  const docs=build(),paths=Object.keys(docs),view=base+'/inventory/current';
  check(paths.length===12&&paths.every(p=>p===base||p.startsWith(base+'/'))&&docs[base]&&docs[view]);
  check(!process.env.FIRESTORE_EMULATOR_HOST&&!process.env.FIREBASE_AUTH_EMULATOR_HOST&&!process.env.FIREBASE_EMULATOR_HUB);
  const config=JSON.parse(process.env.LAB_CONFIG||'');
  check(createHash('sha256').update(JSON.stringify(sorted(config))).digest('hex')===expectedHash);
  const info=config.project_info, client=config.client[0], apiKey=client.api_key[0].current_key;
  check(info.project_id===projectId&&info.project_number==='180856267046'&&config.client.length===1&&client.client_info.mobilesdk_app_id==='1:180856267046:android:4c5670efc62169738121e7'&&client.client_info.android_client_info.package_name==='com.deda.qa.uiddevice');
  check(typeof apiKey==='string'&&/^AIza[\w-]{35}$/.test(apiKey));
  const password=process.env.LAB_PASSWORD||'';
  check(password.length>=16);
  setLogLevel('silent');
  function make(name){
    const app=initializeApp({apiKey,projectId,authDomain:projectId+'.firebaseapp.com'},name);
    apps.push(app);
    const auth=initializeAuth(app,{persistence:inMemoryPersistence});
    const db=initializeFirestore(app,{localCache:memoryLocalCache()});
    return {auth,db};
  }
  async function signIn(c){
    const result=await signInWithEmailAndPassword(c.auth,email,password);
    check(result.user.uid===uid&&result.user.email===email&&!result.user.isAnonymous);
    const token=await getIdTokenResult(result.user,true);
    check(token.claims.aud===projectId&&token.claims.iss==='https://securetoken.google.com/'+projectId&&token.claims.sub===uid&&token.signInProvider==='password');
  }
  const first=make('stage03-spark-writer'),second=make('stage03-spark-reader'),unsigned=make('stage03-spark-unsigned');
  await signIn(first);await signIn(second);
  async function read(c,p){const s=await getDocFromServer(doc(c.db,p));check(!s.metadata.fromCache&&!s.metadata.hasPendingWrites);return s;}
  async function protection(){
    for(const p of [base,view])await denied(()=>read(unsigned,p));
    for(const p of [markerPath,...paths.filter(p=>p!==base&&p!==view),'deda_lab_uid_authority/stage03-foreign-uid-probe'])await denied(()=>read(first,p));
  }
  stage='verify-live-read-rules';
  await protection();
  const a=await read(first,base),v=await read(first,view);
  check(a.exists()===v.exists());
  if(a.exists()){
    check(same(a.data(),docs[base])&&same(v.data(),docs[view]));
    console.log('PASS_EXISTING_EXACT_PROJECTION_NO_WRITE');
  }else{
    stage='fixed-atomic-write';
    const batch=writeBatch(first.db);
    for(const p of paths)batch.set(doc(first.db,p),p.startsWith(base+'/events/')?{...docs[p],createdAt:serverTimestamp()}:docs[p]);
    await batch.commit();
    console.log('PASS_LIVE_FIXED_SYNTHETIC_ATOMIC_WRITE',paths.length);
  }
  stage='two-independent-client-readback';
  for(const c of [first,second])for(const p of [base,view]){
    const s=await read(c,p);check(s.exists()&&same(s.data(),docs[p]));
  }
  await protection();
  console.log('PASS_LIVE_SYNTHETIC_PROGRESS_AND_OWNERSHIP_RESTORE_TWO_CLIENTS');
  console.log('PASS_LIVE_PRIVATE_AUTHORIZATION_AND_HISTORY_READ_DENIED');
  console.log('LAB_SYNTHETIC_ONLY_NO_REAL_AWARD_NO_DEPLOY');
}
try{await main();}catch(e){
  const code=typeof e.code==='string'&&/^[a-z0-9/-]{1,60}$/.test(e.code)?e.code:'guard-or-operation';
  console.log('BLOCK_STAGE03_SPARK_FIXTURE',stage,code);process.exitCode=1;
}finally{await Promise.allSettled(apps.map(deleteApp));}
