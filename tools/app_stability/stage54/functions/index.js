'use strict';
/*
 * DEDA stage54, strictly local Firebase Auth + Functions + Firestore emulator.
 * This entrypoint is NEVER in the deployed functions/index.js or original app.
 * Purpose: prove a limited server-owned PIN binding gate and backend rate limits
 * against synthetic ORIGINAL legacy Firestore credential fixtures.
 *
 * SECURITY: Firebase Auth Emulator unsigned tokens are not production signature
 * verification. enforceAppCheck:false is EMULATOR ONLY. Reject all production
 * execution; NO verified App Check / no XP, coins, diamonds or migration.
 */
const crypto=require('node:crypto');
const {onCall,HttpsError}=require('firebase-functions/v2/https');
const {initializeApp}=require('firebase-admin/app');
const {getAuth}=require('firebase-admin/auth');
const {getFirestore,FieldValue}=require('firebase-admin/firestore');

const PROJECT='demo-deda-stage54-pin-binding';
const SECRET=process.env.STAGE54_EMULATOR_TEST_KEY;
if(process.env.GCLOUD_PROJECT!==PROJECT ||
   process.env.STAGE54_EMULATOR_ONLY!=='true' ||
   !process.env.FIREBASE_AUTH_EMULATOR_HOST ||
   !process.env.FIRESTORE_EMULATOR_HOST ||
   !process.env.FIREBASE_FUNCTIONS_EMULATOR_HOST ||
   typeof SECRET!=='string'||SECRET.length<32) {
  throw Error('STAGE54_EMULATOR_ONLY_REFUSE_PRODUCTION_START');
}
initializeApp({projectId:PROJECT});
const db=getFirestore();
const LIMIT=5;
const LOCK_MS=15*60*1000;
const denied=()=>new HttpsError('permission-denied','identity-preflight-denied');
const hash=(value)=>crypto.createHmac('sha256',SECRET).update(value).digest('hex');
const equalSix=(a,b)=>{
  if(typeof a!=='string'||typeof b!=='string')return false;
  const ha=crypto.createHash('sha256').update(a).digest();
  const hb=crypto.createHash('sha256').update(b).digest();
  return crypto.timingSafeEqual(ha,hb);
};
function validInput(data) {
  if(!data || typeof data!=='object' || Array.isArray(data))return false;
  const keys=Object.keys(data).sort();
  return keys.length===2 && keys[0]==='accountKey' && keys[1]==='pin' &&
    typeof data.accountKey==='string' &&
    /^[0-9]{8,15}$/.test(data.accountKey) &&
    typeof data.pin==='string' && /^[0-9]{6}$/.test(data.pin);
}
function noGrants(){
  return {
    state:'LOCAL_EMULATOR_PIN_BOUND_HOLD_ONLY',
    emulatorOnly:true,serverOwnedBinding:true,
    appCheckVerified:false,productionReady:false,
    migrationApproved:false,legacyWriterCutover:false,
    awardState:'HOLD_NO_GRANTS',
    canCreditTaskPoints:false,canCreditLifetimeXp:false,
    canCreditSocialCoins:false,canCreditLeagueXp:false,
    canCreditDiamonds:false,canIssueWinnerGift:false,
  };
}
exports.dedaStage54LegacyPinPreflight=onCall({
  enforceAppCheck:false,timeoutSeconds:30,memory:'256MiB'
},async request=>{
  // Never trust UID/account/phone/install supplied in body. UID is obtained
  // from callable Auth context, checked against Auth Emulator account record.
  if(!request.auth?.uid ||
     request.auth.token?.firebase?.sign_in_provider!=='anonymous')
    throw denied();
  if(!validInput(request.data))throw denied();
  const uid=request.auth.uid;
  let user;
  try{user=await getAuth().getUser(uid);}catch(_){throw denied();}
  if(!user || user.disabled || user.email ||
     (Array.isArray(user.providerData)&&user.providerData.length!==0))
    throw denied();

  const accountKey=request.data.accountKey;
  const submittedPin=request.data.pin;  // Never logged, persisted or returned.
  const now=Date.now();
  const rateRef=db.doc('deda_stage54_private_pin_limits/'+hash(accountKey));
  const bindingRef=db.doc('deda_stage54_private_account_bindings/'+uid);
  const credentialRef=db.doc('deda_credentials/'+accountKey);
  const directoryRef=db.doc('deda_account_directory/'+accountKey);
  const profileRef=db.doc('deda_account_profiles/'+accountKey);

  let outcome;
  try{
    outcome=await db.runTransaction(async tx=>{
      // ALL transaction reads happen before any writes.
      const [rateSnap,bindingSnap,credentialSnap,directorySnap,profileSnap]=
        await Promise.all([tx.get(rateRef),tx.get(bindingRef),
          tx.get(credentialRef),tx.get(directoryRef),tx.get(profileRef)]);
      const rate=rateSnap.exists?rateSnap.data():{};
      const lockedUntil=Number(rate.lockedUntilMs)||0;
      if(lockedUntil>now)return 'LOCKED';
      const failures=Number.isSafeInteger(rate.failures)?rate.failures:0;
      const credential=credentialSnap.exists?credentialSnap.data():null;
      const directory=directorySnap.exists?directorySnap.data():null;
      const profile=profileSnap.exists?profileSnap.data():null;
      const valid=credential?.active===true &&
        directory?.active===true &&
        credential?.accountKey===accountKey &&
        directory?.accountKey===accountKey &&
        profile?.accountKey===accountKey &&
        equalSix(credential?.pin,submittedPin);
      if(!valid){
        const next=Math.min(LIMIT,failures+1);
        tx.set(rateRef,{failures:next,
          lockedUntilMs:next>=LIMIT?now+LOCK_MS:0,
          updatedAt:FieldValue.serverTimestamp()});
        return 'DENIED';
      }
      if(bindingSnap.exists && bindingSnap.data()?.accountKey!==accountKey)
        return 'CONFLICT';
      // A credentialed owner can bind more than one emulator UID to the same
      // account; never treat client installId/trustedInstallIds as authority.
      if(!bindingSnap.exists){
        tx.create(bindingRef,{
          uid,accountKey,authProvider:'anonymous',
          state:'LOCAL_VERIFIED_HOLD_ONLY',
          emulatorOnly:true,canMigrate:false,canGrant:false,
          createdAt:FieldValue.serverTimestamp()
        });
      }
      // Clear the failed-attempt counter only after a successful valid PIN.
      tx.set(rateRef,{failures:0,lockedUntilMs:0,
        updatedAt:FieldValue.serverTimestamp()});
      return 'OK';
    },{maxAttempts:5});
  }catch(_){
    // Do not echo Firestore errors, sensitive credential fields or account keys.
    throw new HttpsError('unavailable','identity-preflight-unavailable');
  }
  if(outcome!=='OK')throw denied();
  return noGrants();
});
