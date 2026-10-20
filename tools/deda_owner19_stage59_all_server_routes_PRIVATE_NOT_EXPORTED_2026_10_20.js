"use strict";

// DEDA Owner19 Stage59 — single audited contract surface for the REAL app.
// Still PRIVATE, unexported, OFF by default. There is NO live deployment,
// wallet migration, plaintext reserved-100 transfer or Google Play action.
//
// Converges two previously tested backend adapters:
//   1) Stage33 lazy encrypted catalog/card purchase/GM grant adapter.
//   2) Stage57 read-only verified active/public/friend identifier adapter.
//
// This is a STAGING contract, NOT a deployed purchase system.
// To prevent accidental fraud, an enabled handler can be constructed ONLY
// with a local Firebase Emulator and a disposable demo-deda-* project.
// No production caller can bypass by passing an enabled boolean alone.
const {createLazyOwner19Callables,STAGE16} =
  require("./deda_100359_owner19_lazy_server_callables_PRIVATE_NOT_EXPORTED_2026_10_19.js");
const {ROUTES,createStage57VerifiedReadOnlyRoutes} =
  require("./deda_owner19_stage57_joined_verified_read_routes_PRIVATE_NO_DEPLOY_2026_10_20.js");

const OWNER19=Object.freeze({
  adminRead:"dedaStage19Exclusive100Read",
  adminSelfUse:"dedaStage19Exclusive100SelfUse",
  adminGrant:"dedaStage19Exclusive100Grant",
  idPurchase:"dedaPremiumBuyIdentifier",
  listSale:"dedaPremiumListAvailableIdentifiers",
});
const LOCAL=/^(127\.0\.0\.1|localhost):[0-9]{2,5}$/;
const DEMO=/^demo-deda-[a-z0-9_-]+$/;
function blocked(){
  const error=new Error("owner19-private-server-contract-not-live");
  error.code="failed-precondition";
  throw error;
}
const ALL_NAMES=Object.freeze([
  ...new Set([...Object.values(OWNER19),...Object.values(STAGE16),
    ...Object.values(ROUTES)]),
]);

function createOwner19Stage59PrivateRoutes({
  db, onCall, HttpsError, secret, decryptPrivate100,
  readEncryptedManifest, approvedGroup002, flags={},
}={}){
  if(!db||typeof db.runTransaction!=="function"||
      typeof onCall!=="function"||typeof HttpsError!=="function"||
      !secret||typeof secret.value!=="function"||
      typeof decryptPrivate100!=="function"||
      typeof readEncryptedManifest!=="function"||
      typeof approvedGroup002!=="function"||
      !flags||typeof flags!=="object"||Array.isArray(flags)||
      Object.keys(flags).some(x=>!["purchase","read"].includes(x))||
      Object.values(flags).some(v=>v===null||typeof v!=="object"||
         Array.isArray(v))){
    blocked();
  }
  const purchase=flags.purchase||{};
  const read=flags.read||{};
  const allowedPurchase=["readExclusive","gmSelfUse","gmGift",
    "buyIdentifier","listSale","point16"];
  const allowedPoint16=["read","cardPurchase","cardUse","identifierUse",
    "alias","adminGrant"];
  const allowedRead=["activeInk","publicInk","friendAlias"];
  if(Object.keys(purchase).some(x=>!allowedPurchase.includes(x))||
      Object.keys(read).some(x=>!allowedRead.includes(x))||
      Object.entries(read).some(([k,v])=>typeof v!=="boolean")||
      Object.keys(purchase).some(x=>x!=="point16" &&
        typeof purchase[x]!=="boolean")||
      (purchase.point16!==undefined&&(!purchase.point16||
       typeof purchase.point16!=="object"||
       Array.isArray(purchase.point16)||
       Object.entries(purchase.point16).some(([k,v])=>
         !allowedPoint16.includes(k)||typeof v!=="boolean")))){
    blocked();
  }
  const anyEnabled=[
    ...Object.entries(purchase).filter(([key])=>key!=="point16").map(([,v])=>v),
    ...Object.values(purchase.point16||{}),
    ...Object.values(read),
  ].some(v=>v===true);
  if(anyEnabled &&
      (!DEMO.test(process.env.GCLOUD_PROJECT||"")||
       !LOCAL.test(process.env.FIRESTORE_EMULATOR_HOST||""))){
    blocked();
  }
  const purchaseRoutes=createLazyOwner19Callables({
    onCall,HttpsError,secret,decryptPrivate100,readEncryptedManifest,
    getFirestore:()=>db,approvedGroup002,flags:purchase,
  });
  const inkRoutes=createStage57VerifiedReadOnlyRoutes({
    db,onCall,HttpsError,flags:read,
  });
  const duplicate=Object.keys(purchaseRoutes).filter(
    name=>Object.hasOwn(inkRoutes,name));
  if(duplicate.length!==0)blocked();
  const result=Object.freeze({...purchaseRoutes,...inkRoutes});
  if(ALL_NAMES.length!==15||Object.keys(result).length!==15||
      ALL_NAMES.some(n=>typeof result[n]!=="function")||
      Object.keys(result).some(n=>!ALL_NAMES.includes(n))){
    blocked();
  }
  return result;
}
module.exports={OWNER19,STAGE16,ROUTES,ALL_NAMES,
  createOwner19Stage59PrivateRoutes};
