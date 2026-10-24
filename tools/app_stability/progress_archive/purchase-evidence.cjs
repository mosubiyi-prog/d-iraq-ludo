'use strict';
// Untrusted native payment journal only, never a source of spendable money.
const {createHash}=require('node:crypto');
const {hasDuplicateJsonKeys}=require('./legacy-assessment.cjs');
const {frames}=require('./purchase-frames.cjs');
function fail(code){throw Object.assign(new Error(code),{code});}
function exact(value,keys){if(!value||typeof value!=='object'||Array.isArray(value)||
 Object.keys(value).length!==keys.length||!keys.every(k=>Object.hasOwn(value,k)))fail('invalid-purchase-evidence');}
function valueType(value){return value===null?'absent':Array.isArray(value)?'string-list':typeof value;}
function native(value){return value===null||['string','boolean'].includes(typeof value)||
 (typeof value==='number'&&Number.isFinite(value))||(Array.isArray(value)&&value.every(v=>typeof v==='string'));}
function assessPurchaseEvidence(raw,{accountKey,captureId,originalId,progressCaptureId,sourceUid,installId}){
 if(raw===null)fail('purchase-evidence-missing');
 exact(raw,['format','kind','accountKey','sourceUid','installId','captureId','records','createdAt']);
 if(!/^[A-Za-z0-9_-]{20,80}$/.test(captureId)||raw.format!==1||raw.kind!=='legacy-purchase-evidence'||
 raw.accountKey!==accountKey||raw.captureId!==captureId||raw.sourceUid!==sourceUid||raw.installId!==installId)fail('purchase-evidence-origin-conflict');
 exact(raw.records,['originalId','progressCaptureId','localSnapshot']);
 const r=raw.records,t=raw.createdAt;
 if(r.originalId!==originalId||r.progressCaptureId!==progressCaptureId)fail('purchase-evidence-parent-conflict');
 if(typeof r.localSnapshot!=='string'||Buffer.byteLength(r.localSnapshot,'utf8')>200000||!t||
 !Number.isSafeInteger(t.seconds)||!Number.isSafeInteger(t.nanoseconds)||t.nanoseconds<0||t.nanoseconds>=1000000000)fail('invalid-purchase-evidence');
 let snapshot;
 try{snapshot=JSON.parse(r.localSnapshot);if(hasDuplicateJsonKeys(r.localSnapshot))fail('duplicate-purchase-json');}
 catch(error){if(error.code==='duplicate-purchase-json')throw error;fail('invalid-purchase-snapshot-json');}
 exact(snapshot,['format','accountKey','originalId','inventory','frameJournals']);
 if(snapshot.format!==1||snapshot.accountKey!==accountKey||snapshot.originalId!==originalId||!native(snapshot.inventory))fail('invalid-purchase-evidence');
 exact(snapshot.frameJournals,frames);
 const journals={};
 for(const frame of frames){const value=snapshot.frameJournals[frame];if(!native(value))fail('invalid-purchase-evidence');
 journals[frame]={state:value===null?'absent-on-source':value==='paid'?'paid-recorded':value==='charging'?'charging-recorded':'unexpected-value',valueType:valueType(value)};}
 const evidenceDigest=createHash('sha256').update(JSON.stringify(['untrusted-purchase-journals-v1',accountKey,captureId,
 originalId,progressCaptureId,sourceUid,installId,[t.seconds,t.nanoseconds],r.localSnapshot])).digest('hex');
 return {captureId,sourcePath:`deda_purchase_evidence/${accountKey}/captures/${captureId}`,originalId,progressCaptureId,
 sourceUid,installId,evidenceDigest,journals,inventoryValueType:valueType(snapshot.inventory),
 canProvePayment:false,canAutoSettle:false};
}
module.exports={assessPurchaseEvidence};
