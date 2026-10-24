'use strict';
// LOCAL demo-only rule loader/report and fixed approved-place fixtures.
// Never seed client identity/session/PIN/admin/wallet documents here.
const http=require('node:http'),fs=require('node:fs'),path=require('node:path');
const {createHash}=require('node:crypto');
const {initializeTestEnvironment}=require('@firebase/rules-unit-testing');
const {doc,setDoc,deleteDoc}=require('firebase/firestore');
const project='demo-deda-live-progress-compat';
if(process.env.GCLOUD_PROJECT!==project || process.env.FIRESTORE_EMULATOR_HOST!=='127.0.0.1:8080' ||
   process.env.FIREBASE_AUTH_EMULATOR_HOST!=='127.0.0.1:9099' || process.env.GOOGLE_APPLICATION_CREDENTIALS ||
   process.env.DEDA_RULES_PRIMARY_SA || process.env.DEDA_RULES_SECONDARY_SA)throw Error('isolated-demo-without-production-credentials-required');
const privateDir=process.env.DEDA_RULES_PRIVATE,publicDir=process.env.DEDA_RULES_PUBLIC;
if(!privateDir||!publicDir)throw Error('directories-required');
const proof=JSON.parse(fs.readFileSync(path.join(publicDir,'rules-compat-report.json'),'utf8'));
if(proof.status!=='emulator-passed-awaiting-release-verify'||proof.emulator.passed!==93)throw Error('node-comparison-required');
const cases=new Set(["native-bound-owner-registration", "native-bound-wrong-pin-rejected", "native-bound-fresh-uid-pin-profile-preserved", "native-bound-section-preserves-admin", "native-bound-explicit-owner-replaces-admin", "native-bound-whole-flow-blocks-other-login", "native-bound-timeout-keeps-sdk-lane", "native-bound-owner-recovery-after-timeout", "native-bound-secrets-private-no-retry", "native-bound-cold-state-prepared", "cold-bound-auth-install-and-local-state", "cold-bound-trusted-session-restore", "cold-bound-explicit-logout-preserves-local-data"]);
for(const name of ['native-place-wrong-pin-cannot-manage','native-place-new-uid-recovers-and-manages-old-place',
 'native-place-account-mismatch-rejected','native-place-other-account-cannot-claim-or-gain-admin',
 'native-place-admin-session-is-preserved','native-place-ambiguous-records-are-not-guessed',
 'cold-bound-place-recovery-keeps-original-owner'])cases.add(name);
let state={status:'waiting',passed:[],failures:[],phase:1},environment;
let placeOwnerUid=null,placeFixtureSeeded=false;
const loads=[];
function save(){fs.writeFileSync(path.join(publicDir,'native-pin-result.json'),JSON.stringify({...state,
 projectId:project,realNativePlugins:true,originalDedaPinAuth:false,boundDedaPinAuth:true,
 privilegedDocumentSeeds:placeFixtureSeeded,privilegedPublishedPlaceFixtureSeeds:placeFixtureSeeded,
 privilegedIdentitySeeds:false,
 physicalTwoPhonesTested:false,fullDedaUiTested:false,policyLoads:loads},null,2)+'\n');}
save();
async function body(req){let value='';for await(const chunk of req){value+=chunk;if(value.length>12000)throw Error('oversized-request');}return JSON.parse(value||'{}');}
const server=http.createServer(async(req,res)=>{
 try{
  if(req.method==='GET'&&req.url==='/status'){res.writeHead(200,{'content-type':'application/json'});res.end(JSON.stringify(state));return;}
  if(req.method!=='POST')throw Error('post-required');
  const data=await body(req);
  if(req.url==='/policy'){
   if(Object.keys(data).length!==1||!['original','merged'].includes(data.mode))throw Error('invalid-policy-mode');
   const source=fs.readFileSync(path.join(privateDir,data.mode==='original'?'original.private.rules':'candidate.private.rules'),'utf8');
   const sha=createHash('sha256').update(source).digest('hex');
   if(sha!==proof[data.mode==='original'?'originalSHA256':'candidateSHA256'])throw Error('private-policy-drift');
   if(environment)await environment.cleanup();
   environment=await initializeTestEnvironment({projectId:project,firestore:{rules:source}});
   loads.push({mode:data.mode,sha256:sha});save();
  }else if(req.url==='/place-fixture'){
   if(!environment||loads.length!==1||loads[0].mode!=='merged'||placeOwnerUid||
      Object.keys(data).length!==1||typeof data.ownerUid!=='string'||!/^[-A-Za-z0-9_]{20,128}$/.test(data.ownerUid))throw Error('fixed-fixture-required');
   placeOwnerUid=data.ownerUid;
   await environment.withSecurityRulesDisabled(async context=>{
    await setDoc(doc(context.firestore(),'published_places','native-approved-owner-place'),{
     accountKey:'07700000012',ownerUid:placeOwnerUid,published:true,status:'approved',
     placeName:'Synthetic approved place',approvalNumber:'NATIVE-ORIGINAL-APPROVAL',
     isAvailableNow:true,likes:17,followers:9
    });
   });
   placeFixtureSeeded=true;save();
  }else if(req.url==='/place-ambiguity'){
   if(!placeFixtureSeeded||Object.keys(data).length!==1||typeof data.enabled!=='boolean')throw Error('fixed-fixture-required');
   await environment.withSecurityRulesDisabled(async context=>{
    const ref=doc(context.firestore(),'published_places','native-duplicate-owner-place');
    if(data.enabled)await setDoc(ref,{accountKey:'07700000012',ownerUid:placeOwnerUid,published:true,status:'approved'});
    else await deleteDoc(ref);
   });
  }else if(req.url==='/checkpoint'||req.url==='/finish'){
   if(Object.keys(data).length!==3||![1,2].includes(data.phase)||!Array.isArray(data.passed)||!Array.isArray(data.failures)||
      data.passed.some(n=>!cases.has(n))||new Set(data.passed).size!==data.passed.length||
      data.failures.some(f=>!f||Object.keys(f).length!==2||typeof f.name!=='string'||typeof f.code!=='string'||!Object.keys(f).every(k=>['name','code'].includes(k))||!['bootstrap','framework','uncaught',...cases].includes(f.name)||!/^[-a-z0-9_]{1,60}$/.test(f.code)))throw Error('invalid-sanitized-report');
   const next={passed:data.passed,failures:data.failures.map(f=>({name:f.name,code:f.code})),phase:data.phase,
     status:data.failures.length?'failed':req.url==='/checkpoint'?'restart-ready':'passed'};
   if(next.status==='restart-ready'&&(data.phase!==1||data.passed.length!==16))throw Error('incomplete-checkpoint');
   if(next.status==='passed'&&(data.phase!==2||data.passed.length!==20))throw Error('incomplete-result');
   if(next.status!=='failed'&&(loads.length!==1||loads[0].mode!=='merged'))throw Error('both-native-policies-required');
   state=next;save();
  }else throw Error('unknown-local-operation');
  res.writeHead(200,{'content-type':'application/json'});res.end('{"ok":true}');
 }catch(_){res.writeHead(400,{'content-type':'application/json'});res.end('{"error":"local-request-rejected"}');}
});
server.listen(8766,'127.0.0.1');
process.on('SIGTERM',()=>server.close(()=>process.exit(0)));
