"use strict";
/** UNEXPORTED FROM ORIGINAL FUNCTIONS. Auth Emulator UID -> signed original
 * task XP preview. Never production, never actual league or spendable gifts.
 */
const {onCall,HttpsError}=require("firebase-functions/v2/https");
const {initializeApp}=require("firebase-admin/app");
const {getFirestore}=require("firebase-admin/firestore");
const {getAuth}=require("firebase-admin/auth");
const {PROJECT,previewForAuthedViewer}=
  require("../private_account_bound_signed_xp_reader.cjs");
initializeApp({projectId:PROJECT});
function stop(){throw new HttpsError("permission-denied","stage62-account-or-proof-not-verified");}
function local(){
 const k=process.env.STAGE62_PRIVATE_KEY_HEX;
 if(process.env.GCLOUD_PROJECT!==PROJECT||
    process.env.DEDA_STAGE62_EMULATOR_ONLY!=="true"||
    process.env.FIREBASE_AUTH_EMULATOR_HOST!=="127.0.0.1:9099"||
    process.env.FIREBASE_FUNCTIONS_EMULATOR_HOST!=="127.0.0.1:5001"||
    process.env.FIRESTORE_EMULATOR_HOST!=="127.0.0.1:8080"||
    !/^[0-9a-f]{64}$/.test(k||""))
   throw new HttpsError("failed-precondition","STAGE62_ONLY_LOCAL_EMULATOR");
 return Buffer.from(k,"hex");
}
exports.dedaStage62PrivateAccountScopedSignedXpPreview=onCall({
 enforceAppCheck:false,region:"us-central1",timeoutSeconds:30,memory:"256MiB"
},async request=>{
 const secret=local();
 if(!request.auth?.uid||
    request.auth.token?.firebase?.sign_in_provider!=="anonymous"||
    !request.data||typeof request.data!=="object"||
    Array.isArray(request.data)||Object.keys(request.data).length!==0)
   stop();
 const uid=request.auth.uid;
 let user;
 try{user=await getAuth().getUser(uid);}catch(_){stop();}
 if(!user||user.disabled||user.email||user.providerData?.length)stop();
 const firstOpenMs=Number(process.env.STAGE62_FIRST_OPEN_MS);
 const serverNowMs=Number(process.env.STAGE62_NOW_MS);
 if(!Number.isSafeInteger(firstOpenMs)||!Number.isSafeInteger(serverNowMs))
   throw new HttpsError("failed-precondition","STAGE62_QA_CLOCK_MISSING");
 try{return await previewForAuthedViewer({
   db:getFirestore(),authUid:uid,backendSecret:secret,
   firstOpenMs,weekIndex:0,serverNowMs
 });}
 catch(error){if(error instanceof HttpsError)throw error;stop();}
});
