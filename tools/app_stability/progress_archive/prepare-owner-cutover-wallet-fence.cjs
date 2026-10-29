"use strict";
/**
 * Generate a PRIVATE, UNDEPLOYED candidate Firestore ruleset FROM the
 * original rules without editing or replacing the installed production rules.
 *
 * The permanent-ID wallet remains accessible to existing users before an
 * account-specific, SERVER-ONLY writer-fence record is installed. After
 * installing that record the OLD anonymous UID cannot debit, credit or claim
 * the same wallet, nor purchase a frame. Read rights are unchanged.
 *
 * Production requires a separate audited rules deployment plus proof that
 * EVERY old balance writer (not only these four paths) has been fenced.
 */
function exactlyOnce(source,anchor,replacement){
 const i=source.indexOf(anchor);
 if(i<0||source.indexOf(anchor,i+1)>=0)
   throw Error("DEDA_WALLET_CUTOVER_RULES_ANCHOR_DRIFT:"+anchor.slice(0,70));
 return source.slice(0,i)+replacement+source.slice(i+anchor.length);
}
function prepareCutoverWalletFenceRules(source){
 if(typeof source!=="string"||source.length<50000||
    source.includes("DEDA_NEW_PHONE_WALLET_WRITER_CUTOVER_CANDIDATE"))
   throw Error("DEDA_CUTOVER_RULES_BASELINE_REFUSED");
 let s=source;
 const helper=`    // DEDA_NEW_PHONE_WALLET_WRITER_CUTOVER_CANDIDATE
    // Server-owned marker, non-readable/non-writable by any mobile client.
    // Absence preserves existing user access until owner-approved cutover.
    // Malformed or conflicting marker FAILS CLOSED; after activation the old
    // anonymous UID cannot keep spending the permanent-ID gift wallet.
    function dedaCutoverWalletWriterAllowed(publicId) {
      let path = /databases/$(database)/documents/deda_migration_spend_authority/$(publicId);
      return !exists(path) || (
        signedIn()
        && get(path).data.format == 1
        && get(path).data.publicId == publicId
        && get(path).data.status == 'new-device-exclusive'
        && get(path).data.protocol == 'deda-verified-progress-v1'
        && get(path).data.activeUid == request.auth.uid
        && get(path).data.originalUid != request.auth.uid
      );
    }
    match /deda_migration_spend_authority/{publicId} {
      allow read, write: if false;
    }

    // Account-level fence also blocks stale login sessions, profile writes
    // and the special general-manager PERSONAL 1M testing wallet.
    function dedaCutoverAccountWriterAllowed(accountKey) {
      let path = /databases/$(database)/documents/deda_migration_account_authority/$(accountKey);
      return !exists(path) || (
        signedIn()
        && get(path).data.format == 1
        && get(path).data.accountKey == accountKey
        && get(path).data.status == 'new-device-exclusive'
        && get(path).data.protocol == 'deda-verified-progress-v1'
        && get(path).data.activeUid == request.auth.uid
        && get(path).data.originalUid != request.auth.uid
      );
    }
    match /deda_migration_account_authority/{accountKey} {
      allow read, write: if false;
    }

`;
 s=exactlyOnce(s,
 "    // DEDA 100377 point 01: immutable paid-frame proof. No deployment here.",
 helper+"    // DEDA 100377 point 01: immutable paid-frame proof. No deployment here.");
 for(const marker of [
 "match /deda_lab_frame_receipts/{publicId}/frames/{frameId}",
 "match /deda_lab_owned_frames/{publicId}/frames/{frameId}",
 "match /deda_diamond_gift_balances/{publicId}",
 ]){
   const mIndex=s.indexOf(marker);
   if(mIndex<0||s.indexOf(marker,mIndex+1)>=0)throw Error("DEDA_PATH_DRIFT:"+marker);
   const next=s.indexOf("\n    match /",mIndex+marker.length);
   if(next<0)throw Error("DEDA_PATH_END_DRIFT:"+marker);
   const before=s.slice(0,mIndex),block=s.slice(mIndex,next),after=s.slice(next);
   const options=marker.includes("gift_balances")?["allow create: if verifiedDiamondsPersonalOwner(publicId)","allow update: if verifiedDiamondsPersonalOwner(publicId)"]:["allow create: if verifiedDiamondsPersonalOwner(publicId)"];
   let candidate=block;
   for(const permission of options){
      candidate=exactlyOnce(candidate,permission,permission+"\n        && dedaCutoverWalletWriterAllowed(publicId)");
   }
   s=before+candidate+after;
 }
 // Pending gift claims ALSO mint credit in a same-transaction wallet.
 const giftMatch="match /deda_diamond_gifts/{giftId}";
 const j=s.indexOf(giftMatch),end=s.indexOf("\n    match /",j+giftMatch.length);
 if(j<0||end<0)throw Error("DEDA_GIFT_CLAIM_DRIFT");
 const before=s.slice(0,j),after=s.slice(end);
 const block=s.slice(j,end);
 const claim="allow update: if resource.data.targetPublicId is string\n        && verifiedDiamondsPersonalOwner(resource.data.targetPublicId)";
 const next=exactlyOnce(block,claim,claim+"\n        && dedaCutoverWalletWriterAllowed(resource.data.targetPublicId)");
 let fenced=before+next+after;
 // Exact existing account-scoped rule blocks. Do not patch unrelated rules.
 const accountScoped=[
   ["match /deda_gm_personal_diamond_wallets/{accountKey}",[
     ["allow create: if isGeneralManagerPersonalAccount(accountKey)",
       "dedaCutoverAccountWriterAllowed(accountKey)"],
     ["allow update: if isGeneralManagerPersonalAccount(accountKey)",
       "dedaCutoverAccountWriterAllowed(accountKey)"],
   ]],
   ["match /deda_sessions/{uid}",[
     ["allow create, update: if signedIn()",
       "dedaCutoverAccountWriterAllowed(request.resource.data.accountKey)"],
   ]],
   ["match /users/{uid}",[
     ["allow create: if signedIn()",
       "dedaCutoverAccountWriterAllowed(request.resource.data.accountKey)"],
     ["allow update: if signedIn()",
       "dedaCutoverAccountWriterAllowed(resource.data.accountKey)"],
   ]],
   ["match /deda_share_ids/{publicId}",[
     ["allow update: if signedIn()",
       "dedaCutoverWalletWriterAllowed(publicId)"],
   ]],
 ];
 for(const [marker,scopes] of accountScoped){
   const index=fenced.indexOf(marker);
   if(index<0||fenced.indexOf(marker,index+marker.length)>=0)
     throw Error("DEDA_ACCOUNT_PATH_DRIFT:"+marker);
   const finish=fenced.indexOf("\n    match /",index+marker.length);
   if(finish<0)throw Error("DEDA_ACCOUNT_END_DRIFT:"+marker);
   let chunk=fenced.slice(index,finish);
   for(const [anchor,condition] of scopes){
     chunk=exactlyOnce(chunk,anchor,anchor+"\n        && "+condition);
   }
   // The original personal share-ID owner must not deactivate its ID after
   // takeover, even if the original credential/session remains cached.
   // The new device will need a separate authenticated server-side profile/
   // alias update route; never let it claim the old Firebase UID directly.
   if(marker==="match /deda_sessions/{uid}"){
     chunk=exactlyOnce(chunk,
       "allow delete: if signedIn() && request.auth.uid == uid;",
       "allow delete: if signedIn() && request.auth.uid == uid\n"+
       "        && dedaCutoverAccountWriterAllowed(resource.data.accountKey);");
   }
   fenced=fenced.slice(0,index)+chunk+fenced.slice(finish);
 }
 // Profile updates include the manager-bypass OR clause. Conjoin the
 // cutover gate OUTSIDE that OR so no old UID can modify trustedInstallIds.
 const profileMarker="match /deda_account_profiles/{accountKey}";
 const profileStart=fenced.indexOf(profileMarker);
 const profileEnd=fenced.indexOf("\n    match /",profileStart+profileMarker.length);
 if(profileStart<0||profileEnd<0||fenced.indexOf(profileMarker,profileStart+1)>=0)
   throw Error("DEDA_PROFILE_RULE_DRIFT");
 let profile=fenced.slice(profileStart,profileEnd);
 for(const operation of ["create","update"]){
   const needle="allow "+operation+": if isGeneralManager() || (";
   profile=exactlyOnce(profile,needle,
     "allow "+operation+": if dedaCutoverAccountWriterAllowed(accountKey)"+
     " && (isGeneralManager() || (");
 }
 // Both OR expressions close with matching ] newline ) ; lines.
 // Only replace those two precise terminators and preserve existing policy.
 const blockEnd="        ])\n      );";
 const count=profile.split(blockEnd).length-1;
 if(count!==2)throw Error("DEDA_PROFILE_CLOSING_DRIFT");
 profile=profile.split(blockEnd).join("        ])\n      ));");
 return fenced.slice(0,profileStart)+profile+fenced.slice(profileEnd);
}
module.exports={prepareCutoverWalletFenceRules};
