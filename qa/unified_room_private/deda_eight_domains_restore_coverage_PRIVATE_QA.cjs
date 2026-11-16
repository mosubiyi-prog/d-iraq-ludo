"use strict";
/*
 * DEDA POINT4 private decision gate, synthetic inputs ONLY.
 * Important distinction demonstrated by Ahmed: successful PIN sign-in,
 * old public ID, diamonds and Hadaya do NOT imply local XP / task points /
 * coins or historical progress was restored on a replacement phone.
 * NOT a client-side entitlement checker or a production proof service.
 */
const domains=Object.freeze(["profile","original_id","premium_id","friends",
 "league","gifts","wallet","places"]);
const history=Object.freeze(["taskPoints","socialXp","coins","earnedDiamonds",
 "ownedFrames","quizProgress","savedPlaces","settings"]);
function inspectEightSectionRestoration(snapshot){
 const missing=[];
 const scoped=snapshot?.scopes;
 if(!snapshot||snapshot.ownerIndependentlyVerified!==true)
   missing.push("independent-owner-proof");
 if(snapshot?.sameOriginalUid!==true||snapshot?.createdNewUid!==false)
   missing.push("same-original-uid");
 if(snapshot?.singleAuthSession!==true)
   missing.push("one-auth-session");
 for(const domain of domains){
   if(!scoped||scoped[domain]!=="verified-server")
     missing.push("domain:"+domain+":"+
       (scoped?.[domain]||"unknown"));
 }
 for(const key of history){
   if(snapshot?.legacy?.[key]!=="verified-server-readback-new-phone")
     missing.push("history:"+key+":"+
       (snapshot?.legacy?.[key]||"unknown"));
 }
 // A financial gift subwallet cannot stand for the entire balance.
 if(snapshot?.financialSourceComplete!==true)
   missing.push("complete-financial-spend-receipt-proof");
 const ready=missing.length===0;
 return Object.freeze({
  allEightDomainsVerified:domains.every(d=>scoped?.[d]==="verified-server"),
  fullyRestored:ready,
  blockers:Object.freeze(missing),
  financialRestoreAuthorized:false, // actual settlement has a separate ledger
  modifiesUid:false,
  creditsAnything:false
 });
}
module.exports={inspectEightSectionRestoration,domains,history};