"use strict";
/**
 * Disposable emulator FUNCTIONS ENTRYPOINT ONLY.
 * Not referenced by root firebase.json or production functions/index.js.
 * A real client can call an empty request on a second emulator phone.
 */
const {onCall,HttpsError}=require("firebase-functions/v2/https");
const {initializeApp}=require("firebase-admin/app");
const {getAuth}=require("firebase-admin/auth");
const {getFirestore,FieldValue}=require("firebase-admin/firestore");
const {createSecondPhoneLinkCallable}=
  require("../second-phone-link-callable.cjs");
const {createSecondPhonePinProofCallable}=
  require("../second-phone-pin-proof-callable.cjs");
initializeApp({projectId:"demo-deda-restore-readiness"});
exports.dedaPrivateSecondPhoneLinkEmulatorOnly=createSecondPhoneLinkCallable({
 onCall,HttpsError,db:getFirestore(),auth:getAuth(),
 serverTimestamp:()=>FieldValue.serverTimestamp(),
});

exports.dedaPrivateSecondPhonePinProofEmulatorOnly=createSecondPhonePinProofCallable({
 onCall,HttpsError,db:getFirestore(),auth:getAuth(),
 serverTimestamp:()=>FieldValue.serverTimestamp(),
});
