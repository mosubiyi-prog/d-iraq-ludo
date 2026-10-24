'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const {assessPurchaseEvidence}=require('./purchase-evidence.cjs');
const {frames}=require('./purchase-frames.cjs');
const expected={accountKey:'07700000000',captureId:'purchase_capture_origin_00001',originalId:'@DEDA-ABC123',
 progressCaptureId:'baseline_capture_00000001',sourceUid:'old-device',installId:'old-install'};
function snapshot(){return {format:1,accountKey:expected.accountKey,originalId:expected.originalId,
 inventory:' {"owned":["frame_3"],"activeBadges":[]} ',frameJournals:Object.fromEntries(frames.map(id=>[id,null]))};}
function raw(){const s=snapshot();s.frameJournals.FRAME_03='paid';s.frameJournals.FRAME_05='charging';return {
 format:1,kind:'legacy-purchase-evidence',accountKey:expected.accountKey,captureId:expected.captureId,
 sourceUid:expected.sourceUid,installId:expected.installId,createdAt:{seconds:1,nanoseconds:1},
 records:{originalId:expected.originalId,progressCaptureId:expected.progressCaptureId,localSnapshot:JSON.stringify(s)}};}
const assess=value=>assessPurchaseEvidence(value,expected);
test('paid and charging are observed separately, preserve absence and never prove a payment or settle money',()=>{
 const data=raw(),before=structuredClone(data),r=assess(data);assert.equal(r.journals.FRAME_03.state,'paid-recorded');
 assert.equal(r.journals.FRAME_05.state,'charging-recorded');assert.equal(r.journals.FRAME_06.state,'absent-on-source');
 assert.equal(r.canProvePayment,false);assert.equal(r.canAutoSettle,false);assert.deepEqual(data,before);
});
for(const value of [true,123,1.5,['paid'],' PAID ','', 'unknown-future'])test(`unexpected native journal type/value stays non-authoritative: ${JSON.stringify(value)}`,()=>{
 const data=raw(),s=snapshot();s.frameJournals.FRAME_03=value;s.inventory=value;data.records.localSnapshot=JSON.stringify(s);
 const r=assess(data);assert.equal(r.journals.FRAME_03.state,'unexpected-value');assert.equal(r.canProvePayment,false);
});
for(const field of ['accountKey','captureId','sourceUid','installId'])test(`changed ${field} cannot attach evidence to another source`,()=>{
 const data=raw();data[field]='different';assert.throws(()=>assess(data),e=>e.code==='purchase-evidence-origin-conflict');
});
for(const field of ['originalId','progressCaptureId'])test(`changed ${field} does not match parent capture`,()=>{
 const data=raw();data.records[field]='different';assert.throws(()=>assess(data),e=>e.code==='purchase-evidence-parent-conflict');
});
for(const change of ['bytes','time'])test(`digest binds exact ${change} even when observed journals are identical`,()=>{
 const a=raw(),b=raw();if(change==='bytes')b.records.localSnapshot+=' ';else b.createdAt.nanoseconds++;
 assert.notEqual(assess(a).evidenceDigest,assess(b).evidenceDigest);assert.deepEqual(assess(a).journals,assess(b).journals);
});
for(const field of ['sourceUid','installId','captureId'])test(`digest binds original ${field}, independently of journal values`,()=>{
 const a=raw(),b=raw();b[field]+='-new';const params={...expected,[field]:b[field]};
 assert.notEqual(assess(a).evidenceDigest,assessPurchaseEvidence(b,params).evidenceDigest);
});
for(const change of ['missing-frame','extra-frame','nested-map','wrong-original','wrong-account','oversized','bad-json','duplicate-json','bad-time'])test(`malformed ${change} is retained at source and rejected for review`,()=>{
 const data=raw(),s=snapshot();
 if(change==='missing-frame')delete s.frameJournals.FRAME_03;
 if(change==='extra-frame')s.frameJournals.FRAME_FUTURE='paid';
 if(change==='nested-map')s.frameJournals.FRAME_03={paid:true};
 if(change==='wrong-original')s.originalId='@DEDA-OTHER1';
 if(change==='wrong-account')s.accountKey='07700000001';
 if(change==='oversized')s.inventory='x'.repeat(200001);
 data.records.localSnapshot=JSON.stringify(s);
 if(change==='bad-json')data.records.localSnapshot='{broken';
 if(change==='duplicate-json')data.records.localSnapshot=data.records.localSnapshot.replace('"inventory":','"inventory":null,"inventory":');
 if(change==='bad-time')data.createdAt.nanoseconds=1000000000;
 const before=structuredClone(data);assert.throws(()=>assess(data));assert.deepEqual(data,before);
});
test('missing sidecar is missing evidence rather than no purchases',()=>{
 assert.throws(()=>assess(null),e=>e.code==='purchase-evidence-missing');
});
test('frame IDs match the existing native checkout and Dart sidecar without a new catalog',()=>{
 const root=path.join(__dirname,'../../..');
 const checkout=fs.readFileSync(path.join(root,'lib/deda_lab_frame_secure_checkout.dart'),'utf8');
 const section=checkout.slice(checkout.indexOf('static const Set<String> paidFrameIds'),checkout.indexOf('static final RegExp originalIdPattern'));
 const dart=fs.readFileSync(path.join(root,'lib/deda_legacy_purchase_evidence.dart'),'utf8');
 assert.deepEqual([...section.matchAll(/'((?:FRAME_)[0-9]+)'/g)].map(m=>m[1]),frames);
 assert.deepEqual([...dart.matchAll(/'((?:FRAME_)[0-9]+)'/g)].map(m=>m[1]),frames);
});
