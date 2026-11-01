"use strict";
/**
 * DEDA Step 2: INTERNAL, READ-ONLY, server-side original-account inventory.
 *
 * Not exported by functions/index.js, no client callable, no Firestore writes.
 * This is a bounded audit of current evidence, NEVER a right to restore assets,
 * reassign original IDs, copy a wallet, credit XP, or edit a week.
 *
 * A PIN_VERIFIED_HOLD is NOT sufficient authorization to transfer value.
 * Downstream migration requires separate historical source attestation,
 * anti-replay receipts, old-version writer fencing and owner-approved cutover.
 */
const {rateDocumentId} = require("./deda_secure_pin_gate_core");
const {originalLockDocumentId} = require("./deda_canonical_account_proof_core");
const FRAMES = Object.freeze([
  "FRAME_03","FRAME_05","FRAME_06","FRAME_07","FRAME_08","FRAME_09",
  "FRAME_10","FRAME_11","FRAME_12","FRAME_13","FRAME_14",
  "FRAME_15","FRAME_16",
]);
const DOMAINS = Object.freeze([
  "profile","levelAndXp","taskPoints","diamondsAndBalances","paidFrames",
  "premiumIdentifier","gifts","dailyTasks","trafficQuestions","weeklyLeague",
  "settings","friends","places",
]);
const ACCOUNT = /^[0-9]{8,15}$/;
const ORIGINAL = /^@DEDA-[A-Z0-9]{6}$/;
const UID = /^[A-Za-z0-9_-]{6,128}$/;
const WEEK = /^[0-9]{4}-[0-9]{2}-[0-9]{2}$/;
const ALL_BLOCKED = Object.freeze(Object.fromEntries(
  DOMAINS.map(name=>[name,"not-audited"])));
class InventoryDenied extends Error {
  constructor(){super("account-restore-inventory-denied");this.name="InventoryDenied";}
}
const deny=()=>{throw new InventoryDenied();};
const data=sn=>sn?.exists?sn.data():null;
const uint=n=>Number.isSafeInteger(n)&&n>=0;

function protectScope({accountKey,originalId,claimantUid,weekId,secret}){
  if(typeof secret!=="string" || Buffer.byteLength(secret,"utf8")<32 ||
     typeof accountKey!=="string" || !ACCOUNT.test(accountKey) ||
     typeof originalId!=="string" || !ORIGINAL.test(originalId) ||
     typeof claimantUid!=="string" || !UID.test(claimantUid) ||
     (weekId!==undefined && (typeof weekId!=="string"||!WEEK.test(weekId)))) deny();
}

/**
 * A readable scan is not a credential validation. Only future internally
 * authorized backend code may invoke this AFTER fresh AppCheck+PIN verification.
 * It NEVER creates a session, locks, snapshots or financial records.
 */
async function scanAccountRestoreReadiness({db,auth,secret,accountKey,
                                           originalId,claimantUid,weekId,
                                           freshCanonicalHold}){
  protectScope({accountKey,originalId,claimantUid,weekId,secret});
  // The caller must obtain this from canonicalOriginalHold in the SAME
  // trusted backend invocation after fresh AppCheck+PIN verification.
  // Never accept it from client request.data or a cached proof. As a plain
  // JS object this is a caller contract, NOT independent attestation.
  if(!freshCanonicalHold ||
     freshCanonicalHold.status!=="PIN_VERIFIED_HOLD" ||
     freshCanonicalHold.serverOwned!==true ||
     freshCanonicalHold.canonicalOriginalVerified!==true ||
     freshCanonicalHold.canonicalOriginalId!==originalId ||
     freshCanonicalHold.canRestoreAssets!==false ||
     freshCanonicalHold.canMigrate!==false ||
     freshCanonicalHold.productionMigrationEnabled!==false) deny();
  if(!db||typeof db.runTransaction!=="function" || !auth||
     typeof auth.getUser!=="function") deny();
  let claimant;
  try{claimant=await auth.getUser(claimantUid);}catch(_){deny();}
  if(!claimant || claimant.disabled || claimant.uid!==claimantUid ||
     claimant.email || (Array.isArray(claimant.providerData)&&
     claimant.providerData.length>0)) deny();
  const ah=rateDocumentId(secret,accountKey);
  const ih=originalLockDocumentId(secret,originalId);
  const scopePaths={
    canonical:"deda_secure_canonical_accounts/"+ah,
    originalLock:"deda_secure_original_id_owners/"+ih,
    binding:"deda_secure_account_bindings/"+claimantUid,
    directory:"deda_account_directory/"+accountKey,
    credential:"deda_credentials/"+accountKey,
    profile:"deda_account_profiles/"+accountKey,
    route:"deda_share_ids/"+originalId,
  };
  let result;
  try{
    result=await db.runTransaction(async tx=>{
      // Scope reads are completed and checked BEFORE any inventory read.
      const scopeRefs=Object.values(scopePaths).map(p=>db.doc(p));
      const snap=await Promise.all(scopeRefs.map(ref=>tx.get(ref)));
      const s=Object.fromEntries(
        Object.keys(scopePaths).map((k,i)=>[k,data(snap[i])]));
      const source=s.canonical?.sourceOwnerUid;
      if(typeof source!=="string"||!UID.test(source) ||
         s.canonical?.originalId!==originalId ||
         s.canonical?.status!=="PIN_VERIFIED_HOLD" ||
         s.canonical?.canRestoreAssets!==false ||
         s.canonical?.canMigrate!==false ||
         s.originalLock?.accountHash!==ah ||
         s.originalLock?.originalId!==originalId ||
         s.originalLock?.sourceOwnerUid!==source ||
         s.originalLock?.status!=="PIN_VERIFIED_HOLD" ||
         s.originalLock?.canRestoreAssets!==false ||
         s.originalLock?.canMigrate!==false ||
         s.binding?.uid!==claimantUid ||
         s.binding?.accountKey!==accountKey ||
         s.binding?.status!=="PIN_VERIFIED_HOLD" ||
         s.binding?.canRestoreAssets!==false ||
         s.binding?.canCreditDiamonds!==false ||
         s.directory?.accountKey!==accountKey ||
         s.directory?.active!==true ||
         s.directory?.createdUid!==source ||
         s.credential?.accountKey!==accountKey ||
         s.credential?.active!==true ||
         s.credential?.createdUid!==source ||
         s.profile?.accountKey!==accountKey ||
         s.route?.publicId!==originalId ||
         s.route?.kind!=="personal" ||
         s.route?.active!==true ||
         s.route?.ownerUid!==source) deny();

      // A single old Firebase UID may have created more than one phone
      // account: in that case do NOT assume which account owns this ID.
      const sisters=await tx.get(db.collection("deda_account_directory")
        .where("createdUid","==",source).limit(2));
      if(sisters.size!==1||sisters.docs[0].id!==accountKey) deny();
      const oldUser=data(await tx.get(db.doc("users/"+source)));
      if(oldUser?.accountKey!==accountKey ||
         oldUser?.sharePersonalId!==originalId) deny();

      const frameReceipts=FRAMES.map(name=>
        db.doc("deda_lab_frame_receipts/"+originalId+"/frames/"+name));
      const frameOwned=FRAMES.map(name=>
        db.doc("deda_lab_owned_frames/"+originalId+"/frames/"+name));
      const staticRefs=[
        db.doc("deda_diamond_gift_balances/"+originalId),
        db.doc("deda_stage71_active_identifier/"+originalId),
        db.doc("deda_weekly_direct_accounts/"+originalId),
        ...(weekId?[db.doc("deda_weekly_direct_weeks/"+weekId+
          "/scores/"+originalId)]:[]),
      ];
      const reads=await Promise.all([...frameReceipts,...frameOwned,
        ...staticRefs].map(ref=>tx.get(ref)));
      const receipt=reads.slice(0,FRAMES.length).map(data);
      const owned=reads.slice(FRAMES.length,FRAMES.length*2).map(data);
      let found=0;
      for(let i=0;i<FRAMES.length;i++){
        const name=FRAMES[i], r=receipt[i], o=owned[i];
        if(!r&&!o) continue;
        if(!r||!o || r.publicId!==originalId || o.publicId!==originalId ||
           r.kind!=="lab_frame" || r.frameId!==name || o.frameId!==name ||
           r.cost!==1000 || o.receiptId!==originalId+"_"+name) deny();
        found++;
      }
      const offset=FRAMES.length*2;
      const wallet=data(reads[offset]), active=data(reads[offset+1]);
      const weeklyOwner=data(reads[offset+2]);
      const weeklyScore=weekId?data(reads[offset+3]):null;
      // Distinguish NO VERIFIED GIFT WALLET from confirmed ZERO.
      // Other diamond sources are not included and cannot be inferred.
      if(wallet && (wallet.publicId!==originalId||!uint(wallet.balance))) deny();
      if(active && (active.originalId!==originalId ||
         typeof active.activeId!=="string" ||
         !/^@DEDA-[A-Z0-9]{4,12}$/.test(active.activeId))) deny();
      if(weeklyOwner && (weeklyOwner.publicId!==originalId ||
        weeklyOwner.accountKey!==accountKey)) deny();
      if(weeklyScore && (weeklyScore.publicId!==originalId ||
        weeklyScore.weekId!==weekId ||
        !uint(weeklyScore.weeklyXp))) deny();

      // Source-of-truth premium grants & user-acknowledged gift receipts:
      // original DEDA ID stays canonical, active premium ID is display only.
      // These are bounded READ-ONLY queries. Never call receive(), use(),
      // grant(), claim() or migrate() here.
      const grantsSnap=await tx.get(db.collection("deda_stage71_granted_registry")
        .where("recipientOriginalId","==",originalId).limit(201));
      const giftSnap=await tx.get(db.collection("deda_stage74_id_gift_receipts")
        .where("originalId","==",originalId).limit(201));
      if(grantsSnap.size>200||giftSnap.size>200) deny();
      const giftReceipts=new Map();
      for(const item of giftSnap.docs){
        const v=item.data();
        if(v?.identifier!==item.id||v.originalId!==originalId ||
           !["001","002"].includes(v.group) ||
           !v.receivedAt || typeof v.receivedAt.toMillis!=="function" ||
           !Number.isSafeInteger(v.receivedAt.toMillis())) deny();
        giftReceipts.set(item.id,v);
      }
      let verifiedPremium=0,pendingPremiumGifts=0,acceptedPremiumGifts=0;
      const verifiedAliases=new Set();
      const observedGrants=new Set();
      for(const item of grantsSnap.docs){
        const v=item.data();
        if(v?.identifier!==item.id||
           !/^@DEDA-[A-Z0-9]{4,12}$/.test(item.id) ||
           v.recipientOriginalId!==originalId ||
           !["001","002"].includes(v.group) ||
           !["gold","diamond","royal","pink"].includes(v.baseColor) ||
           !["gifted","self_used"].includes(v.kind) ||
           observedGrants.has(item.id)) deny();
        observedGrants.add(item.id);
        if(v.kind==="gifted"){
          const received=giftReceipts.get(item.id);
          if(received){
            if(received.group!==v.group) deny();
            acceptedPremiumGifts++;
            verifiedPremium++;
            verifiedAliases.add(item.id);
          }else{
            pendingPremiumGifts++;
          }
        }else{
          if(giftReceipts.has(item.id)) deny();
          verifiedPremium++;
          verifiedAliases.add(item.id);
        }
      }
      // A valid incoming receipt cannot exist without its original
      // recipient's grant; that would create a false owned item.
      for(const id of giftReceipts.keys()){
        if(!observedGrants.has(id)) deny();
      }
      const activePremiumOwned=!!active &&
        verifiedAliases.has(active.activeId);
      // Legacy paid / non-Stage71 alias may have its OWN ownership
      // registry. It must NOT be falsely marked unowned or restored here.
      const activeNeedsIndependentProof=!!active &&
        active.activeId!==originalId && !activePremiumOwned;

      // All unscanned streams stay as UNVERIFIED, not zeros. A valid
      // inventory read does not transfer UID-owned merchandise or awards.
      const domains={...ALL_BLOCKED,
        profile:"verified-source-readonly",
        paidFrames:"receipt-and-ownership-pairs-readonly",
        diamondsAndBalances:wallet?
          "partial-verified-gift-wallet-only":"unverified-wallet-sources",
        premiumIdentifier:activePremiumOwned?
          "stage71-received-or-self-used-alias-verified-readonly":
          activeNeedsIndependentProof?
            "active-selection-needs-independent-ownership-proof":
            active?"original-selection-seen":"active-selection-absent-needs-review",
        gifts:"stage71-gift-receipts-audited-only",
        weeklyLeague:weekId&&weeklyScore?
          "score-seen-payout-unverified":"week-score-unverified",
      };
      return Object.freeze({
        status:"READ_ONLY_INVENTORY_HOLD",
        safeToRestore:false,safeToCreditDiamonds:false,
        safeToTransferPremiumId:false,safeToReissueGifts:false,
        safeToRewriteWeek:false,
        scannedPaidFrameSlots:FRAMES.length,
        verifiedPaidFramePairs:found,
        verifiedGiftWalletPresent:!!wallet,
        activeDisplaySelectionPresent:!!active,
        activeStage71OwnershipVerified:activePremiumOwned,
        verifiedStage71PremiumItems:verifiedPremium,
        pendingStage71GiftReceipts:pendingPremiumGifts,
        acceptedStage71GiftReceipts:acceptedPremiumGifts,
        weeklyAccountSeen:!!weeklyOwner,
        domains:Object.freeze(domains),
      });
    },{maxAttempts:2,readOnly:true});
  }catch(e){
    if(e instanceof InventoryDenied) throw e;
    // Do not leak real account/wallet/PIN values, database paths or ownership.
    throw new Error("READ_ONLY_INVENTORY_BACKEND_UNAVAILABLE");
  }
  return result;
}

module.exports={InventoryDenied,DOMAINS,FRAMES,scanAccountRestoreReadiness};
