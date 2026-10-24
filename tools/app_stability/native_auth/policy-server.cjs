'use strict';
// LOCAL rule loader/report endpoint only. No document SDK, seed endpoint,
// production credentials, actual source/PIN/UID in the public result.
const http=require('node:http'),fs=require('node:fs'),path=require('node:path');
const {createHash}=require('node:crypto');
const {initializeTestEnvironment}=require('@firebase/rules-unit-testing');
const project='demo-deda-live-progress-compat';
if(process.env.GCLOUD_PROJECT!==project || process.env.FIRESTORE_EMULATOR_HOST!=='127.0.0.1:8080' ||
   process.env.FIREBASE_AUTH_EMULATOR_HOST!=='127.0.0.1:9099' || process.env.GOOGLE_APPLICATION_CREDENTIALS ||
   process.env.DEDA_RULES_PRIMARY_SA || process.env.DEDA_RULES_SECONDARY_SA)throw Error('isolated-demo-without-production-credentials-required');
const privateDir=process.env.DEDA_RULES_PRIVATE,publicDir=process.env.DEDA_RULES_PUBLIC;
if(!privateDir||!publicDir)throw Error('directories-required');
const proof=JSON.parse(fs.readFileSync(path.join(publicDir,'rules-compat-report.json'),'utf8'));
if(proof.status!=='emulator-passed-awaiting-release-verify'||proof.emulator.passed!==93)throw Error('node-comparison-required');
const cases=new Set(["native-bound-owner-registration", "native-bound-wrong-pin-rejected", "native-bound-fresh-uid-pin-profile-preserved", "native-bound-section-preserves-admin", "native-bound-explicit-owner-replaces-admin", "native-bound-whole-flow-blocks-other-login", "native-bound-timeout-keeps-sdk-lane", "native-bound-owner-recovery-after-timeout", "native-bound-secrets-private-no-retry", "native-bound-cold-state-prepared", "cold-bound-auth-install-and-local-state", "cold-bound-trusted-session-restore", "cold-bound-explicit-logout-preserves-local-data"]);
let state={status:'waiting',passed:[],failures:[],phase:1},environment;
const loads=[];
function save(){fs.writeFileSync(path.join(publicDir,'native-pin-result.json'),JSON.stringify({...state,
 projectId:project,realNativePlugins:true,originalDedaPinAuth:false,boundDedaPinAuth:true,privilegedDocumentSeeds:false,
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
  }else if(req.url==='/checkpoint'||req.url==='/finish'){
   if(Object.keys(data).length!==3||![1,2].includes(data.phase)||!Array.isArray(data.passed)||!Array.isArray(data.failures)||
      data.passed.some(n=>!cases.has(n))||new Set(data.passed).size!==data.passed.length||
      data.failures.some(f=>!f||Object.keys(f).length!==2||typeof f.name!=='string'||typeof f.code!=='string'||!Object.keys(f).every(k=>['name','code'].includes(k))||!['bootstrap','framework','uncaught',...cases].includes(f.name)||!/^[-a-z0-9_]{1,60}$/.test(f.code)))throw Error('invalid-sanitized-report');
   const next={passed:data.passed,failures:data.failures.map(f=>({name:f.name,code:f.code})),phase:data.phase,
     status:data.failures.length?'failed':req.url==='/checkpoint'?'restart-ready':'passed'};
   if(next.status==='restart-ready'&&(data.phase!==1||data.passed.length!==10))throw Error('incomplete-checkpoint');
   if(next.status==='passed'&&(data.phase!==2||data.passed.length!==13))throw Error('incomplete-result');
   if(next.status!=='failed'&&(loads.length!==1||loads[0].mode!=='merged'))throw Error('both-native-policies-required');
   state=next;save();
  }else throw Error('unknown-local-operation');
  res.writeHead(200,{'content-type':'application/json'});res.end('{"ok":true}');
 }catch(_){res.writeHead(400,{'content-type':'application/json'});res.end('{"error":"local-request-rejected"}');}
});
server.listen(8766,'127.0.0.1');
process.on('SIGTERM',()=>server.close(()=>process.exit(0)));
