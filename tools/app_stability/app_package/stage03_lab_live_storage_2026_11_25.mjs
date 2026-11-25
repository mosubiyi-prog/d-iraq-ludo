// Stage 03 live client SDK probe. Only one explicitly provisioned lab principal.
// Never deploy rules, use Admin SDK, create users, write balances, or touch production.
import {createHash} from 'node:crypto';
import {initializeApp,deleteApp} from 'firebase/app';
import {initializeAuth,inMemoryPersistence,signInWithEmailAndPassword,getIdTokenResult} from 'firebase/auth';
import {initializeFirestore,memoryLocalCache,doc,getDocFromServer,runTransaction,serverTimestamp,setLogLevel} from 'firebase/firestore';

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
  stage='first-pinned-client';
  const first=make('stage03-writer');await signIn(first);
  stage='preflight-records';
  const initial=await getDocFromServer(first.head), prior=await getDocFromServer(first.receipt);
  require(!initial.metadata.fromCache&&!prior.metadata.fromCache);
  if(initial.exists()){
    // Safe replay after interrupted CI: never overwrite a pre-existing unknown record.
    const a=checkRecord(initial),b=checkRecord(prior);require(a.updatedAt.isEqual(b.updatedAt));
    console.log('PASS_EXISTING_EXACT_SYNTHETIC_RECEIPT_NO_REWRITE');
  }else{
    require(!prior.exists());
    stage='atomic-first-save';
    await runTransaction(first.db,async tx=>{
      const old=await tx.get(first.head),receipt=await tx.get(first.receipt);
      require(!old.exists()&&!receipt.exists());
      const data={format:1,uid,version:1,mutationId,payload,updatedAt:serverTimestamp()};
      tx.set(first.head,data);tx.set(first.receipt,data);
    });
    console.log('PASS_LIVE_ATOMIC_SYNTHETIC_SAVE');
  }
  stage='writer-server-readback';
  const written=checkRecord(await getDocFromServer(first.head)),receipt=checkRecord(await getDocFromServer(first.receipt));
  require(written.updatedAt.isEqual(receipt.updatedAt));
  console.log('PASS_LIVE_HEAD_RECEIPT_SERVER_MATCH');
  stage='second-independent-client';
  const second=make('stage03-reader');await signIn(second);
  const restored=checkRecord(await getDocFromServer(second.head)),otherReceipt=checkRecord(await getDocFromServer(second.receipt));
  require(restored.updatedAt.isEqual(written.updatedAt)&&otherReceipt.updatedAt.isEqual(written.updatedAt));
  console.log('PASS_LIVE_INDEPENDENT_SAME_UID_RESTORE');
  stage='live-denial-read-only';
  const unauth=make('stage03-unsigned');
  await denied(()=>getDocFromServer(unauth.head));
  await denied(()=>getDocFromServer(doc(second.db,'deda_lab_uid_private','stage03-foreign-uid-probe')));
  console.log('PASS_LIVE_UNSIGNED_AND_FOREIGN_PATH_READ_DENIED');
  console.log('WEB_CLIENT_SDK_ONLY_NO_ANDROID_NO_FULL_APP_NO_FINANCIAL_AUTHORITY_NO_DEPLOY');
}
try{await main();}catch(e){
  const code=typeof e.code==='string'&&/^[a-z0-9/-]{1,60}$/.test(e.code)?e.code:'';
  console.log('BLOCK_STAGE03_LIVE_STORAGE',stage,code);process.exitCode=1;
}finally{await Promise.allSettled(apps.map(deleteApp));}
