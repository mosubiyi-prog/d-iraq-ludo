'use strict';
// Pure reading of original point-tier history; never grants or repairs rights.
const thresholds=Object.freeze([5000,10000,15000,20000,25000]);
function pointTierObservations(raw,assessment){
 const issues=new Set(),tiers=[];
 if(assessment.observedBalances.points===null||assessment.issues.some(v=>['taskPoints:duplicate-json-key','taskPoints:unsupported-version','taskPoints:invalid-awards','taskPoints:invalid-amount'].includes(v)))
 return {tiers:[],observedUnclaimedReturns:null,issues:['point-tier-evidence-unreadable']};
 const awards=JSON.parse(raw.records.taskPoints).awards;
 if(Object.hasOwn(awards,'point_tier|5000'))issues.add('legacy-stage-one-entry-requires-review');
 for(const key of Object.keys(awards))if(key.startsWith('point_tier_')&&!thresholds.some(t=>key===`point_tier_reserve|${t}`||key===`point_tier_claim|${t}`))issues.add('unknown-point-tier-entry');
 let observedUnclaimedReturns=0;
 for(const threshold of thresholds){
  const reserveKey=`point_tier_reserve|${threshold}`,claimKey=`point_tier_claim|${threshold}`;
  const hasReserve=Object.hasOwn(awards,reserveKey),hasClaim=Object.hasOwn(awards,claimKey);
  const reserve=hasReserve?awards[reserveKey]:null,claim=hasClaim?awards[claimKey]:null;
  const bonus=threshold/100;
  let status=!hasReserve&&!hasClaim?'not-observed':hasClaim?'returned-in-raw-balance':threshold===25000?'terminal-prize-reserve':'unclaimed-return';
  const valid=(v,key,amount,type)=>v&&typeof v==='object'&&!Array.isArray(v)&&v.points===amount&&
   (v.id===undefined||v.id===key)&&(v.type===undefined||v.type===type)&&
   (v.threshold===undefined||v.threshold===threshold)&&(v.reservedPoints===undefined||v.reservedPoints===threshold)&&
   (v.bonusPoints===undefined||v.bonusPoints===bonus);
  if((hasReserve&&!valid(reserve,reserveKey,-threshold,'point_tier_reserve'))||
   (hasClaim&&!valid(claim,claimKey,threshold+bonus,'point_tier_claim'))||(hasClaim&&!hasReserve)){
   status='requires-review';issues.add(`point-tier-${threshold}:invalid-pair`);
  }
  if(hasClaim&&threshold===25000){status='requires-review';issues.add('obsolete-final-claim-preserved-needs-review');}
  const previous=thresholds[thresholds.indexOf(threshold)-1];
  if((hasReserve||hasClaim)&&previous&&!Object.hasOwn(awards,`point_tier_claim|${previous}`)){
   status='requires-review';issues.add(`point-tier-${threshold}:previous-claim-missing`);
  }
  if(status==='unclaimed-return')observedUnclaimedReturns++;
  tiers.push({threshold,bonus:threshold===25000?0:bonus,reserveKey,claimKey,hasReserve,hasClaim,
   recordedReservePoints:hasReserve?reserve?.points??null:null,recordedClaimPoints:hasClaim?claim?.points??null:null,
   status,canAutoRefund:false});
 }
 if(issues.size)observedUnclaimedReturns=null;
 return {tiers,observedUnclaimedReturns,issues:[...issues].sort()};
}
module.exports={pointTierObservations};
