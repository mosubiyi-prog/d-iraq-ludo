'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm');
const fs=require('node:fs'),path=require('node:path'),{createHash}=require('node:crypto');
const source=fs.readFileSync(path.join(__dirname,'policy-server.cjs'),'utf8');
const sha=s=>createHash('sha256').update(s).digest('hex');
function fixture(overrides={}){
 const before='synthetic original policy',after='synthetic merged policy';
 const proof={status:'emulator-passed-awaiting-release-verify',emulator:{passed:93},originalSHA256:sha(before),candidateSHA256:sha(after)};
 const files=new Map([['/public/rules-compat-report.json',JSON.stringify(proof)],['/private/original.private.rules',before],['/private/candidate.private.rules',after]]);
 const loads=[];let handler;
 const server={listen(){},close(){}};
 const context=vm.createContext({process:{env:{GCLOUD_PROJECT:'demo-deda-live-progress-compat',FIRESTORE_EMULATOR_HOST:'127.0.0.1:8080',FIREBASE_AUTH_EMULATOR_HOST:'127.0.0.1:9099',DEDA_RULES_PRIVATE:'/private',DEDA_RULES_PUBLIC:'/public',...overrides},on(){}},
  require(name){
   if(name==='node:http')return{createServer(fn){handler=fn;return server;}};
   if(name==='node:fs')return{readFileSync:p=>{assert(files.has(p));return files.get(p);},writeFileSync:(p,v)=>files.set(p,v)};
   if(name==='@firebase/rules-unit-testing')return{initializeTestEnvironment:async options=>{loads.push(options);return{cleanup:async()=>{}};}};
   if(['node:path','node:crypto'].includes(name))return require(name);
   throw Error('unexpected SDK or dependency');
  }});
 vm.runInContext(source,context);
 return{context,files,loads,async call(route,data,method='POST'){
  let code,body;const req={method,url:route,async *[Symbol.asyncIterator](){yield JSON.stringify(data);}};
  await handler(req,{writeHead(c){code=c;},end(b){body=b;}});return{code,body};
 }};
}
test('rule loader accepts only two exact hashed private sources and never seeds documents',async()=>{
 const f=fixture();assert.equal(vm.runInContext('cases.size',f.context),24);
 assert.equal((await f.call('/policy',{mode:'original'})).code,200);
 assert.equal((await f.call('/policy',{mode:'merged'})).code,200);
 assert.deepEqual(f.loads.map(v=>v.firestore.rules),['synthetic original policy','synthetic merged policy']);
 assert.equal((await f.call('/seed',{uid:'synthetic'})).code,400);
 assert.equal((await f.call('/policy',{mode:'../other'})).code,400);
});
test('private source mismatch is rejected without revealing text',async()=>{
 const f=fixture();f.files.set('/private/original.private.rules','DO_NOT_DISCLOSE_CHANGED_POLICY');
 const response=await f.call('/policy',{mode:'original'});assert.equal(response.code,400);
 assert(!response.body.includes('DO_NOT_DISCLOSE'));assert.equal(f.loads.length,0);
});
test('production credentials, remote emulator or wrong project cannot initialize',()=>{
 for(const overrides of [{GOOGLE_APPLICATION_CREDENTIALS:'/credentials'},{DEDA_RULES_PRIMARY_SA:'fixture-secret'},
  {FIRESTORE_EMULATOR_HOST:'remote:8080'},{FIREBASE_AUTH_EMULATOR_HOST:'remote:9099'},{GCLOUD_PROJECT:'production'}]){
  assert.throws(()=>fixture(overrides),/isolated-demo/);
 }
});
test('public report refuses unknown cases, raw exception fields and incomplete success',async()=>{
 const f=fixture();
 for(const report of [{phase:1,passed:['unknown'],failures:[]},
  {phase:1,passed:[],failures:[{name:'bootstrap',code:'private source with spaces'}]},
  {phase:1,passed:[],failures:[{name:'bootstrap',code:'case-failed',exception:'DO_NOT_DISCLOSE'}]},
  {phase:1,passed:[],failures:[{name:'bootstrap',secret:'DO_NOT_DISCLOSE'}]},
  {phase:1,passed:[],failures:[{name:'bootstrap',code:123}]},
  {phase:2,passed:[],failures:[]}]){
  assert.equal((await f.call('/finish',report)).code,400);
 }
});
test('complete cold restart result and sanitized failures are representable',async()=>{
 const f=fixture();const cases=vm.runInContext('[...cases]',f.context);
 await f.call('/policy',{mode:'original'});await f.call('/policy',{mode:'merged'});
 assert.equal((await f.call('/checkpoint',{phase:1,passed:cases.slice(0,21),failures:[]})).code,200);
 assert.equal((await f.call('/finish',{phase:2,passed:cases,failures:[]})).code,200);
 const r=JSON.parse(f.files.get('/public/native-pin-result.json'));
 assert.equal(r.status,'passed');assert.equal(r.passed.length,24);assert.equal(r.privilegedDocumentSeeds,false);
 assert.equal((await f.call('/finish',{phase:2,passed:[],failures:[{name:'bootstrap',code:'case-failed'}]})).code,200);
 const failed=JSON.parse(f.files.get('/public/native-pin-result.json'));assert.equal(failed.status,'failed');
 assert(!JSON.stringify(failed).includes('synthetic original policy'));
});
