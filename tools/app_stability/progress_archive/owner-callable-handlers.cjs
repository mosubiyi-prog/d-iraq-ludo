'use strict';
// Callable boundary prepared for packaging; functions/index.js does NOT export
// it. No tokens/account IDs are accepted in the callable data object.
const {readReviewedPurchaseBalanceForOwnerSession,purchaseReviewedFrameForOwnerSession}=require('./purchase-reviewed-frame.cjs');
const {claimReviewedPointTierForOwnerSession}=require('./point-tier-session.cjs');
function fail(code){throw Object.assign(new Error(code),{code});}
function createOwnerCallableHandlers({store,auth}){
 if(!store||!auth||typeof auth.verifyIdToken!=='function')fail('invalid-owner-api-dependencies');
 async function principal(request){
  const header=request?.rawRequest?.headers?.authorization;
  if(typeof header!=='string'||!/^Bearer [^\s]+$/.test(header)||typeof request?.auth?.uid!=='string'||
   !request.auth.uid.length||!request?.app?.appId)fail('owner-api-auth-required');
  const idToken=header.slice(7),token=await auth.verifyIdToken(idToken,true);
  if(token?.uid!==request.auth.uid||token?.firebase?.sign_in_provider!=='anonymous')fail('owner-api-auth-required');
  return idToken;
 }
 function data(request,keys){
  const value=request?.data;
  if(!value||typeof value!=='object'||Array.isArray(value)||Object.keys(value).length!==keys.length||
   !keys.every(k=>Object.hasOwn(value,k)))fail('invalid-owner-api-request');
  return value;
 }
 return Object.freeze({
  dedaReadMigratedProgress:async request=>{
   data(request,[]);const idToken=await principal(request);
   return readReviewedPurchaseBalanceForOwnerSession({store,auth,idToken});
  },
  dedaPurchaseMigratedFrame:async request=>{
   const {frameId}=data(request,['frameId']),idToken=await principal(request);
   return purchaseReviewedFrameForOwnerSession({store,auth,idToken,frameId});
  },
  dedaClaimMigratedPointTier:async request=>{
   const {threshold}=data(request,['threshold']),idToken=await principal(request);
   return claimReviewedPointTierForOwnerSession({store,auth,idToken,threshold});
  },
 });
}
// The actual Firebase callable wrapper enforces App Check before executing a
// handler; request.app is framework context, never client-provided JSON data.
function createOwnerCallableExports({store,auth,onCall,HttpsError}){
 if(typeof onCall!=='function'||typeof HttpsError!=='function')fail('invalid-owner-api-framework');
 const handlers=createOwnerCallableHandlers({store,auth});
 return Object.fromEntries(Object.entries(handlers).map(([name,handler])=>[name,onCall({
  enforceAppCheck:true,maxInstances:10,timeoutSeconds:30,
 },async request=>{
  try{return await handler(request);}catch(error){
   const code=typeof error?.code==='string'?error.code:'';
   if(code==='invalid-owner-api-request'||code==='invalid-reviewed-frame-request'||code==='point-tier-return-ineligible')
    throw new HttpsError('invalid-argument','invalid-progress-request');
   if(code==='owner-api-auth-required'||code.startsWith('auth/'))throw new HttpsError('unauthenticated','account-session-required');
   if(code==='frame-insufficient-diamonds')throw new HttpsError('failed-precondition','insufficient-diamonds');
   if(code.startsWith('migration-')||code.startsWith('reviewed-')||code.startsWith('point-')||code.startsWith('frame-'))
    throw new HttpsError('failed-precondition','progress-not-ready');
   throw new HttpsError('unavailable','progress-request-unavailable');
  }
 })]));
}
module.exports={createOwnerCallableHandlers,createOwnerCallableExports};
