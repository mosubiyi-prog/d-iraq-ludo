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
  // Original prize_winner_requests path and cycle; pinned synthetic account only.
  // Code is a display reference, NOT an authentication credential or a payout.
  // Each earlier event is immutable under these same candidate rules. The
  // final event records the actual post-reservation points, not client input.
  const terminal=entries.find(e=>e.receipt.delta.points===-25000);
  if(!terminal || entries.length!==9)throw Error('prize-terminal-anchor');
  const earlier=entries.filter(e=>e!==terminal).map(e=>
    'exists(tierEventPath(uid,"'+e.key+'"))').join(' &&\n          ');
  const code=syntheticPrizeCode(terminal.key);
  const prize=String.raw`
    match /prize_winner_requests/{requestId} {
      function prizeOwner() {
        return owner(request.auth.uid) && requestId == 'prize_v1_' + request.auth.uid;
      }
      function completePrize(uid,d) {
        let a=get(accountPath(uid)).data;
        let finalEvent=get(tierEventPath(uid,"`+terminal.key+String.raw`")).data;
        return a.uid == uid && finalEvent.accountKey == uid &&
          finalEvent.eventKey == "`+terminal.key+String.raw`" &&
          finalEvent.receipt == `+literal(terminal.receipt)+String.raw` &&
          `+earlier+String.raw` &&
          d == {'ownerUid':uid,'cycleId':'prize_v1','accountKey':uid,
            'name':a.profile.displayName,'phone':'','dedaId':a.profile.originalId,
            'rewardCode':"`+code+String.raw`",'pointsAtCompletion':finalEvent.afterBalances.points,
            'completedThresholds':[5000,10000,15000,20000,25000],
            'finalReservedPoints':25000,'status':'new','adminMessage':'',
            'prizeDetails':'','userReply':'','createdAt':request.time,'updatedAt':request.time};
      }
      allow get: if prizeOwner();
      allow create: if prizeOwner() && completePrize(request.auth.uid,request.resource.data);
      // Only the original owner-side transitions. Administrative status
      // changes remain denied to every client in this synthetic candidate.
      allow update: if prizeOwner() &&
        resource.data.ownerUid == request.auth.uid &&
        resource.data.accountKey == request.auth.uid &&
        resource.data.cycleId == 'prize_v1' &&
        resource.data.rewardCode == "`+code+String.raw`" &&
        request.resource.data.updatedAt == request.time &&
        ((resource.data.status == 'needs_info' &&
          request.resource.data.status == 'reviewing' &&
          request.resource.data.userReply is string &&
          request.resource.data.userReply.size() > 0 &&
          request.resource.data.userReply.size() <= 600 &&
          request.resource.data.userReplyAt == request.time &&
          request.resource.data.diff(resource.data).affectedKeys().hasOnly(
            ['status','userReply','userReplyAt','updatedAt'])) ||
         (resource.data.status == 'prize_sent' &&
          resource.data.prizeDetails is string && resource.data.prizeDetails.size() > 0 &&
          request.resource.data.status == 'delivered' &&
          request.resource.data.winnerConfirmedAt == request.time &&
          request.resource.data.deliveredAt == request.time &&
          request.resource.data.diff(resource.data).affectedKeys().hasOnly(
            ['status','winnerConfirmedAt','deliveredAt','updatedAt'])));
      allow list, delete: if false;
    }
`;
  // Read only the two existing residual source records, never the admin
  // role documents or a writable client projection. Exact synthetic schema.
  // The protected legacy-shaped source may change without a projection job.
  const walletSources=String.raw`
    function walletOwner(uid,o) {
      let a=get(accountPath(uid)).data;
      let u=get(/databases/$(database)/documents/users/$(uid)).data;
      let s=get(/databases/$(database)/documents/deda_sessions/$(uid)).data;
      return owner(uid) && a.uid == uid && a.profile.originalId == o &&
        u.accountKey == uid && u.sharePersonalId == o && s.uid == uid &&
        s.accountKey == uid && labOriginal(uid,o);
    }
    function ordinaryWallet(uid) {
      return !exists(/databases/$(database)/documents/admins/$(uid)) &&
        !exists(/databases/$(database)/documents/admin_entry_access/$(uid)) &&
        !exists(/databases/$(database)/documents/deda_gm_personal_diamond_wallets/$(uid));
    }
    function managerWallet(uid) {
      let a=get(/databases/$(database)/documents/admins/$(uid)).data;
      let g=get(/databases/$(database)/documents/admin_entry_access/$(uid)).data;
      return a.role == 'general_manager' && a.active == true && a.status == 'active' &&
        g.accountKey == uid && g.active == true && g.status == 'active' &&
        g.accessType == 'general_manager_gateway' && g.allowedRole == 'general_manager';
    }
    function money(v) { return v is int && v >= 0 && v <= 9007199254740990; }
    match /deda_diamond_gift_balances/{o} {
      allow get: if walletOwner(request.auth.uid,o) &&
        resource.data.keys().hasOnly(['publicId','ownerUid','balance']) &&
        resource.data.publicId == o && money(resource.data.balance) &&
        (!resource.data.keys().hasAny(['ownerUid']) || resource.data.ownerUid == request.auth.uid);
      allow list, create, update, delete: if false;
    }
    match /deda_gm_personal_diamond_wallets/{uid} {
      allow get: if walletOwner(uid,'@DEDA-QA1234') &&
        (ordinaryWallet(uid) || (managerWallet(uid) &&
        resource.data.keys().hasOnly(['accountKey','balance']) &&
        resource.data.accountKey == uid && money(resource.data.balance)));
      allow list, create, update, delete: if false;
    }
`;
  return generateWalletRead(candidate.replace(end,()=>directory+prize+walletSources+end));
}
// Deterministic display-only reference for the single synthetic fixture.
// Never a production issuer or proof of entitlement by itself.
function syntheticPrizeCode(finalEventKey){
  if(typeof finalEventKey!=='string'||!/^[a-f0-9]{64}$/.test(finalEventKey))throw Error('prize-fixture-key');
  return 'Q4'+finalEventKey.slice(0,14);
}
// Narrow live readiness candidate, based on the previously published locked
// account candidate, NOT on the action-enabled emulator candidate. Only exact
// synthetic records can be read. Missing sources remain missing; no new writes.
function generateProfileReadiness(original){
  const locked=generateAccount(original);
  const end='    match /{document=**} { allow read, write: if false; }';
  if(locked.split(end).length!==2 || locked.includes('match /deda_diamond_gift_balances/'))throw Error('readiness-anchor');
  const additions=String.raw`
    function stage04ReadinessOwner(uid) {
      let a=get(/databases/$(database)/documents/deda_lab_uid_authority/$(uid)/account/current).data;
      return owner(uid) && a.uid == uid && a.profile.originalId == '@DEDA-QA1234';
    }
    function stage04ReadyMoney(v) {
      return v is int && v >= 0 && v <= 9007199254740990;
    }
    function stage04ReadyRoute(uid) {
      let r=get(/databases/$(database)/documents/deda_share_ids/@DEDA-QA1234).data;
      return r.ownerUid == uid && r.publicId == '@DEDA-QA1234' && r.kind == 'personal' && r.active == true;
    }
    match /users/{uid} {
      allow get: if stage04ReadinessOwner(uid) &&
        (!exists(/databases/$(database)/documents/users/$(uid)) ||
         (resource.data.keys().hasOnly(['accountKey','sharePersonalId']) &&
          resource.data.accountKey == uid && resource.data.sharePersonalId == '@DEDA-QA1234'));
      allow list, create, update, delete: if false;
    }
    match /deda_sessions/{uid} {
      allow get: if stage04ReadinessOwner(uid) &&
        (!exists(/databases/$(database)/documents/deda_sessions/$(uid)) ||
         (resource.data.keys().hasOnly(['uid','accountKey']) &&
          resource.data.uid == uid && resource.data.accountKey == uid));
      allow list, create, update, delete: if false;
    }
    match /deda_share_ids/{o} {
      allow get: if o == '@DEDA-QA1234' && stage04ReadinessOwner(request.auth.uid) &&
        (!exists(/databases/$(database)/documents/deda_share_ids/$(o)) ||
         (resource.data.keys().hasOnly(['ownerUid','publicId','kind','active']) &&
          stage04ReadyRoute(request.auth.uid)));
      allow list, create, update, delete: if false;
    }
    match /deda_diamond_gift_balances/{o} {
      allow get: if o == '@DEDA-QA1234' && stage04ReadinessOwner(request.auth.uid) &&
        (!exists(/databases/$(database)/documents/deda_diamond_gift_balances/$(o)) ||
         (stage04ReadyRoute(request.auth.uid) &&
          resource.data.keys().hasOnly(['publicId','ownerUid','balance']) &&
          resource.data.publicId == o && stage04ReadyMoney(resource.data.balance) &&
          (!resource.data.keys().hasAny(['ownerUid']) || resource.data.ownerUid == request.auth.uid)));
      allow list, create, update, delete: if false;
    }
    match /deda_gm_personal_diamond_wallets/{uid} {
      allow get: if stage04ReadinessOwner(uid) &&
        !exists(/databases/$(database)/documents/admins/$(uid)) &&
        !exists(/databases/$(database)/documents/admin_entry_access/$(uid)) &&
        !exists(/databases/$(database)/documents/deda_gm_personal_diamond_wallets/$(uid));
      allow list, create, update, delete: if false;
    }
    match /prize_winner_requests/{id} {
      allow get: if stage04ReadinessOwner(request.auth.uid) &&
        id == 'prize_v1_' + request.auth.uid &&
        (!exists(/databases/$(database)/documents/prize_winner_requests/$(id)) ||
         (resource.data.ownerUid == request.auth.uid && resource.data.accountKey == request.auth.uid &&
          resource.data.cycleId == 'prize_v1' && resource.data.dedaId == '@DEDA-QA1234' &&
          resource.data.phone == '' &&
          resource.data.rewardCode.matches('^Q4[a-f0-9]{14}$') &&
          resource.data.keys().hasOnly(['ownerUid','cycleId','accountKey','name','phone','dedaId',
            'rewardCode','pointsAtCompletion','completedThresholds','finalReservedPoints','status',
            'adminMessage','prizeDetails','userReply','createdAt','updatedAt','userReplyAt',
            'winnerConfirmedAt','deliveredAt'])));
      allow list, create, update, delete: if false;
    }
`;
  return locked.replace(end,()=>additions+end);
}
module.exports={generateProfileName,generateProfileActions,syntheticPrizeCode,generateProfileReadiness};
