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
 return before+next+after;
}
module.exports={prepareCutoverWalletFenceRules};
