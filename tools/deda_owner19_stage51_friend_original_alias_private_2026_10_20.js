"use strict";

// Owner19 Stage51: PRIVATE, READ-ONLY, NEVER EXPORTED IN functions/index.js.
// Resolve an OWNED alias to the registered ORIGINAL friend/public ID.
// Does not touch locations, QR, friendship pair keys, wallets, or account data.
// Hosted Callable is default-OFF and must be owner-approved with AppCheck.
const {createHash} = require("node:crypto");
const PREMIUM = /^@DEDA-[A-Z0-9]{4,12}$/;
const ORIGINAL = /^@DEDA-[A-Z0-9]{6}$/;
const USER = /^[A-Za-z0-9_-]{1,160}$/;
const KEY = /^[A-Za-z0-9_-]{4,160}$/;
const sha = s => createHash("sha256").update(s, "utf8").digest("hex");
function blocked(code="failed-precondition") {
  const e=new Error("deda-stage51-safe-friend-alias-closed");
  e.code=code;throw e;
}
function data(s) {return s.exists?s.data()||{}:{};}
function read(db, collection, id) {return db.collection(collection).doc(id);}
async function resolveStage51FriendOriginalId(db,{identifier}={}) {
  if (!db||typeof db.runTransaction!=="function"||
      typeof identifier!=="string"||!PREMIUM.test(identifier)) {
    blocked("invalid-argument");
  }
  return db.runTransaction(async tx=>{
    const direct=await tx.get(read(db,"deda_share_ids",identifier));
    if(direct.exists) {
      const dir=data(direct);
      if(!ORIGINAL.test(identifier)||dir.kind!=="personal"||
          dir.active!==true||dir.publicId!==identifier||
          typeof dir.ownerUid!=="string"||!USER.test(dir.ownerUid)) return null;
      const user=await tx.get(read(db,"users",dir.ownerUid));
      const owner=data(user);
      if(!user.exists||typeof owner.accountKey!=="string"||
          !KEY.test(owner.accountKey)||
          owner.sharePersonalId!==identifier) return null;
      return Object.freeze({serverConfirmed:true,requestedId:identifier,
        originalId:identifier});
    }
    // Never trust alias docs alone: require registry, current original
    // directory, historic original owner with stable account key, and ledger.
    const [aliasSnapshot,registration]=await Promise.all([
      tx.get(read(db,"deda_owned_identifier_aliases",identifier)),
      tx.get(read(db,"deda_owned_identifier_registry",identifier)),
    ]);
    if(!aliasSnapshot.exists||!registration.exists) return null;
    const alias=data(aliasSnapshot), reg=data(registration);
    if(alias.kind!=="permanent_alias"||alias.identifier!==identifier||
        reg.identifier!==identifier||reg.status!=="owned"||
        typeof reg.originalId!=="string"||!ORIGINAL.test(reg.originalId)||
        reg.originalId!==alias.originalId||
        typeof reg.accountKey!=="string"||!KEY.test(reg.accountKey)||
        reg.accountKey!==alias.accountKey) blocked();
    const original=reg.originalId,key=reg.accountKey;
    const [canonical,ledgerSnapshot]=await Promise.all([
      tx.get(read(db,"deda_share_ids",original)),
      tx.get(read(db,"deda_owned_identifier_accounts",sha(key))),
    ]);
    const dir=data(canonical),ledger=data(ledgerSnapshot);
    if(!canonical.exists||dir.publicId!==original||
        dir.kind!=="personal"||dir.active!==true||
        typeof dir.ownerUid!=="string"||!USER.test(dir.ownerUid)||
        !ledgerSnapshot.exists||ledger.accountKey!==key||
        ledger.originalId!==original||
        !Array.isArray(ledger.ownedIds)||
        ledger.ownedIds.length<2||ledger.ownedIds.length>250||
        ledger.ownedIds[0]!==original||
        new Set(ledger.ownedIds).size!==ledger.ownedIds.length||
        !ledger.ownedIds.every(x=>typeof x==="string"&&PREMIUM.test(x))||
        !ledger.ownedIds.includes(identifier)||
        !ledger.ownedIds.includes(ledger.activeId)) blocked();
    const ownerSnap=await tx.get(read(db,"users",dir.ownerUid));
    const owner=data(ownerSnap);
    if(!ownerSnap.exists||owner.accountKey!==key||
        owner.sharePersonalId!==original) blocked();
    // A permanently owned inactive ID still resolves to the same original
    // account. Only the active ID is displayed as the profile's colored name.
    return Object.freeze({serverConfirmed:true,requestedId:identifier,
      originalId:original});
  },{maxAttempts:5});
}

function buildStage51FriendAliasCallable({
  db,onCall,HttpsError,enabled=false,
}={}) {
  if(!db||typeof db.runTransaction!=="function"||
      typeof onCall!=="function"||typeof HttpsError!=="function") blocked();
  return onCall({enforceAppCheck:true,memory:"256MiB",
    timeoutSeconds:30},async request=>{
    try {
      if(!enabled) blocked("unavailable");
      if(typeof request?.auth?.uid!=="string"||
          !USER.test(request.auth.uid)) blocked("unauthenticated");
      if(typeof request?.app?.appId!=="string"||
          !request.app.appId.trim()) blocked("permission-denied");
      const input=request.data;
      if(!input||typeof input!=="object"||Array.isArray(input)||
          Object.keys(input).length!==1||
          typeof input.identifier!=="string"||
          !PREMIUM.test(input.identifier)) blocked("invalid-argument");
      const result=await resolveStage51FriendOriginalId(db,{
        identifier:input.identifier});
      return result??Object.freeze({serverConfirmed:false,
        requestedId:input.identifier,originalId:null});
    } catch(e) {
      const safe=new Set(["unavailable","unauthenticated","permission-denied",
        "invalid-argument","failed-precondition"]);
      throw new HttpsError(safe.has(e?.code)?e.code:"internal",
        "deda-friend-alias-not-ready");
    }
  });
}
module.exports={resolveStage51FriendOriginalId,buildStage51FriendAliasCallable};
