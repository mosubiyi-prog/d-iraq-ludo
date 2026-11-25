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
module.exports={generateProfileName};
