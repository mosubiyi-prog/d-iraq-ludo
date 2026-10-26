'use strict';
// LOCAL demo only. PIN accounts/sessions/users/routes are created by the real
// Android client. Privileged writes create HISTORICAL purchase fixture data only.
const http=require('node:http'),fs=require('node:fs'),path=require('node:path');
const {createHash}=require('node:crypto');
const {initializeTestEnvironment}=require('@firebase/rules-unit-testing');
const {doc,setDoc,getDocFromServer,serverTimestamp}=require('firebase/firestore');
const project='demo-deda-live-progress-compat',account='07700000020';
if(process.env.GCLOUD_PROJECT!==project || process.env.FIRESTORE_EMULATOR_HOST!=='127.0.0.1:8080' ||
 process.env.FIREBASE_AUTH_EMULATOR_HOST!=='127.0.0.1:9099' || process.env.GOOGLE_APPLICATION_CREDENTIALS ||
 process.env.DEDA_RULES_PRIMARY_SA || process.env.DEDA_RULES_SECONDARY_SA)throw Error('local-demo-only');
const priv=process.env.DEDA_RULES_PRIVATE,pub=process.env.DEDA_RULES_PUBLIC;
if(!priv||!pub)throw Error('directories-required');
const proof=JSON.parse(fs.readFileSync(path.join(pub,'rules-compat-report.json'),'utf8'));
if(proof.status!=='emulator-passed-awaiting-release-verify'||proof.emulator.passed!==93)throw Error('policy-comparison-required');
const source=fs.readFileSync(path.join(priv,'original.private.rules'),'utf8');
if(createHash('sha256').update(source).digest('hex')!==proof.originalSHA256)throw Error('policy-hash-mismatch');
const frames=['03','05','06','07','08','09','10','11','12','13','14','15','16'].map(n=>'FRAME_'+n);
const cases=['native-original-pin-account-and-route-created-by-client','native-original-owner-reads-all-thirteen-frames',
 'native-original-gift-balance-and-history-read-by-real-backend',
 'native-same-pin-new-uid-and-new-install','native-new-device-recovers-existing-inventory-and-appearance',
 'native-new-uid-recovers-server-gift-balance-without-claiming-pending-gift',
 'native-other-account-cannot-read-original-ownership','native-original-account-recovers-after-another-login',
 'native-offline-is-an-error-not-empty-ownership','native-restoration-does-not-charge-or-rewrite-history'];
let env,original,historyHash,historyChecked=false,state={status:'waiting',passed:[],failures:[]};
function stable(d){if(Array.isArray(d))return d.map(stable);if(d&&typeof d==='object')return Object.fromEntries(Object.keys(d).sort().map(k=>[k,stable(d[k])]));return d;}
async function fingerprint(db){
 const paths=[`deda_diamond_gift_balances/${original}`,`deda_native_account_cosmetics/${original}`,
  'deda_diamond_gifts/native-owned-gift-received','deda_diamond_gifts/native-owned-gift-pending',
  ...frames.flatMap(f=>[`deda_lab_frame_receipts/${original}/frames/${f}`,`deda_lab_owned_frames/${original}/frames/${f}`])];
 const values=[];for(const p of paths)values.push([p,(await getDocFromServer(doc(db,p))).data()]);
 return createHash('sha256').update(JSON.stringify(stable(values))).digest('hex');
}
function save(){fs.writeFileSync(path.join(pub,'native-owned-result.json'),JSON.stringify({...state,projectId:project,
 realNativePlugins:true,originalDedaPinAuth:true,privilegedIdentitySeeds:false,privilegedOwnershipHistoryFixtures:true,
 originalGiftBackendReads:true,earnedBalanceMigrationTested:false,generalManagerWalletTested:false,
 actualPurchaseTested:false,physicalTwoPhonesTested:false,fullDedaUiTested:false,
 policySHA256:proof.originalSHA256,historyUnchangedVerified:state.status==='passed'&&historyChecked},null,2)+'\n');}
async function body(req){let t='';for await(const c of req){t+=c;if(t.length>8000)throw Error('oversized');}return JSON.parse(t||'{}');}
async function start(){
 env=await initializeTestEnvironment({projectId:project,firestore:{rules:source}});save();
 http.createServer(async(req,res)=>{
  try{
   if(req.method==='GET'&&req.url==='/status'){res.writeHead(200,{'content-type':'application/json'});res.end(JSON.stringify(state));return;}
   if(req.method!=='POST')throw Error('post-required');const d=await body(req);
   if(req.url==='/ownership-history'){
    if(historyHash||Object.keys(d).length!==2||typeof d.uid!=='string'||!/^[A-Za-z0-9_-]{1,128}$/.test(d.uid)||
     typeof d.original!=='string'||!/^@DEDA-[A-Z2-9]{6}$/.test(d.original))throw Error('invalid-history-request');
    original=d.original;
    await env.withSecurityRulesDisabled(async ctx=>{
     const db=ctx.firestore();
     const user=(await getDocFromServer(doc(db,`users/${d.uid}`))).data();
     const session=(await getDocFromServer(doc(db,`deda_sessions/${d.uid}`))).data();
     const route=(await getDocFromServer(doc(db,`deda_share_ids/${original}`))).data();
     if(user?.accountKey!==account||user.sharePersonalId!==original||session?.uid!==d.uid||session.accountKey!==account||
       route?.ownerUid!==d.uid||route.publicId!==original||route.kind!=='personal'||route.active!==true)throw Error('client-owner-proof-required');
     for(const frameId of frames){
      await setDoc(doc(db,`deda_lab_frame_receipts/${original}/frames/${frameId}`),{publicId:original,frameId,kind:'lab_frame',cost:1000,createdAt:serverTimestamp()});
      await setDoc(doc(db,`deda_lab_owned_frames/${original}/frames/${frameId}`),{publicId:original,frameId,receiptId:`${original}_${frameId}`,createdAt:serverTimestamp()});
     }
     await setDoc(doc(db,`deda_diamond_gift_balances/${original}`),{publicId:original,balance:42000,updatedAt:serverTimestamp()});
     await setDoc(doc(db,'deda_diamond_gifts/native-owned-gift-received'),{targetPublicId:original,amount:42000,status:'received',createdAt:serverTimestamp(),claimedAt:serverTimestamp()});
     await setDoc(doc(db,'deda_diamond_gifts/native-owned-gift-pending'),{targetPublicId:original,amount:150,status:'pending',createdAt:serverTimestamp()});
     await setDoc(doc(db,`deda_native_account_cosmetics/${original}`),{originalId:original,ownedFrames:['FRAME_05'],pendingFrames:[],
       ownedStyles:['badge_spark'],activeBadges:['badge_spark'],avatar:2,frame:7,background:1,updatedAt:serverTimestamp()});
     historyHash=await fingerprint(db);
    });
   }else if(req.url==='/check-unchanged'){
    if(Object.keys(d).length||!historyHash)throw Error('history-required');
    await env.withSecurityRulesDisabled(async ctx=>{if(await fingerprint(ctx.firestore())!==historyHash)throw Error('history-mutated');historyChecked=true;});
   }else if(req.url==='/finish'){
    if(Object.keys(d).length!==2||!Array.isArray(d.passed)||!Array.isArray(d.failures)||
      d.passed.some(n=>!cases.includes(n))||new Set(d.passed).size!==d.passed.length||
      d.failures.some(f=>!f||Object.keys(f).length!==2||!['bootstrap',...cases].includes(f.name)||!/^[-a-z0-9_]{1,60}$/.test(f.code)))throw Error('invalid-report');
    if(!d.failures.length&&(!historyChecked||d.passed.length!==cases.length))throw Error('incomplete-report');
    state={status:d.failures.length?'failed':'passed',passed:d.passed,failures:d.failures};save();
   }else throw Error('unknown-route');
   res.writeHead(200,{'content-type':'application/json'});res.end('{"ok":true}');
  }catch(_){res.writeHead(400,{'content-type':'application/json'});res.end('{"error":"local-request-rejected"}');}
 }).listen(8767,'127.0.0.1');
}
start().catch(()=>process.exit(70));
