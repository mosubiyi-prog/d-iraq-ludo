'use strict';
// Private migration observations only. NEVER an approval, balance receipt,
// wallet restore or rule for merging devices. Preserve the raw archive.
const {createHash}=require('node:crypto');
const {account}=require('./reconcile-core.cjs');
const parts=['taskPoints','socialCoinsAndXp','earnedDiamonds'];
function fail(code){throw Object.assign(new Error(code),{code});}
function object(value){return value!==null && typeof value==='object' && !Array.isArray(value);}
function exact(value,keys,code){
  if(!object(value)||Object.keys(value).length!==keys.length||!keys.every(key=>Object.hasOwn(value,key)))fail(code);
}
function id(value){return typeof value==='string'&&/^[A-Za-z0-9_-]{20,80}$/.test(value);}
function duplicateKeys(text){
  // JSON.parse validates syntax first. Opaque string tokens protect punctuation
  // inside values; decode key escapes so coins and \u0063oins are the same key.
  const tokens=text.match(/"(?:[^"\\]|\\.)*"|[{}\[\]:,]|-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?|true|false|null/g)||[];
  const stack=[];
  for(let i=0;i<tokens.length;i++){
    const token=tokens[i];
    if(token==='{')stack.push(new Set());
    else if(token==='[')stack.push(null);
    else if(token==='}'||token===']')stack.pop();
    else if(token.startsWith('"')&&tokens[i+1]===':'){
      const keys=stack.at(-1),key=JSON.parse(token);
      if(keys.has(key))return true;
      keys.add(key);
    }
  }
  return false;
}
function assessLegacyEvidence(raw,expectedAccount,captureId){
  account(expectedAccount);
  if(!id(captureId))fail('invalid-capture-id');
  if(raw===null)fail('migration-evidence-missing');
  exact(raw,['format','kind','accountKey','sourceUid','installId','captureId','records','createdAt'],'invalid-migration-evidence');
  if(raw.format!==1||raw.kind!=='legacy-local-evidence'||raw.accountKey!==expectedAccount||raw.captureId!==captureId||
     typeof raw.sourceUid!=='string'||!raw.sourceUid.length||raw.sourceUid.length>128||
     typeof raw.installId!=='string'||!raw.installId.length||raw.installId.length>128||raw.createdAt==null)fail('invalid-migration-evidence');
  exact(raw.records,parts,'invalid-migration-evidence-records');
  if(parts.some(part=>raw.records[part]!==null&&(typeof raw.records[part]!=='string'||raw.records[part].length>200000)))fail('invalid-migration-evidence-record');
  const time=raw.createdAt;
  if(!object(time)||!Number.isSafeInteger(time.seconds)||!Number.isSafeInteger(time.nanoseconds)||
     time.nanoseconds<0||time.nanoseconds>=1000000000)fail('invalid-migration-evidence-time');
  const evidenceDigest=createHash('sha256').update(JSON.stringify([
    'untrusted-legacy-evidence-v1',expectedAccount,captureId,raw.sourceUid,raw.installId,
    [time.seconds,time.nanoseconds],...parts.map(part=>raw.records[part]),
  ]),'utf8').digest('hex');
  const issues=new Set(['local-values-not-server-attested','legacy-writer-fence-not-established','pending-operations-not-reviewed']);
  const read=part=>{
    const text=raw.records[part];
    if(text===null){issues.add(`${part}:missing`);return null;}
    try{
      const value=JSON.parse(text);
      if(!object(value)){issues.add(`${part}:not-object`);return null;}
      if(duplicateKeys(text)){issues.add(`${part}:duplicate-json-key`);return null;}
      return value;
    }catch(_){issues.add(`${part}:invalid-json`);return null;}
  };
  const points=read('taskPoints'),social=read('socialCoinsAndXp'),diamonds=read('earnedDiamonds');
  const observedBalances={points:null,coins:null,xp:null,earnedDiamonds:null};
  const history={pointAwards:null,ledgerEntries:null,socialTaskClaims:null,
    taskAwardsWithoutSocialHistory:null,socialHistoryWithoutTaskAward:null,reservationRecords:null};
  const taskIds=new Set();let validPoints=false;
  if(points){
    if(points.version!==1)issues.add('taskPoints:unsupported-version');
    else if(!object(points.awards))issues.add('taskPoints:invalid-awards');
    else{
      let total=0,valid=true,reservations=0;
      const entries=Object.entries(points.awards);history.pointAwards=entries.length;
      for(const [key,value]of entries){
        if(!object(value)||!Number.isSafeInteger(value.points)||!Number.isSafeInteger(total+value.points))valid=false;
        else total+=value.points;
        if(key.startsWith('task|'))taskIds.add(key.slice(5));
        if(key.startsWith('point_tier_reserve|'))reservations++;
      }
      history.reservationRecords=reservations;
      if(reservations)issues.add('taskPoints:reservations-require-review');
      if(valid){observedBalances.points=total;validPoints=true;if(total<0)issues.add('taskPoints:negative-net-needs-review');}
      else issues.add('taskPoints:invalid-amount');
    }
    if(!object(points.completions))issues.add('taskPoints:invalid-completions');
    if(!Array.isArray(points.ledger))issues.add('taskPoints:invalid-ledger');
    else{history.ledgerEntries=points.ledger.length;if(points.ledger.length>=600)issues.add('taskPoints:history-may-be-truncated');}
  }
  function amount(value,part,field,target){
    if(!Number.isSafeInteger(value)||value<0){issues.add(`${part}:invalid-${field}`);return;}
    observedBalances[target]=value;
    if(value>2**30)issues.add(`${part}:${field}-outside-legacy-display-range`);
  }
  if(social){
    amount(social.coins,'socialCoinsAndXp','coins','coins');
    amount(social.xp,'socialCoinsAndXp','xp','xp');
    if(!Array.isArray(social.taskClaims)||social.taskClaims.some(value=>typeof value!=='string'))issues.add('socialCoinsAndXp:invalid-task-history');
    else{
      const ids=new Set(social.taskClaims);history.socialTaskClaims=social.taskClaims.length;
      if(ids.size!==social.taskClaims.length)issues.add('socialCoinsAndXp:duplicate-task-history');
      if(social.taskClaims.length>=180)issues.add('socialCoinsAndXp:history-may-be-truncated');
      if(validPoints){
        history.taskAwardsWithoutSocialHistory=[...taskIds].filter(key=>!ids.has(key)).length;
        history.socialHistoryWithoutTaskAward=[...ids].filter(key=>!taskIds.has(key)).length;
        if(history.taskAwardsWithoutSocialHistory||history.socialHistoryWithoutTaskAward)issues.add('task-social-history:requires-reconciliation');
      }
    }
  }
  if(diamonds){
    amount(diamonds.balance,'earnedDiamonds','balance','earnedDiamonds');
    if(!Number.isSafeInteger(diamonds.viewsToday)||diamonds.viewsToday<0||diamonds.viewsToday>5)issues.add('earnedDiamonds:invalid-view-counter');
    if(typeof diamonds.day!=='string'||!/^\d{4}-\d{2}-\d{2}$/.test(diamonds.day))issues.add('earnedDiamonds:invalid-local-day');
  }
  return Object.freeze({format:1,kind:'untrusted-legacy-assessment',accountKey:expectedAccount,captureId,
    evidenceDigest,status:'requires-verification',canAutoApprove:false,
    observedBalances:Object.freeze(observedBalances),history:Object.freeze(history),issues:Object.freeze([...issues].sort()),
    settlement:Object.freeze({purchases:'unknown',pointReservations:'unknown'}),
    excludedComponents:Object.freeze(['general-manager-points-bonus','gifted-diamonds','general-manager-personal-wallet','admin-grant-wallet'])});
}
module.exports={assessLegacyEvidence};
