'use strict';
// Privileged fixture service for one LOCAL demo emulator job. Not an API,
// verifier or PIN implementation. Never run with production credentials.
const http=require('node:http');
const fs=require('node:fs');
const path=require('node:path');
const {initializeApp}=require('firebase-admin/app');
const {getFirestore}=require('firebase-admin/firestore');
const project='demo-deda-progress-archive';
if(process.env.FIRESTORE_EMULATOR_HOST!=='127.0.0.1:8080' ||
   process.env.FIREBASE_AUTH_EMULATOR_HOST!=='127.0.0.1:9099' ||
   process.env.GOOGLE_APPLICATION_CREDENTIALS) throw Error('localhost-demo-only');
const app=initializeApp({projectId:project});
const db=getFirestore(app);
const output=process.env.DEDA_NATIVE_RESULTS;
if(!output)throw Error('results-directory-required');
fs.mkdirSync(output,{recursive:true});
let state={status:'waiting',passed:[],failures:[]};
function save(){fs.writeFileSync(path.join(output,'native-result.json'),JSON.stringify(state,null,2)+'\n');}
save();
async function body(req){
  let text='';for await(const chunk of req){text+=chunk;if(text.length>64000)throw Error('oversized-request');}
  return JSON.parse(text||'{}');
}
const server=http.createServer(async(req,res)=>{
  try{
    if(req.method==='GET' && req.url==='/status'){
      res.writeHead(200,{'content-type':'application/json'});res.end(JSON.stringify(state));return;
    }
    if(req.method!=='POST')throw Error('post-required');
    const data=await body(req);
    if(req.url==='/seed'){
      if(!/^[A-Za-z0-9_-]{1,128}$/.test(data.uid||'') ||
          !['07700000000','07700000001'].includes(data.accountKey) ||
          typeof data.installId!=='string' || data.installId.length<1 || data.installId.length>128)throw Error('invalid-fixture');
      const batch=db.batch();
      batch.set(db.doc(`deda_sessions/${data.uid}`),{uid:data.uid,accountKey:data.accountKey,installId:data.installId});
      if(data.omitUser===true)batch.delete(db.doc(`users/${data.uid}`));
      else {
        const originalId=data.accountKey==='07700000000'?'@DEDA-ABC123':'@DEDA-DEF456';
        batch.set(db.doc(`users/${data.uid}`),{accountKey:data.accountKey,sharePersonalId:originalId});
        const route=db.doc(`deda_share_ids/${originalId}`);
        if(!(await route.get()).exists)batch.set(route,{publicId:originalId,kind:'personal',active:true,ownerUid:data.uid});
      }
      await batch.commit();
    }else if(req.url==='/lifecycle'){
      if(data.state!=='paused')throw Error('unexpected-lifecycle-signal');
      if(state.status==='background-ready'){state={...state,status:'backgrounded'};save();}
    }else if(req.url==='/background-ready' || req.url==='/checkpoint' || req.url==='/finish'){
      if(!Array.isArray(data.passed) || !Array.isArray(data.failures))throw Error('invalid-report');
      state={...data,status:data.failures.length?'failed':req.url==='/background-ready'?'background-ready':req.url==='/checkpoint'?'restart-ready':'passed',
        projectId:project,realNativePlugins:true,actualDedaPinTested:false,physicalTwoPhonesTested:false,privilegedCanonicalRouteSeeds:true};save();
    }else throw Error('unknown-operation');
    res.writeHead(200,{'content-type':'application/json'});res.end('{"ok":true}');
  }catch(error){res.writeHead(400,{'content-type':'application/json'});res.end(JSON.stringify({error:error.message}));}
});
server.listen(8765,'127.0.0.1',()=>process.stdout.write('LOCAL_DEMO_FIXTURE_READY\n'));
process.on('SIGTERM',()=>server.close(()=>process.exit(0)));
