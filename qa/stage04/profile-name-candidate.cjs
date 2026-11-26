'use strict';
// REVIEW/EMULATOR ONLY. Extend the exact current lab account candidate, never
// deploy it. No new data paths, authority writer, balance or alias mutation.
const {generateAccount}=require('../stage03/uid-spark-fixture-rules.cjs');
function generateProfileName(original) {
  const current=generateAccount(original);
  const anchor='    match /deda_lab_uid_authority/{uid} {';
  if(current.split(anchor).length!==2)throw Error('profile-name-root-anchor');
  const funcs=String.raw`
    function accountPath(uid) {
      return /databases/$(database)/documents/deda_lab_uid_authority/$(uid)/account/current;
    }
    function accountSourcePath(uid) {
      return /databases/$(database)/documents/deda_lab_uid_authority/$(uid)/accountSources/current;
    }
    function accountHistoryPath(uid, revision) {
      return /databases/$(database)/documents/deda_lab_uid_authority/$(uid)/accountHistory/$(revision);
    }
    // Only the display name and the revision can change. Preserve all other
    // fields including identity, role (if any), friends, tasks, league.
    function validNameChange(old, next) {
      return next.diff(old).affectedKeys().hasOnly(['profile','revision']) &&
        old.revision is int && old.revision >= 1 && old.revision < 9007199254740990 &&
        next.revision is int && next.revision == old.revision + 1 &&
        next.profile.diff(old.profile).affectedKeys().hasOnly(['displayName']) &&
        next.profile.displayName != old.profile.displayName &&
        next.profile.displayName is string &&
        next.profile.displayName.size() >= 2 && next.profile.displayName.size() <= 96 &&
        next.profile.displayName.matches('[^ <>][^<>]*[^ <>]') &&
        !next.profile.displayName.matches('.*[\\x00-\\x1f].*');
    }
    function nameCommit(uid, next) {
      let ap = accountPath(uid);
      let sp = accountSourcePath(uid);
      let hp = accountHistoryPath(uid, string(next.revision));
      let old = get(ap).data;
      return owner(uid) && validNameChange(old,next) &&
        get(sp).data == old &&
        get(accountHistoryPath(uid,string(old.revision))).data == old &&
        !exists(hp) && getAfter(ap).data == next &&
        getAfter(sp).data == next && getAfter(hp).data == next;
    }
`;
  let candidate=current.replace(anchor,()=>funcs+anchor);
  for(const path of ['account/current','accountSources/current']){
    const start='      match /'+path+' {';
    const end='\n      }';
    const at=candidate.indexOf(start), z=candidate.indexOf(end,at);
    if(at<0||z<0||candidate.split(start).length!==2)throw Error('profile-name-path-anchor');
    let block=candidate.slice(at,z);
    const old='        allow list, update, delete: if false;';
    if(block.split(old).length!==2)throw Error('profile-name-write-anchor');
    block=block.replace(old,()=> '        allow update: if nameCommit(uid,request.resource.data);\n        allow list, delete: if false;');
    candidate=candidate.slice(0,at)+block+candidate.slice(z);
  }
  // Stage03 revision one creation stays exact and immutable. New history is
  // create-only, bound to the same full atomic owner rename and revision.
  const history='      match /accountHistory/{revision} {\n'+
    '        allow create: if revision == string(request.resource.data.revision) && nameCommit(uid,request.resource.data);\n'+
    '        allow read, update, delete: if false;\n      }\n';
  const end='    match /{document=**} { allow read, write: if false; }';
  const rootEnd=candidate.lastIndexOf('    }\n'+end);
  if(rootEnd<0)throw Error('profile-name-root-end');
  return candidate.slice(0,rootEnd)+history+candidate.slice(rootEnd);
}

// Combined Spark client candidate for the existing synthetic lab only.
// Uses the tested pointReceipt/core event IDs and the fixed accepted lab ID.
// Neither this generator nor the workflow publishes Firebase rules.
function generateProfileActions(original) {
  const {pointReceipt,generateWalletRead}=require('../stage03/uid-ownership-projection.cjs');
  const {eventKey}=require('../stage03/reconcile-core.cjs');
  const {uid,base}=require('../stage03/uid-trusted-fixture.cjs');
  let candidate=generateProfileName(original);
  const anchor='    match /deda_lab_uid_authority/{uid} {';
  const end='    match /{document=**} { allow read, write: if false; }';
  const points=[5000,10000,15000,20000,25000];
  const literal=v=>JSON.stringify(v);
  const entries=[];
  for(const [index,threshold] of points.entries()){
    for(const action of threshold===25000?['reserve']:['reserve','claim']){
      const receipt=pointReceipt(uid,threshold,action),key=eventKey(receipt);
      const required=[];
      if(index>0)required.push(eventKey(pointReceipt(uid,points[index-1],'claim')));
      if(action==='claim')required.push(eventKey(pointReceipt(uid,threshold,'reserve')));
      entries.push({receipt,key,required});
    }
  }
  const funcs=String.raw`
    function rootPath(uid) {
      return /databases/$(database)/documents/deda_lab_uid_authority/$(uid);
    }
    function tierReceiptPath(uid,k) {
      return /databases/$(database)/documents/deda_lab_uid_authority/$(uid)/receipts/$(k);
    }
    function tierEventPath(uid,k) {
      return /databases/$(database)/documents/deda_lab_uid_authority/$(uid)/events/$(k);
    }
    function validPointDelta(old,next,d) {
      return next.diff(old).affectedKeys().hasOnly(['version','balances']) &&
        next.version == old.version+1 && next.version <= 9007199254740990 &&
        next.balances.diff(old.balances).affectedKeys().hasOnly(['points']) &&
        next.balances.points is int && next.balances.points >= 0 &&
        next.balances.points <= 9007199254740990 &&
        next.balances.points == old.balances.points+d;
    }
    function tierEvent(uid,k,r,next) {
      return {'format':1,'accountKey':uid,'eventKey':k,'receipt':r,'receiptId':k,
        'appliedVersion':next.version,'afterBalances':next.balances,'createdAt':request.time};
    }
    function pointCommit(uid,k,r,old,next) {
      return owner(uid) && validPointDelta(old,next,r.delta.points) &&
        !exists(tierReceiptPath(uid,k)) && !exists(tierEventPath(uid,k)) &&
        getAfter(tierReceiptPath(uid,k)).data == r &&
        getAfter(tierEventPath(uid,k)).data == tierEvent(uid,k,r,next);
    }
    function activePath(o) {
      return /databases/$(database)/documents/deda_stage71_active_identifier/$(o);
    }
    function publicPath(o) {
      return /databases/$(database)/documents/deda_public_active_aliases/$(o);
    }
    function aliasPath(a) {
      return /databases/$(database)/documents/deda_public_alias_routes/$(a);
    }
    function labOriginal(uid,o) {
      return o == '@DEDA-QA1234' &&
        get(/databases/$(database)/documents/deda_share_ids/$(o)).data.ownerUid == uid &&
        get(/databases/$(database)/documents/deda_share_ids/$(o)).data.publicId == o &&
        get(/databases/$(database)/documents/deda_share_ids/$(o)).data.kind == 'personal' &&
        get(/databases/$(database)/documents/deda_share_ids/$(o)).data.active == true;
    }
    function validIdChange(old,next) {
      return next.diff(old).affectedKeys().hasOnly(['profile','revision']) &&
        old.revision >= 1 && old.revision < 9007199254740990 &&
        next.revision == old.revision+1 &&
        next.profile.diff(old.profile).affectedKeys().hasOnly(['activeId','fixedColor']) &&
        next.profile.activeId != old.profile.activeId &&
        next.profile.originalId == '@DEDA-QA1234' &&
        ((next.profile.activeId == next.profile.originalId && next.profile.fixedColor == null) ||
         (next.profile.activeId == '@DEDA-QAFIXTURE' && next.profile.fixedColor == 'gold'));
    }
    function activeRow(p) {
      return {'originalId':p.originalId,'activeId':p.activeId,'updatedAt':request.time};
    }
    function publicRow(p) {
      return {'originalId':p.originalId,'activeId':p.activeId,'baseColor':p.fixedColor,'updatedAt':request.time};
    }
    function aliasRow(p) {
      return {'aliasId':p.activeId,'originalId':p.originalId,'baseColor':p.fixedColor,'updatedAt':request.time};
    }
    function idCommit(uid,next) {
      let ap=accountPath(uid);
      let sp=accountSourcePath(uid);
      let hp=accountHistoryPath(uid,string(next.revision));
      let old=get(ap).data;
      let p=next.profile;
      return owner(uid) && validIdChange(old,next) &&
        get(sp).data == old && get(accountHistoryPath(uid,string(old.revision))).data == old &&
        !exists(hp) && getAfter(ap).data == next &&
        getAfter(sp).data == next && getAfter(hp).data == next &&
        getAfter(activePath(p.originalId)).data == activeRow(p) &&
        getAfter(publicPath(p.originalId)).data == publicRow(p) &&
        (p.activeId == p.originalId || getAfter(aliasPath(p.activeId)).data == aliasRow(p));
    }
    function directoryChange(uid,o) {
      let old=get(accountPath(uid)).data;
      let next=getAfter(accountPath(uid)).data;
      return owner(uid) && labOriginal(uid,o) && validIdChange(old,next) &&
        old.profile.originalId == o && next.profile.originalId == o;
    }
    function acceptedLabAlias(uid,a,o) {
      let inv=get(/databases/$(database)/documents/deda_lab_uid_authority/$(uid)/inventory/current).data;
      let g=inv.idGifts[0];
      let reg=get(/databases/$(database)/documents/deda_stage71_granted_registry/$(a)).data;
      let rec=get(/databases/$(database)/documents/deda_stage74_id_gift_receipts/$(a)).data;
      return a == '@DEDA-QAFIXTURE' && inv.uid == uid && inv.complete == true &&
        g.identifier == a && g.grant.uid == uid && g.grant.identifier == a &&
        g.grant.kind == 'gifted' && g.grant.baseColor == 'gold' &&
        g.acceptance != null && g.acceptance.uid == uid &&
        g.acceptance.identifier == a && g.acceptance.group == g.grant.group &&
        g.acceptance.receivedMs >= g.grant.grantedMs &&
        reg.identifier == a && reg.recipientOriginalId == o && reg.kind == 'gifted' &&
        reg.group == g.grant.group && reg.baseColor == g.grant.baseColor &&
        rec.identifier == a && rec.originalId == o && rec.group == g.grant.group &&
        rec.receivedAt.toMillis() == g.acceptance.receivedMs &&
        !exists(/databases/$(database)/documents/deda_share_ids/$(a));
    }
`;
  const gate=e=>e.required.map(k=>'exists(tierEventPath(uid,"'+k+'"))').join(' && ');
  const call=(e,old,next)=>'pointCommit(uid,"'+e.key+'",'+literal(e.receipt)+','+old+','+next+')'+
    (gate(e)?' && '+gate(e):'');
  // Route by the unique signed point delta BEFORE evaluating the full
  // receipt/ledger proof. A ternary executes exactly one expensive branch.
  // All original conditions still apply, including the prior stage checks.
  const deltas=entries.map(e=>e.receipt.delta.points);
  if(new Set(deltas).size!==entries.length)throw Error('point-delta-not-unique');
  const dispatch=entries.reduceRight((fallback,e)=>
    '(d == '+e.receipt.delta.points+' ? ('+call(e,'old','next')+') : '+fallback+')','false');
  const pointDispatch='    function pointDispatch(uid,old,next) {\n'+
    '      let d = next.balances.points - old.balances.points;\n'+
    '      return owner(uid) && '+dispatch+';\n    }\n';
  const rootAllow='pointDispatch(uid,resource.data,request.resource.data)';
  const pointMatches=entries.flatMap(e=>['receipts','events'].map(kind=>{
    const check=call(e,'get(rootPath(uid)).data','getAfter(rootPath(uid)).data');
    const exact=kind==='receipts'?literal(e.receipt):
      'tierEvent(uid,"'+e.key+'",'+literal(e.receipt)+',getAfter(rootPath(uid)).data)';
    return '      match /'+kind+'/'+e.key+' {\n'+
      '        allow get: if '+(kind==='events'?'owner(uid)':'false')+';\n'+
      '        allow create: if '+check+' && request.resource.data == '+exact+';\n'+
      '        allow list, update, delete: if false;\n      }\n';
  })).join('');
  if(candidate.split(anchor).length!==2)throw Error('profile-action-root');
  candidate=candidate.replace(anchor,()=>funcs+pointDispatch+anchor+'\n      allow update: if '+rootAllow+';\n'+pointMatches);
  // Existing exact creation/name change rules remain intact. Only the
  // additional atomic selection alternative is enabled on these three paths.
  const nameCheck='nameCommit(uid,request.resource.data)';
  if(candidate.split(nameCheck).length!==4)throw Error('profile-action-name-anchor');
  candidate=candidate.replaceAll(nameCheck,'('+nameCheck+' || idCommit(uid,request.resource.data))');
  const directory=String.raw`
    match /deda_stage71_active_identifier/{o} {
      allow get: if owner(request.auth.uid) && o == '@DEDA-QA1234';
      allow update: if directoryChange(request.auth.uid,o) &&
        resource.data.originalId == o &&
        resource.data.activeId == get(accountPath(request.auth.uid)).data.profile.activeId &&
        request.resource.data == activeRow(getAfter(accountPath(request.auth.uid)).data.profile);
      allow list, create, delete: if false;
    }
    match /deda_public_active_aliases/{o} {
      allow get: if owner(request.auth.uid) && o == '@DEDA-QA1234';
      allow update: if directoryChange(request.auth.uid,o) &&
        resource.data.originalId == o &&
        resource.data.activeId == get(accountPath(request.auth.uid)).data.profile.activeId &&
        resource.data.baseColor == get(accountPath(request.auth.uid)).data.profile.fixedColor &&
        request.resource.data == publicRow(getAfter(accountPath(request.auth.uid)).data.profile);
      allow list, create, delete: if false;
    }
    match /deda_public_alias_routes/{a} {
      function aliasCommit() {
        let uid=request.auth.uid;
        let p=getAfter(accountPath(uid)).data.profile;
        return directoryChange(uid,p.originalId) && p.activeId == a &&
          acceptedLabAlias(uid,a,p.originalId) && request.resource.data == aliasRow(p);
      }
      allow get: if owner(request.auth.uid) && a == '@DEDA-QAFIXTURE';
      allow create: if aliasCommit();
      allow update: if aliasCommit() && resource.data.originalId == request.resource.data.originalId &&
        resource.data.aliasId == a && resource.data.baseColor == request.resource.data.baseColor;
      allow list, delete: if false;
    }
`;
  if(candidate.split(end).length!==2)throw Error('profile-action-end');
  return generateWalletRead(candidate.replace(end,()=>directory+end));
}
module.exports={generateProfileName,generateProfileActions};
