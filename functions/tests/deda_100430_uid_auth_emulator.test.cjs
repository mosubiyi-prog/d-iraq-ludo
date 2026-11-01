"use strict";
const test=require("node:test"),assert=require("node:assert/strict");
const fs=require("node:fs"),path=require("node:path");
const {createRequire}=require("node:module");
const req=createRequire(path.resolve(__dirname,"../package.json"));
const {initializeApp,deleteApp}=req("firebase/app");
const {getAuth,connectAuthEmulator,signInAnonymously,linkWithCredential,
       EmailAuthProvider,signOut,signInWithEmailAndPassword}=req("firebase/auth");

const PROJECT="demo-deda-100430-uid-continuity";
if(process.env.GCLOUD_PROJECT!==PROJECT||
   process.env.FIREBASE_AUTH_EMULATOR_HOST!=="127.0.0.1:9099"||
   process.env.GOOGLE_APPLICATION_CREDENTIALS!==undefined) {
 throw Error("REFUSE_NON_LOCAL_100430_AUTH_TEST");
}
let count=0;
const apps=[];
function client(){
 const app=initializeApp({apiKey:"fake-deda-emulator-key",projectId:PROJECT,
 authDomain:PROJECT+".firebaseapp.com"},"100430-test-"+(++count));
 apps.push(app);
 const auth=getAuth(app);
 connectAuthEmulator(auth,"http://127.0.0.1:9099",{disableWarnings:true});
 return auth;
}
const email=n=>"077123"+String(n).padStart(5,"0")+"@deda-login.invalid";
const pin="736294";
test.after(async()=>{await Promise.all(apps.map(deleteApp))});
test("original phone links PIN backend credential without ever changing Firebase owner UID",async()=>{
 const old=client(),newPhone=client();
 const s=await signInAnonymously(old),uid=s.user.uid;
 assert.equal(s.user.isAnonymous,true);
 const e=email(1);
 await linkWithCredential(s.user,EmailAuthProvider.credential(e,pin));
 assert.equal(old.currentUser.uid,uid);
 assert.equal(old.currentUser.isAnonymous,false);
 await signOut(old);
 const same=await signInWithEmailAndPassword(newPhone,e,pin);
 assert.equal(same.user.uid,uid);
 assert.equal(same.user.isAnonymous,false);
});
test("wrong PIN on a replacement phone does not sign into original UID",async()=>{
 const old=client(),other=client();
 const original=await signInAnonymously(old);
 const e=email(2);
 await linkWithCredential(original.user,EmailAuthProvider.credential(e,pin));
 await assert.rejects(signInWithEmailAndPassword(other,e,"000000"));
 assert.equal(other.currentUser,null);
 assert.equal(old.currentUser.uid,original.user.uid);
});
test("new phone cannot claim the same number by linking another anonymous UID",async()=>{
 const a=client(),b=client();
 const initial=await signInAnonymously(a),collision=await signInAnonymously(b);
 const e=email(3);
 await linkWithCredential(initial.user,EmailAuthProvider.credential(e,pin));
 await assert.rejects(
  linkWithCredential(collision.user,EmailAuthProvider.credential(e,"888888")));
 assert.equal(a.currentUser.uid,initial.user.uid);
 assert.equal(b.currentUser.uid,collision.user.uid);
 assert.notEqual(a.currentUser.uid,b.currentUser.uid);
});
test("unlinked legacy owner remains untouched and cannot be assumed recovered",async()=>{
 const old=client(),fresh=client();
 const original=await signInAnonymously(old);
 await assert.rejects(signInWithEmailAndPassword(fresh,email(4),pin));
 assert.equal(old.currentUser.uid,original.user.uid);
 assert.equal(old.currentUser.isAnonymous,true);
 assert.equal(fresh.currentUser,null);
});
test("backend identity preserves UID while display premium-ID remains separate source",async()=>{
 const old=client(),replacement=client();
 const uid=(await signInAnonymously(old)).user.uid;
 const premium="@DEDA-KING99",original="@DEDA-ABC123";
 assert.notEqual(premium,original);
 const e=email(5);
 await linkWithCredential(old.currentUser,EmailAuthProvider.credential(e,pin));
 await signOut(old);
 assert.equal((await signInWithEmailAndPassword(replacement,e,pin)).user.uid,uid);
 assert.notEqual(premium,original);
 // Never use a mutable premium alias to derive the account's auth email.
 assert.equal(e,"07712300005@deda-login.invalid");
});
test("exact existing Dart phone PIN email domain and no data-cutover are preserved",()=>{
 const source=fs.readFileSync(path.resolve(__dirname,"../../lib/deda_pin_auth.dart"),"utf8");
 const stage=fs.readFileSync(path.resolve(__dirname,"../../lib/deda_100430_owner_uid_continuity.dart"),"utf8");
 assert.match(source,/return '\$key@deda-login\.invalid';/);
 assert.match(stage,/linkWithCredential\(credential\)/);
 assert.match(stage,/signInWithEmailAndPassword\(/);
 assert.match(stage,/original-owner-uid-not-proven/);
 assert.match(stage,/deda_auth_attempts/);
 assert.match(stage,/deda_sessions/);
 assert.doesNotMatch(stage,/deda_verified_progress|deda_diamond_gift_balances|deda_lab_frame_receipts/);
});
