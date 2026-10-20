"use strict";
// Stage64 real Firestore Emulator rules test. No production credentials/writes.
// Simulate old phone UID and new phone UID bound to the SAME verified account,
// NOT merely the same typed name or phone, and preserve original document.
const test = require("node:test");
const assert = require("node:assert/strict");
const {readFileSync} = require("node:fs");
const {resolve} = require("node:path");
const {createRequire} = require("node:module");
const req = createRequire(resolve(__dirname, "../functions/package.json"));
const {initializeTestEnvironment, assertSucceeds, assertFails} =
  req("@firebase/rules-unit-testing");
const {collection, doc, setDoc, getDoc, getDocs, query, where, limit, updateDoc} =
  req("firebase/firestore");
const PROJECT = "demo-deda-stage64-owner-place-recovery";
assert.equal(process.env.GCLOUD_PROJECT, PROJECT);
assert.match(process.env.FIRESTORE_EMULATOR_HOST || "",
  /^(127\.0\.0\.1|localhost):[0-9]{2,5}$/);

const accountKey="9647700001234", oldUid="old-phone-uid", newUid="new-phone-uid";
const strangerUid="stranger-phone-uid", placeId="approved-month-old-place";
let env;
test.before(async ()=>{
  env=await initializeTestEnvironment({
    projectId:PROJECT,
    firestore:{host:"127.0.0.1",port:8080,
      rules:readFileSync(resolve(__dirname,"../firestore.rules"),"utf8")},
  });
  await env.withSecurityRulesDisabled(async context=>{
    const db=context.firestore();
    await setDoc(doc(db,"deda_sessions",newUid),
      {uid:newUid,accountKey,installId:"synthetic-verified-pin-device"});
    await setDoc(doc(db,"deda_sessions",oldUid),
      {uid:oldUid,accountKey,installId:"synthetic-previous-device"});
    await setDoc(doc(db,"published_places",placeId),{
      ownerUid:oldUid,accountKey,published:true,
      approvalNumber:"DEDA-2026-0000009",placeName:"Existing verified owner place",
      isAvailableNow:false,followers:17,likes:12,
    });
    await setDoc(doc(db,"published_places","another-owner-place"),{
      ownerUid:strangerUid,accountKey:"9647811111111",
      published:true,placeName:"Not owned by the signed-in account",
    });
    await setDoc(doc(db,"published_places","legacy-needs-manual-review"),{
      ownerUid:oldUid,published:true,placeName:"Legacy without accountKey",
    });
  });
});
test.after(async()=>{if(env)await env.cleanup();});

test("real rules: changed UID has same authenticated session accountKey and sees exact original published place",async()=>{
  const db=env.authenticatedContext(newUid).firestore();
  const session=await assertSucceeds(getDoc(doc(db,"deda_sessions",newUid)));
  assert.equal(session.data().accountKey,accountKey);
  const places=await assertSucceeds(getDocs(query(
    collection(db,"published_places"),
    where("accountKey","==",session.data().accountKey),
    where("published","==",true),limit(2),
  )));
  assert.equal(places.size,1);
  assert.equal(places.docs[0].id,placeId);
  assert.equal(places.docs[0].data().ownerUid,oldUid,
    "ownerUid must not be client-rewritten");
  assert.equal(places.docs[0].data().approvalNumber,"DEDA-2026-0000009");
  assert.equal(places.docs[0].data().followers,17);
  assert.equal(places.docs[0].data().likes,12);
});

test("real rules: verified new UID may update ONLY allowed availability, original owner UID and approvals remain",async()=>{
  const db=env.authenticatedContext(newUid).firestore();
  await assertSucceeds(updateDoc(doc(db,"published_places",placeId),
    {isAvailableNow:true}));
  await assertFails(updateDoc(doc(db,"published_places",placeId),
    {ownerUid:newUid}));
  await assertFails(updateDoc(doc(db,"published_places",placeId),
    {approvalNumber:"DEDA-2026-FAKE"}));
  const after=await getDoc(doc(db,"published_places",placeId));
  assert.equal(after.data().ownerUid,oldUid);
  assert.equal(after.data().approvalNumber,"DEDA-2026-0000009");
});

test("real rules: stranger cannot edit or self-create a trusted recovery session by typing same accountKey",async()=>{
  const db=env.authenticatedContext(strangerUid).firestore();
  await assertFails(updateDoc(doc(db,"published_places",placeId),
    {isAvailableNow:false}));
  await assertFails(setDoc(doc(db,"deda_sessions",strangerUid),{
    uid:strangerUid,accountKey,installId:"guessed-device-id",
    signedInAt:new Date(),lastSeenAt:new Date(),
  }));
});

test("real rules: missing historical accountKey cannot be auto-adopted",async()=>{
  const db=env.authenticatedContext(newUid).firestore();
  const places=await assertSucceeds(getDocs(query(
    collection(db,"published_places"),
    where("accountKey","==",accountKey),
    where("published","==",true),limit(2),
  )));
  assert.equal(places.docs.some(d=>d.id==="legacy-needs-manual-review"),false);
});
