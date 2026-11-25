// Stage 03 read-only live authority preflight, exact pinned lab client.
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
  stage='pinned-authority-read-only';
  const first=make('stage03-authority-reader');await signIn(first);
  const second=make('stage03-authority-independent');await signIn(second);
  const unauth=make('stage03-authority-unsigned');
  const root='deda_lab_uid_authority/'+uid;
  const snap=await getDocFromServer(doc(first.db,root));
  require(!snap.metadata.fromCache&&!snap.metadata.hasPendingWrites);
  const restored=await getDocFromServer(doc(second.db,root));
  require(restored.exists()===snap.exists()&&!restored.metadata.fromCache&&!restored.metadata.hasPendingWrites);
  if(snap.exists()){
    const d=snap.data(),other=restored.data();
    require(d.accountKey===uid&&d.format===1&&d.version===4&&
      JSON.stringify(sorted(d.balances))===JSON.stringify(sorted({points:5,coins:10,xp:20,earnedDiamonds:200}))&&
      JSON.stringify(sorted(d))===JSON.stringify(sorted(other)));
    console.log('PASS_LIVE_SYNTHETIC_PROGRESS_RESTORE_TWO_CLIENTS');
  }else console.log('PASS_LIVE_AUTHORITY_ABSENCE_NOT_ZERO');
  stage='inventory-candidate-publication';
  const view=root+'/inventory/current';
  let inv;
  try{inv=await getDocFromServer(doc(first.db,view));}
  catch(e){require(e.code==='permission-denied');console.log('HOLD_LIVE_INVENTORY_RULE_NOT_AVAILABLE');}
  if(inv){
    require(!inv.metadata.fromCache&&!inv.metadata.hasPendingWrites);
    const other=await getDocFromServer(doc(second.db,view));
    require(other.exists()===inv.exists()&&!other.metadata.fromCache&&!other.metadata.hasPendingWrites);
    if(inv.exists()){
      const d=inv.data();
      require(d.uid===uid&&d.format===1&&d.revision===1&&d.complete===true&&
        d.frames?.length===1&&d.frames[0].frameId==='FRAME_03'&&
        d.idGifts?.length===1&&d.idGifts[0].identifier==='@DEDA-QAFIXTURE'&&d.idGifts[0].acceptance===null&&
        d.diamondGifts?.length===1&&d.diamondGifts[0].amount===250&&d.diamondGifts[0].status==='pending'&&
        JSON.stringify(sorted(d))===JSON.stringify(sorted(other.data())));
      console.log('PASS_LIVE_SYNTHETIC_OWNERSHIP_RESTORE_TWO_CLIENTS');
    }else console.log('HOLD_LIVE_INVENTORY_SOURCE_ABSENT');
  }
  stage='protected-read-denials';
  for(const path of [root,view])await denied(()=>getDocFromServer(doc(unauth.db,path)));
  for(const path of [root+'/inventorySources/current',root+'/inventoryHistory/1',root+'/receipts/stage03_synthetic_task_000001','deda_lab_uid_authority/stage03-foreign-uid-probe']){
    await denied(()=>getDocFromServer(doc(first.db,path)));
  }
  console.log('PASS_LIVE_PRIVATE_AUTHORITY_SOURCES_AND_FOREIGN_READ_DENIED');
  console.log('READ_ONLY_NO_AWARDS_NO_DEPLOY');
}
try{await main();}catch(e){
  const code=typeof e.code==='string'&&/^[a-z0-9/-]{1,60}$/.test(e.code)?e.code:'';
  console.log('BLOCK_STAGE03_AUTHORITY_READ',stage,code);process.exitCode=1;
}finally{await Promise.allSettled(apps.map(deleteApp));}
