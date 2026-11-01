"use strict";
// Server-only proof for original DEDA identity after a fresh PIN+AppCheck
// check. No wallet, inventory, session, user record or ID route is modified.
const {securePinPreflight, rateDocumentId} = require("./deda_secure_pin_gate_core");
class CanonicalDenied extends Error {
  constructor() {super("canonical-original-hold-denied"); this.name="CanonicalDenied";}
}
const deny=()=>{throw new CanonicalDenied();};
const originalPattern=/^@DEDA-[A-Z0-9]{6}$/;

function canonicalMatches({accountKey, directory, credential, profile,
                           owner, route, originalId}) {
  const uid=directory?.createdUid;
  return typeof uid==="string" && uid.length>=6 &&
    credential?.active===true && directory?.active===true &&
    credential?.createdUid===uid && credential?.accountKey===accountKey &&
    directory?.accountKey===accountKey && profile?.accountKey===accountKey &&
    owner?.accountKey===accountKey &&
    owner?.sharePersonalId===originalId &&
    originalPattern.test(originalId) &&
    route?.publicId===originalId && route?.kind==="personal" &&
    route?.active===true && route?.ownerUid===uid &&
    (route?.originalId===undefined || route.originalId===originalId);
}

async function canonicalOriginalHold({request, db, auth, secret,
                                      nowMs=Date.now()}) {
  // This performs the actual server-side PIN check on EACH invocation:
  // never accept a stale HOLD document or client-supplied account/original UID.
  const hold=await securePinPreflight({request,db,auth,secret,nowMs});
  if(hold.status!=="PIN_VERIFIED_HOLD" || hold.canRestoreAssets!==false) deny();
  const uid=request.auth.uid, accountKey=request.data.accountKey;
  const id=rateDocumentId(secret,accountKey);
  const docs={
    directory:db.doc("deda_account_directory/"+accountKey),
    credential:db.doc("deda_credentials/"+accountKey),
    profile:db.doc("deda_account_profiles/"+accountKey),
    binding:db.doc("deda_secure_account_bindings/"+uid),
    canonical:db.doc("deda_secure_canonical_accounts/"+id),
  };
  let originalId;
  try {
    originalId=await db.runTransaction(async tx=>{
      const [d,c,p,b,m]=await Promise.all([
        tx.get(docs.directory),tx.get(docs.credential),tx.get(docs.profile),
        tx.get(docs.binding),tx.get(docs.canonical)
      ]);
      const directory=d.exists?d.data():null;
      const credential=c.exists?c.data():null;
      const profile=p.exists?p.data():null;
      const binding=b.exists?b.data():null;
      const sourceUid=directory?.createdUid;
      if(!sourceUid || typeof sourceUid!=="string" ||
          !/^[A-Za-z0-9_-]{6,128}$/.test(sourceUid) ||
          binding?.uid!==uid || binding?.accountKey!==accountKey ||
          binding?.status!=="PIN_VERIFIED_HOLD" ||
          binding?.canRestoreAssets!==false ||
          binding?.canCreditDiamonds!==false) deny();
      // Legacy original projection is a *candidate*, not an authorization.
      const originalOwner=await tx.get(db.doc("users/"+sourceUid));
      const owner=originalOwner.exists?originalOwner.data():null;
      const candidate=owner?.sharePersonalId;
      if(typeof candidate!=="string" || !originalPattern.test(candidate)) deny();
      const routeRef=db.doc("deda_share_ids/"+candidate);
      const routeSnapshot=await tx.get(routeRef);
      const route=routeSnapshot.exists?routeSnapshot.data():null;
      if(!canonicalMatches({accountKey,directory,credential,profile,
                            owner,route,originalId:candidate})) deny();
      if(m.exists) {
        const old=m.data();
        if(old?.status!=="PIN_VERIFIED_HOLD" ||
            old?.sourceOwnerUid!==sourceUid ||
            old?.originalId!==candidate ||
            old?.canRestoreAssets!==false || old?.canMigrate!==false)
          deny();
      } else {
        // Stable, server-created account->original mapping. No arbitrary
        // phone-format merging and no ownership transfer.
        tx.create(docs.canonical,{
          sourceOwnerUid:sourceUid,originalId:candidate,
          status:"PIN_VERIFIED_HOLD",createdAtMs:nowMs,
          canRestoreAssets:false,canMigrate:false,
          canCreditXp:false,canCreditDiamonds:false,canIssueGift:false
        });
      }
      return candidate;
    },{maxAttempts:5});
  } catch(e) {
    if(e instanceof CanonicalDenied) throw e;
    // Do not disclose private account existence or route details.
    throw new Error("CANONICAL_PROOF_BACKEND_UNAVAILABLE");
  }
  return {...hold,canonicalOriginalVerified:true,canonicalOriginalId:originalId,
          canMigrate:false};
}
module.exports={CanonicalDenied,canonicalMatches,canonicalOriginalHold};
