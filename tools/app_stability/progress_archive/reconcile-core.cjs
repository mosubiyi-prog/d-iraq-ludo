'use strict';
const {createHash}=require('node:crypto');
const units=Object.freeze(['points','coins','xp','earnedDiamonds']);
const sources=Object.freeze({
  'account-bootstrap-v1':'baseline','legacy-baseline-v1':'baseline',
  'task-claim-v1':'award','rewarded-ad-v1':'award','point-tier-return-v1':'award',
  'cosmetic-debit-v1':'spend','point-reservation-v1':'spend',
});
function fail(code){throw Object.assign(new Error(code),{code});}
function exact(value,keys,code){
  if(!value||Array.isArray(value)||typeof value!=='object'||Object.keys(value).length!==keys.length||
    !keys.every(key=>Object.hasOwn(value,key)))fail(code);
}
function account(value){if(typeof value!=='string'||!/^[0-9]+$/.test(value))fail('invalid-account');return value;}
function vector(value,{signed=false}={}){
  exact(value,units,'invalid-units');
  for(const unit of units)if(!Number.isSafeInteger(value[unit])||(!signed&&value[unit]<0))fail('invalid-amount');
  return Object.freeze({...value});
}
function parseReceipt(value,expectedAccount){
  account(expectedAccount);
  exact(value,['format','accountKey','source','sourceId','kind','delta'],'invalid-receipt');
  if(value.format!==1||value.accountKey!==expectedAccount)fail('receipt-account-or-format');
  if(!Object.hasOwn(sources,value.source)||sources[value.source]!==value.kind)fail('unsupported-event-source');
  if(typeof value.sourceId!=='string'||value.sourceId.length<1||value.sourceId.length>256)fail('invalid-source-id');
  const delta=vector(value.delta,{signed:true});
  const values=units.map(unit=>delta[unit]);
  if(value.kind==='baseline'&&values.some(n=>n<0))fail('invalid-baseline');
  if(value.source==='account-bootstrap-v1'&&values.some(n=>n!==0))fail('new-account-bootstrap-must-be-zero');
  if(value.kind==='award'&&(values.some(n=>n<0)||!values.some(n=>n>0)))fail('invalid-award');
  if(value.kind==='spend'&&(values.some(n=>n>0)||!values.some(n=>n<0)||delta.xp!==0))fail('invalid-spend');
  if(value.source==='rewarded-ad-v1'&&(delta.points!==0||delta.coins!==0||delta.xp!==0))fail('invalid-rewarded-ad-units');
  if(value.source==='cosmetic-debit-v1'&&(delta.points!==0||delta.xp!==0))fail('invalid-cosmetic-units');
  if(value.source==='point-reservation-v1'&&(delta.coins!==0||delta.xp!==0||delta.earnedDiamonds!==0))fail('invalid-point-units');
  if(value.source==='point-tier-return-v1'){
    const match=/^[A-Za-z0-9_-]{20,80}\|(5000|10000|15000|20000)\|[a-f0-9]{64}$/.exec(value.sourceId);
    const threshold=match?Number(match[1]):null;
    if(threshold===null||delta.points!==threshold+threshold/100||delta.coins!==0||delta.xp!==0||delta.earnedDiamonds!==0)fail('invalid-point-tier-return');
  }
  return Object.freeze({...value,delta});
}
function eventKey(receipt){
  // Identical source events deduplicate even through two receipt document IDs.
  // Neither current SDK UID, installId, client time nor payload amount is a key.
  return createHash('sha256').update(JSON.stringify([1,receipt.accountKey,receipt.source,receipt.sourceId])).digest('hex');
}
function sameEvent(a,b){
  return ['format','accountKey','source','sourceId','kind'].every(key=>a[key]===b[key])&&
    units.every(unit=>a.delta[unit]===b.delta[unit]);
}
function parseState(value,expectedAccount){
  exact(value,['format','accountKey','version','balances','initializedBy'],'invalid-state');
  if(value.format!==1||value.accountKey!==expectedAccount||!Number.isSafeInteger(value.version)||value.version<1||
    typeof value.initializedBy!=='string'||!/^[0-9a-f]{64}$/.test(value.initializedBy))fail('invalid-state');
  return Object.freeze({...value,balances:vector(value.balances)});
}
function applyEvent(prior,receipt){
  receipt=parseReceipt(receipt,receipt?.accountKey);
  if(prior===null&&receipt.kind!=='baseline')fail('progress-initialization-required');
  if(prior!==null&&receipt.kind==='baseline')fail('baseline-already-initialized');
  const current=prior===null?{points:0,coins:0,xp:0,earnedDiamonds:0}:parseState(prior,receipt.accountKey).balances;
  const balances={};
  for(const unit of units){
    const value=current[unit]+receipt.delta[unit];
    if(!Number.isSafeInteger(value))fail('progress-overflow');
    if(value<0)fail('insufficient-'+unit);
    balances[unit]=value;
  }
  const version=(prior?.version??0)+1;
  if(!Number.isSafeInteger(version))fail('version-overflow');
  return Object.freeze({format:1,accountKey:receipt.accountKey,version,
    balances:Object.freeze(balances),initializedBy:prior?.initializedBy??eventKey(receipt)});
}
module.exports={units,account,parseReceipt,eventKey,sameEvent,parseState,applyEvent};
