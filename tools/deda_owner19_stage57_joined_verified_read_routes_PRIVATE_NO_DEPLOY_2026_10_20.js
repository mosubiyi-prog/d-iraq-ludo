"use strict";

// Owner19 Stage57 — compose three VERIFIED READ-ONLY endpoints matching the
// already-built 100359 Flutter profile / public-friend / alias clients.
// PRIVATE test/review module ONLY. Not imported by production functions/index.js.
// Never reveal UID, wallet, accountKey, manager catalog, phone or location.
// Enabling a handler is ONLY permitted on a disposable local demo emulator.
// A real backend release would require separate audited implementation, rules,
// AppCheck, owner approval, and no automatic application of these test flags.
const {buildVerifiedInkReadCallable} =
  require("./deda_owner19_stage47_verified_active_ink_private_2026_10_20.js");
const {buildStage50PublicInkCallable} =
  require("./deda_owner19_stage50_public_verified_ink_private_2026_10_20.js");
const {buildStage51FriendAliasCallable} =
  require("./deda_owner19_stage51_friend_original_alias_private_2026_10_20.js");

const ROUTES=Object.freeze({
  activeInk:"dedaPremiumReadActiveIdentifierInk",
  publicInk:"dedaPremiumReadPublicIdentifierStyle",
  friendAlias:"dedaPremiumResolveFriendOriginal",
});
const ALLOWED=new Set(Object.keys(ROUTES));
const EMULATOR=/^(127\.0\.0\.1|localhost):[0-9]{2,5}$/;
const DEMO=/^demo-deda-[a-z0-9_-]+$/;
function unavailable(){
  const err=new Error("stage57-not-authorized-for-live-enablement");
  err.code="failed-precondition";
  throw err;
}
function createStage57VerifiedReadOnlyRoutes({
  db,onCall,HttpsError,flags={},
}={}){
  if(!db||typeof db.runTransaction!=="function"||
     typeof onCall!=="function"||typeof HttpsError!=="function"||
     !flags||typeof flags!=="object"||Array.isArray(flags)||
     Object.keys(flags).some(key=>!ALLOWED.has(key))||
     Object.values(flags).some(v=>typeof v!=="boolean")){
    unavailable();
  }
  const anyEnabled=Object.values(flags).some(v=>v===true);
  if(anyEnabled &&
     !(DEMO.test(process.env.GCLOUD_PROJECT||"") &&
       EMULATOR.test(process.env.FIRESTORE_EMULATOR_HOST||""))){
    unavailable();
  }
  const deps={db,onCall,HttpsError};
  const result={
    [ROUTES.activeInk]:buildVerifiedInkReadCallable({
      ...deps,enabled:flags.activeInk===true,
    }),
    [ROUTES.publicInk]:buildStage50PublicInkCallable({
      ...deps,enabled:flags.publicInk===true,
    }),
    [ROUTES.friendAlias]:buildStage51FriendAliasCallable({
      ...deps,enabled:flags.friendAlias===true,
    }),
  };
  if(Object.keys(result).length!==3||
     !Object.values(result).every(fn=>typeof fn==="function")){
    unavailable();
  }
  return Object.freeze(result);
}
module.exports={ROUTES,createStage57VerifiedReadOnlyRoutes};
