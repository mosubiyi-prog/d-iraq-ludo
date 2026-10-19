"use strict";

/**
 * DEDA جمال التطبيق المتكاملة / Stage20.
 * READ-ONLY source-of-truth preflight: NOT sale activation, NEVER writes/migrates.
 *
 * The old ad wallet (DedaDiamondsWallet; SharedPreferences) is a LOCAL DISPLAY
 * NUMBER. It has no server SSV proof; accepting its number in checkout would
 * allow double-credit after reinstalls or tampered clients.
 *
 * Telegram's verified 10 diamonds and admin-received gifts can ALREADY credit
 * deda_diamond_gift_balances. NEVER add their gross rewards again.
 *
 * The GM personal million was historically allowed to be initialised by a
 * current GM client under Firestore rules; it is not a provably server-minted
 * transaction history until independently audited. We report it separately,
 * never automatically migrate, gift, debit or mark sale ready.
 */
const RE_ACCOUNT=/^[A-Za-z0-9_-]{4,160}$/;
const RE_UID=/^[A-Za-z0-9_-]{1,160}$/;
const RE_ORIGINAL=/^@DEDA-[A-Z0-9]{6}$/;
const MAX_WALLET=1073741824;

function fail(code,message) {
  const e=new Error(message);
  e.code=code;
  throw e;
}
function raw(snap) {return snap.exists ? snap.data()||{} : {};}
function validAmount(value) {
  if(!Number.isSafeInteger(value) || value<0 || value>MAX_WALLET) {
    fail("failed-precondition","wallet-balance-needs-server-reconciliation");
  }
  return value;
}
function walletPaths(db,orig,key) {
  return {
    gifted:db.collection("deda_diamond_gift_balances").doc(orig),
    gmPersonal:db.collection("deda_gm_personal_diamond_wallets").doc(key),
    gmAccess:db.collection("admin_entry_access").doc(key),
  };
}

async function auditDiamondSourcesForAuthenticatedAccount(db,{uid}={}) {
  if(!db || typeof db.runTransaction!=="function") {
    fail("unavailable","trusted-admin-server-firestore-required");
  }
  if(typeof uid!=="string" || !RE_UID.test(uid)) {
    fail("unauthenticated","authenticated-current-deda-uid-required");
  }
  return db.runTransaction(async tx=>{
    const userRef=db.collection("users").doc(uid);
    const sessionRef=db.collection("deda_sessions").doc(uid);
    const [userSnap,sessionSnap]=await Promise.all([
      tx.get(userRef),tx.get(sessionRef),
    ]);
    const user=raw(userSnap),session=raw(sessionSnap);
    const key=user.accountKey,orig=user.sharePersonalId;
    if(!userSnap.exists || !sessionSnap.exists ||
      typeof key!=="string" || !RE_ACCOUNT.test(key) ||
      typeof orig!=="string" || !RE_ORIGINAL.test(orig) ||
      session.accountKey!==key || session.uid!==uid) {
      fail("permission-denied","current-verified-account-session-required");
    }

    // Share-owner may be an older rotating anonymous Firebase UID; preserve
    // the permanent original account identity. Ignore user-supplied IDs.
    const share=db.collection("deda_share_ids").doc(orig);
    const shareSnap=await tx.get(share), s=raw(shareSnap);
    if(!shareSnap.exists || s.active!==true || s.kind!=="personal" ||
      s.publicId!==orig || typeof s.ownerUid!=="string" ||
      !RE_UID.test(s.ownerUid)) {
      fail("permission-denied","registered-original-identity-required");
    }
    const originalOwner=await tx.get(db.collection("users").doc(s.ownerUid));
    if(!originalOwner.exists || raw(originalOwner).accountKey!==key) {
      fail("permission-denied","original-owner-account-proof-mismatch");
    }

    const w=walletPaths(db,orig,key);
    const [giftSnap,gmSnap,accessSnap,canonicalSnap]=await Promise.all([
      tx.get(w.gifted),tx.get(w.gmPersonal),tx.get(w.gmAccess),
      tx.get(db.collection("admins").doc(uid)),
    ]);
    const gift=raw(giftSnap),gm=raw(gmSnap);
    if(giftSnap.exists && gift.publicId!==orig) {
      fail("failed-precondition","gift-wallet-original-id-mismatch");
    }
    if(gmSnap.exists && gm.accountKey!==key) {
      fail("failed-precondition","gm-wallet-account-key-mismatch");
    }
    const giftRecorded=giftSnap.exists ? validAmount(gift.balance) : 0;
    const gmRecorded=gmSnap.exists ? validAmount(gm.balance) : 0;
    const a=raw(accessSnap),admin=raw(canonicalSnap);
    const verifiedCurrentGM=accessSnap.exists &&
      a.accountKey===key && a.active===true &&
      a.status==="active" && a.allowedRole==="general_manager" &&
      a.accessType==="general_manager_gateway" &&
      canonicalSnap.exists && admin.active===true &&
      admin.status==="active" && admin.role==="general_manager";

    // Important: GM stored money is READ-ONLY audit evidence, not a credit
    // guarantee. Existing Firestore rules historically permit GM test-wallet
    // creation; do not turn this into real verified customer spendable funds.
    const gmRequiresProvenanceAudit=gmSnap.exists;
    return Object.freeze({
      serverConfirmed:true,
      originalId:orig,
      giftAndServerVerifiedRewardWallet:{
        recordedBalance:giftRecorded,
        walletPresent:giftSnap.exists,
        sources:["received_admin_gifts","telegram_verified_reward"],
        // Both sources are in ONE document; NEVER sum them twice.
        separateTelegramAmountToAdd:0,
      },
      managerPersonalTestWallet:{
        recordedBalance:gmRecorded,
        walletPresent:gmSnap.exists,
        currentlyAuthorizedGM:verifiedCurrentGM,
        requiresOwnerProvenanceReview:gmRequiresProvenanceAudit,
        approvedForAutomaticMigration:false,
      },
      localAdsWallet:{
        storage:"SharedPreferences/deda_diamonds_wallet_v1",
        clientBalanceAccepted:false,
        serverSideAdVerificationConfirmed:false,
        automaticallyImportedDiamonds:0,
        policy:"preserve-display-only-until-per-event-server-SSV-audit",
      },
      taskAndSurveyWallet:{
        shadowLedgerIsSpendable:false,
        verifiedRealClaimImport:false,
        automaticallyImportedDiamonds:0,
      },
      administrativeGiftPool:{
        includedInPersonalSpending:false,
      },
      purchaseActivationApproved:false,
      reason:"reward-ad-task-and-manager-provenance-audit-pending",
    });
  },{maxAttempts:5});
}

module.exports={auditDiamondSourcesForAuthenticatedAccount};
