"use strict";
/*
 * PRIVATE, UNDEPLOYED QA-only PIN-to-account binding factory. This finally
 * connects the original DEDA PIN sign-in to the existing second-phone link
 * in ONE disposable Firebase project. NEVER a production authentication
 * mechanism: legacy credentials are 6-digit PINs and App Check is NOT proven.
 *
 * The NEW phone must ALREADY have the original app's successful session and
 * user profile. Server verifies the old creator and stable original @DEDA ID.
 * Neither a client-supplied UID nor copied installId authorizes binding.
 * Missing original-device binding is constructed from directory + original
 * owner proof: a lost old phone is not required to participate.
 */
const {createHmac,timingSafeEqual,createHash}=require("node:crypto");
const PROJECT="demo-deda-restore-readiness";
const ACCOUNT=/^[0-9]{10,16}$/;
const UID=/^[A-Za-z0-9_-]{8,128}$/;
const PIN=/^[0-9]{6}$/;
const ORIGINAL=/^@DEDA-[A-Z0-9]{6}$/;
const LIMIT=5,LOCK_MS=15*60*1000;
const bindingPath=uid=>"deda_stage54_private_account_bindings/"+uid;
function guard(){
 if(process.env.GCLOUD_PROJECT!==PROJECT||
    process.env.FIRESTORE_EMULATOR_HOST!=="127.0.0.1:8080"||
    process.env.DEDA_RESTORE_AUDIT_EMULATOR_ONLY!=="true"||
    process.env.FIREBASE_AUTH_EMULATOR_HOST!=="127.0.0.1:9099"||
    process.env.FIREBASE_FUNCTIONS_EMULATOR_HOST!=="127.0.0.1:5001"||
    !/^[0-9a-f]{64}$/.test(process.env.DEDA_RESTORE_AUDIT_LINK_KEY_HEX||""))
   throw Error("DEDA_PRIVATE_PIN_PROOF_REFUSE_PRODUCTION");
}
function constantEqual(a,b){
 if(!PIN.test(a||"")||!PIN.test(b||""))return false;
 return timingSafeEqual(createHash("sha256").update(a).digest(),
   createHash("sha256").update(b).digest());
}
function shape(v,uid,accountKey){
 return !!v&&v.uid===uid&&v.accountKey===accountKey&&
   v.authProvider==="anonymous"&&v.state==="LOCAL_VERIFIED_HOLD_ONLY"&&
   v.emulatorOnly===true&&v.canGrant===false&&v.canMigrate===false&&
   v.createdAt!=null;
}
function makeBinding(uid,accountKey,serverTimestamp){
 return {uid,accountKey,authProvider:"anonymous",
  state:"LOCAL_VERIFIED_HOLD_ONLY",emulatorOnly:true,
  canMigrate:false,canGrant:false,createdAt:serverTimestamp()};
}
function createSecondPhonePinProofCallable({
 onCall,HttpsError,db,auth,serverTimestamp,now=()=>Date.now()
}={}){
 if(typeof onCall!=="function"||typeof HttpsError!=="function"||
    !db||typeof db.doc!=="function"||typeof db.runTransaction!=="function"||
    !auth||typeof auth.verifyIdToken!=="function"||
    typeof auth.getUser!=="function"||
    typeof serverTimestamp!=="function"||typeof now!=="function")
    throw Error("DEDA_PRIVATE_PIN_PROOF_INVALID_DEPENDENCIES");
 return onCall({enforceAppCheck:false,timeoutSeconds:30,memory:"256MiB"},
 async request=>{
  guard();
  const denied=()=>{throw new HttpsError("permission-denied","private-pin-proof-denied");};
  const unavailable=()=>{throw new HttpsError("unavailable","private-pin-proof-unavailable");};
  const uid=request?.auth?.uid,data=request?.data;
  if(!UID.test(uid||"")||
     request.auth.token?.firebase?.sign_in_provider!=="anonymous"||
     !data||typeof data!=="object"||Array.isArray(data)||
     Object.keys(data).length!==2||
     !Object.hasOwn(data,"accountKey")||!Object.hasOwn(data,"pin")||
     !ACCOUNT.test(data.accountKey||"")||!PIN.test(data.pin||""))denied();
  const h=request?.rawRequest?.headers?.authorization;
  const match=typeof h==="string"?/^Bearer ([A-Za-z0-9._-]{16,8192})$/.exec(h):null;
  if(!match)denied();
  try{
   const token=await auth.verifyIdToken(match[1],true);
   const person=await auth.getUser(uid);
   if(token?.uid!==uid||
      token.firebase?.sign_in_provider!=="anonymous"||
      person?.uid!==uid||person.disabled===true||
      !!person.email||person.providerData?.length>0)denied();
  }catch(e){
   if(e instanceof HttpsError)throw e;
   denied();
  }
  const key=data.accountKey,submittedPin=data.pin;
  const secret=Buffer.from(process.env.DEDA_RESTORE_AUDIT_LINK_KEY_HEX,"hex");
  const rateId=createHmac("sha256",secret)
    .update("deda-pin-throttle-v1|"+key).digest("hex");
  const ratePath="deda_stage54_private_pin_limits/"+rateId;
  const current=now();
  if(!Number.isSafeInteger(current)||current<0)unavailable();
  let outcome;
  try{
   outcome=await db.runTransaction(async tx=>{
    const get=async path=>{
      const s=await tx.get(db.doc(path));
      return s.exists?s.data():null;
    };
    const [rate,credential,directory,profile,newUser,newSession,
       newBinding]=await Promise.all([
      get(ratePath),get("deda_credentials/"+key),
      get("deda_account_directory/"+key),
      get("deda_account_profiles/"+key),
      get("users/"+uid),get("deda_sessions/"+uid),
      get(bindingPath(uid)),
    ]);
    const failures=rate?.failures;
    if(rate!==null&&(!Number.isSafeInteger(failures)||failures<0||
       failures>LIMIT||!Number.isSafeInteger(rate.lockedUntilMs)||
       rate.lockedUntilMs<0))return "DENIED";
    if((rate?.lockedUntilMs||0)>current)return "DENIED";
    // Credentials and directory exist only on server. The original
    // Android sign-in already used these exact same records.
    const good=credential?.accountKey===key&&credential.active===true&&
      directory?.accountKey===key&&directory.active===true&&
      profile?.accountKey===key&&newUser?.accountKey===key&&
      newSession?.uid===uid&&newSession?.accountKey===key&&
      constantEqual(submittedPin,credential?.pin);
    const oldUid=directory?.createdUid;
    if(!good||!UID.test(oldUid||"")||uid===oldUid){
      const next=Math.min(LIMIT,(failures||0)+1);
      tx.set(db.doc(ratePath),{failures:next,
        lockedUntilMs:next>=LIMIT?current+LOCK_MS:0,
        updatedAt:serverTimestamp()});
      return "DENIED";
    }
    const oldBinding=await get(bindingPath(oldUid));
    const oldUser=await get("users/"+oldUid);
    const originalId=oldUser?.sharePersonalId;
    const route=ORIGINAL.test(originalId||"")?
       await get("deda_share_ids/"+originalId):null;
    if(oldUser?.accountKey!==key||route?.publicId!==originalId||
       route.kind!=="personal"||route.active!==true||
       route.ownerUid!==oldUid||
       (newUser?.sharePersonalId!=null&&
         newUser.sharePersonalId!==originalId)||
       (oldBinding!==null&&!shape(oldBinding,oldUid,key))||
       (newBinding!==null&&!shape(newBinding,uid,key)))
      return "DENIED";
    if(oldBinding===null)
      tx.create(db.doc(bindingPath(oldUid)),
        makeBinding(oldUid,key,serverTimestamp));
    if(newBinding===null)
      tx.create(db.doc(bindingPath(uid)),
        makeBinding(uid,key,serverTimestamp));
    tx.set(db.doc(ratePath),{
      failures:0,lockedUntilMs:0,updatedAt:serverTimestamp(),
    });
    return "OK";
   },{maxAttempts:3});
  }catch(e){
   if(e instanceof HttpsError)throw e;
   unavailable();
  }
  if(outcome!=="OK")denied();
  return Object.freeze({
   status:"ACCOUNT_PIN_BOUND_HOLD_ONLY",emulatorOnly:true,
   serverOwnedBinding:true,canMigrate:false,canGrant:false,
   appCheckVerified:false,productionReady:false,
  });
 });
}
module.exports={createSecondPhonePinProofCallable};
