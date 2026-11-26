// Stage 03 live authority preflight, read-only by default. Optional exact nonfinancial synthetic account seed after explicit owner publication and manual dispatch.
// Never deploy rules, use Admin SDK, create users, write balances, or touch production.
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {createRequire} from 'node:module';
const load=createRequire(import.meta.url);
const {build,buildAccount,base,uid:fixtureUid,project:fixtureProject}=load('../stage03-trusted-fixture/uid-trusted-fixture.cjs');
import {initializeApp,deleteApp} from 'firebase/app';
import {initializeAuth,inMemoryPersistence,signInWithEmailAndPassword,getIdTokenResult} from 'firebase/auth';
import {initializeFirestore,memoryLocalCache,doc,getDocFromServer,setLogLevel,writeBatch} from 'firebase/firestore';

const projectId='deda-qa-uid-lab-20261108', uid='PLmG06Uhhheef1hDE2MLfX6DEpg2', email='deda-qa-test@example.com';
const expectedHash='705e70c89ef87374a56ed7cf1f31fc408050935b04a9b4120b8b11685872a323';
const payload=JSON.stringify({favorites:['DEDA_STAGE03_LIVE_SYNTHETIC_ONLY_20261125']});
const mutationId=createHash('sha256').update(projectId+':'+uid+':'+payload).digest('hex').slice(0,48);
const apps=[];
let stage='preflight';
function require(ok){if(!ok)throw Error('check-failed');}
function sorted(x){return Array.isArray(x)?x.map(sorted):x!==null&&typeof x==='object'?Object.fromEntries(Object.keys(x).sort().map(k=>[k,sorted(x[k])])):x;}
function checkRecord(s){
  require(s.exists()&&!s.metadata.fromCache&&!s.metadata.hasPendingWrites);
  const d=s.data();
  require(Object.keys(d).sort().join(',')==='format,mutationId,payload,uid,updatedAt,version'&&d.format===1&&d.uid===uid&&d.version===1&&d.mutationId===mutationId&&d.payload===payload&&typeof d.updatedAt?.isEqual==='function');
  return d;
}
async function denied(f){
  try{await f();}catch(e){require(e.code==='permission-denied');return;}
  throw Error('unexpected-permission');
}
async function main(){
  require(!process.env.FIRESTORE_EMULATOR_HOST&&!process.env.FIREBASE_AUTH_EMULATOR_HOST&&!process.env.FIREBASE_EMULATOR_HUB);
  const config=JSON.parse(process.env.LAB_CONFIG||'');
  require(createHash('sha256').update(JSON.stringify(sorted(config))).digest('hex')===expectedHash);
  const info=config.project_info, client=config.client[0], apiKey=client.api_key[0].current_key;
  require(info.project_id===projectId&&info.project_number==='180856267046'&&config.client.length===1&&client.client_info.mobilesdk_app_id==='1:180856267046:android:4c5670efc62169738121e7'&&client.client_info.android_client_info.package_name==='com.deda.qa.uiddevice');
  require(typeof apiKey==='string'&&/^AIza[\w-]{35}$/.test(apiKey));
  const password=process.env.LAB_PASSWORD||'';
  require(password.length>=16);
  setLogLevel('silent');
  function make(name){
    const app=initializeApp({apiKey,projectId,authDomain:projectId+'.firebaseapp.com'},name);
    apps.push(app);
    const auth=initializeAuth(app,{persistence:inMemoryPersistence});
    const db=initializeFirestore(app,{localCache:memoryLocalCache()});
    return {auth,db,head:doc(db,'deda_lab_uid_private',uid),receipt:doc(db,'deda_lab_uid_private',uid,'versions',mutationId)};
  }
  async function signIn(c){
    const result=await signInWithEmailAndPassword(c.auth,email,password);
    require(result.user.uid===uid&&result.user.email===email&&!result.user.isAnonymous);
    const token=await getIdTokenResult(result.user,true);
    require(token.claims.aud===projectId&&token.claims.iss==='https://securetoken.google.com/'+projectId&&token.claims.sub===uid&&token.signInProvider==='password');
  }
  stage='pinned-authority-read-only';
  const first=make('stage03-authority-reader');await signIn(first);
  const second=make('stage03-authority-independent');await signIn(second);
  const unauth=make('stage03-authority-unsigned');
  const root='deda_lab_uid_authority/'+uid,view=root+'/inventory/current';
  require(base===root&&fixtureUid===uid&&fixtureProject===projectId);
  const expected=build(),paths=Object.keys(expected);
  require(paths.length===12&&expected[root]&&expected[view]);
  const same=(a,b)=>JSON.stringify(sorted(a))===JSON.stringify(sorted(b));
  const v3=JSON.parse(readFileSync(new URL('./uid-private-v3-fixture.json',import.meta.url),'utf8'));
  const v2={favorites:['DEDA_STAGE03_ANDROID_SYNTHETIC_ONLY_20261125']};
  let observedPrivate;
  stage='strict-post-lock-readback';
  for(const c of [first,second]){
    for(const path of [root,view]){
      const snap=await getDocFromServer(doc(c.db,path));
      require(snap.exists()&&!snap.metadata.fromCache&&!snap.metadata.hasPendingWrites&&same(snap.data(),expected[path]));
    }
    const privateHead=await getDocFromServer(c.head);
    require(privateHead.exists()&&!privateHead.metadata.fromCache&&!privateHead.metadata.hasPendingWrites);
    const d=privateHead.data();
    require(d.uid===uid&&d.format===1&&/^[a-f0-9]{48}$/.test(d.mutationId)&&
      (d.version===2||d.version===3)&&same(JSON.parse(d.payload),d.version===2?v2:v3));
    const receipt=await getDocFromServer(doc(c.db,'deda_lab_uid_private',uid,'versions',d.mutationId));
    require(receipt.exists()&&!receipt.metadata.fromCache&&!receipt.metadata.hasPendingWrites&&
      receipt.data().updatedAt.isEqual(d.updatedAt)&&same(receipt.data(),d));
    if(observedPrivate)require(same(observedPrivate,d));
    observedPrivate=d;
  }
  console.log('PASS_POST_LOCK_EXACT_PROGRESS_AND_INVENTORY_TWO_CLIENTS');
  console.log('PASS_POST_LOCK_PRIVATE_STORAGE_EXACT_VERSION',observedPrivate.version);
  stage='protected-read-denials';
  for(const path of [root,view])await denied(()=>getDocFromServer(doc(unauth.db,path)));
  for(const c of [first,second]){
    for(const path of [...paths.filter(p=>p!==root&&p!==view),'deda_lab_fixture_authorization/'+uid,'deda_lab_uid_authority/stage03-foreign-uid-probe']){
      await denied(()=>getDocFromServer(doc(c.db,path)));
    }
  }
  console.log('PASS_POST_LOCK_PRIVATE_AUTHORIZATION_HISTORY_AND_FOREIGN_READ_DENIED');
  // Root and inventory already checked and locked. Never touch them.
  const accountRows=buildAccount(),accountView=root+'/account/current';
  if(process.env.ACCOUNT_FIXTURE_AUTHORIZED==='true'){
    stage='explicit-fixed-account-only';
    const before=await getDocFromServer(doc(first.db,accountView));
    require(!before.metadata.fromCache&&!before.metadata.hasPendingWrites);
    if(before.exists()){
      require(same(before.data(),accountRows[accountView]));
      console.log('PASS_EXISTING_EXACT_ACCOUNT_NO_WRITE');
    }else{
      const batch=writeBatch(first.db);
      for(const [path,value] of Object.entries(accountRows))batch.set(doc(first.db,path),value);
      await batch.commit();
      console.log('PASS_ATOMIC_NONFINANCIAL_ACCOUNT_FIXTURE_SAVE');
    }
    stage='account-two-independent-clients';
    for(const c of [first,second]){
      const snapshot=await getDocFromServer(doc(c.db,accountView));
      require(snapshot.exists()&&!snapshot.metadata.fromCache&&!snapshot.metadata.hasPendingWrites&&same(snapshot.data(),accountRows[accountView]));
      for(const path of Object.keys(accountRows).filter(p=>p!==accountView))await denied(()=>getDocFromServer(doc(c.db,path)));
      for(const path of [root,view]){
        const snapshot=await getDocFromServer(doc(c.db,path));
        require(snapshot.exists()&&same(snapshot.data(),expected[path]));
      }
    }
    await denied(()=>getDocFromServer(doc(unauth.db,accountView)));
    console.log('PASS_EXACT_ACCOUNT_RESTORE_TWO_CLIENTS_PRIOR_AUTHORITY_UNCHANGED');
    console.log('SYNTHETIC_ACCOUNT_ONLY_NO_AWARDS_NO_DEPLOY');
  }else{
    console.log('READ_ONLY_NO_AWARDS_NO_DEPLOY');
    // Stage 04: inspect only the exact existing synthetic account's source
    // paths. No permission probing via writes, no legacy phone or historical
    // identity, no automatic publication or fixture creation.
    stage='stage04-profile-live-readiness';
    require(process.env.ACCOUNT_FIXTURE_AUTHORIZED==='false');
    require(process.env.GITHUB_REPOSITORY==='mosubiyi-prog/d-iraq-ludo'&&
      process.env.GITHUB_REF==='refs/heads/deda-100451-owner-admin-session-safe-repair-2026-11-20');
    const o=accountRows[accountView].profile.originalId;
    require(o==='@DEDA-QA1234');
    const specs=[
      ['account',accountView,d=>same(d,accountRows[accountView])],
      ['wallet-original-route','deda_share_ids/'+o,d=>d.ownerUid===uid&&d.publicId===o&&d.kind==='personal'&&d.active===true],
      ['wallet-gift-residual','deda_diamond_gift_balances/'+o,d=>d.publicId===o&&
        (!Object.hasOwn(d,'ownerUid')||d.ownerUid===uid)&&Number.isSafeInteger(d.balance)&&d.balance>=0&&d.balance<=9007199254740990],
      ['wallet-personal-residual','deda_gm_personal_diamond_wallets/'+uid,d=>d.accountKey===uid&&
        Number.isSafeInteger(d.balance)&&d.balance>=0&&d.balance<=9007199254740990],
      ['prize-request','prize_winner_requests/prize_v1_'+uid,d=>d.ownerUid===uid&&
        d.accountKey===uid&&d.cycleId==='prize_v1'&&d.dedaId===o&&typeof d.rewardCode==='string'],
    ];
    async function inspect(c,path,valid){
      try{
        const s=await getDocFromServer(doc(c.db,path));
        require(!s.metadata.fromCache&&!s.metadata.hasPendingWrites);
        if(!s.exists())return {state:'missing'};
        const value=s.data();
        return {state:valid(value)?'verified-shape':'unexpected-shape',value};
      }catch(e){
        if(e.code==='permission-denied')return {state:'read-denied'};
        throw e;
      }
    }
    const findings={};
    for(const [label,path,valid] of specs){
      const a=await inspect(first,path,valid),b=await inspect(second,path,valid);
      require(a.state===b.state);
      if(a.value!==undefined||b.value!==undefined)require(same(a.value,b.value));
      await denied(()=>getDocFromServer(doc(unauth.db,path)));
      findings[label]=a.state;
      console.log('STAGE04_LIVE_SOURCE',label,a.state);
    }
    // A successful read is not proof of issuance or mutation authorization.
    // Missing/denied residuals must not be converted into zero. Never infer
    // a real prize code from the synthetic fixture. Evidence-only outcome.
    console.log('PASS_STAGE04_PINNED_READ_ONLY_OBSERVATIONS_TWO_CLIENTS');
    if(Object.values(findings).some(s=>s==='read-denied'||s==='unexpected-shape')||
        findings.account!=='verified-shape'||findings['wallet-original-route']!=='verified-shape'||
        findings['wallet-gift-residual']!=='verified-shape'){
      console.log('BLOCK_STAGE04_LIVE_SOURCE_READINESS');
      process.exitCode=1;
    }else{
      console.log('STAGE04_LIVE_SOURCE_OBSERVED_NOT_ENTITLEMENT_OR_DEVICE_APPROVAL');
    }
    console.log('STAGE04_REAL_PRIZE_ISSUER_AND_POSITIVE_DEVICE_TEST_NOT_PROVEN');
  }
}
try{await main();}catch(e){
  const code=typeof e.code==='string'&&/^[a-z0-9/-]{1,60}$/.test(e.code)?e.code:'';
  console.log('BLOCK_STAGE03_AUTHORITY_READ',stage,code);process.exitCode=1;
}finally{await Promise.allSettled(apps.map(deleteApp));}
