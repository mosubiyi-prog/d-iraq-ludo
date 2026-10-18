"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {readFileSync} = require("node:fs");
const {resolve} = require("node:path");
const {createRequire} = require("node:module");

assert.match(process.env.FIRESTORE_EMULATOR_HOST || "",
    /^(127\.0\.0\.1|localhost):[0-9]+$/,
    "SAFE_STOP: Firestore Emulator is mandatory — no production writes");
const projectId = "demo-deda-point13-atomic-ledger";
assert.match(projectId, /^demo-/);

const requireFunctions = createRequire(resolve(__dirname, "../functions/package.json"));
const {initializeApp, deleteApp} = requireFunctions("firebase-admin/app");
const {getFirestore} = requireFunctions("firebase-admin/firestore");
const {initializeTestEnvironment, assertFails} =
    requireFunctions("@firebase/rules-unit-testing");
const {doc, setDoc, getDoc} = requireFunctions("firebase/firestore");
const {
  checkoutIdCard, readOwnedCards, accountHash, PRICE,
} = require("../tools/deda_intakadha_point13_atomic_id_card_checkout_2026_10_19.js");

let app;
let db;
let env;
let seq = 0;

function name(label) {
  seq++;
  return label + "_" + String(seq).padStart(3, "0");
}
function cash(docSnap) {
  return docSnap.exists ? docSnap.data().balance : null;
}
function errorCode(wanted) {
  return (error) => error && error.code === wanted;
}
async function row(collection, id) {
  return (await db.collection(collection).doc(id).get()).data();
}

async function makeAccount({
  gifted = 15000, gm = 0, eligibleGM = false, uid = null,
  accountKey = null, registeredOwner = null,
} = {}) {
  const userId = uid || name("verified_uid");
  const key = accountKey || name("account_key");
  const publicId = "@DEDA-" + String(seq).padStart(6, "0");
  const firstOwnerUid = registeredOwner || userId;
  const batch = db.batch();
  batch.set(db.collection("users").doc(userId), {
    accountKey: key, sharePersonalId: publicId,
  });
  batch.set(db.collection("deda_sessions").doc(userId), {
    uid: userId, accountKey: key,
  });
  if (firstOwnerUid !== userId) {
    batch.set(db.collection("users").doc(firstOwnerUid), {accountKey: key});
  }
  batch.set(db.collection("deda_share_ids").doc(publicId), {
    publicId, kind: "personal", active: true, ownerUid: firstOwnerUid,
  });
  if (gifted !== null) {
    batch.set(db.collection("deda_diamond_gift_balances").doc(publicId),
        {publicId, balance: gifted, createdAt: new Date()});
  }
  if (gm !== null) {
    batch.set(db.collection("deda_gm_personal_diamond_wallets").doc(key),
        {accountKey: key, balance: gm, initialBalance: 1000000});
  }
  if (eligibleGM) {
    batch.set(db.collection("admin_entry_access").doc(key), {
      accountKey: key, allowedRole: "general_manager",
      accessType: "general_manager_gateway", status: "active", active: true,
    });
  }
  await batch.commit();
  return {uid: userId, key, publicId,
    giftRef: db.collection("deda_diamond_gift_balances").doc(publicId),
    gmRef: db.collection("deda_gm_personal_diamond_wallets").doc(key),
    entitlementRef: db.collection("deda_id_card_entitlements").doc(accountHash(key)),
    receiptRoot: db.collection("deda_id_card_purchase_requests")
        .doc(accountHash(key)).collection("requests"),
  };
}

test.before(async () => {
  app = initializeApp({projectId}, "point13-emulator-only");
  db = getFirestore(app);
  env = await initializeTestEnvironment({
    projectId,
    firestore: {
      host: "127.0.0.1",
      port: Number((process.env.FIRESTORE_EMULATOR_HOST || "").split(":")[1]),
      rules: readFileSync(resolve(__dirname, "../firestore.rules"), "utf8"),
    },
  });
});
test.after(async () => {
  if (env) await env.cleanup();
  if (app) await deleteApp(app);
});

test("gifted diamonds: exactly 5,000 spent with permanent owned and immutable receipt", async () => {
  const a = await makeAccount({gifted: 12500, gm: null});
  const result = await checkoutIdCard(db,
      {uid: a.uid, color: "gold", requestId: "t00000001-gold"});
  assert.deepEqual({charged: result.diamondsCharged, owned: result.alreadyOwned},
      {charged: 5000, owned: false});
  assert.equal(result.serverConfirmed, true);
  assert.equal(cash(await a.giftRef.get()), 7500);
  assert.deepEqual((await a.entitlementRef.get()).data().colors, {gold: true});
  const receipt = await a.receiptRoot.doc("t00000001-gold").get();
  assert.equal(receipt.data().diamondsCharged, 5000);
  assert.equal(receipt.data().giftCharged, 5000);
  assert.equal(receipt.data().gmPersonalCharged, 0);
  assert.deepEqual(await readOwnedCards(db, {uid: a.uid}), ["gold"]);
});

test("network retry reuses original receipt and does not charge twice", async () => {
  const a = await makeAccount({gifted: 11000, gm: null});
  const params = {uid: a.uid, color: "pink", requestId: "t00000002-pink"};
  const first = await checkoutIdCard(db, params);
  const again = await checkoutIdCard(db, params);
  assert.deepEqual(again, first);
  assert.equal(cash(await a.giftRef.get()), 6000);
});

test("new request for owned color charges zero and preserves ownership", async () => {
  const a = await makeAccount({gifted: 10000, gm: null});
  await checkoutIdCard(db,
      {uid: a.uid, color: "diamond", requestId: "t00000003-diamond"});
  const again = await checkoutIdCard(db,
      {uid: a.uid, color: "diamond", requestId: "t00000004-diamond"});
  assert.equal(again.alreadyOwned, true);
  assert.equal(again.diamondsCharged, 0);
  assert.equal(cash(await a.giftRef.get()), 5000);
  assert.deepEqual(await readOwnedCards(db, {uid: a.uid}), ["diamond"]);
});

test("parallel same style requests commit only one 5,000 debit", async () => {
  const a = await makeAccount({gifted: 15000, gm: null});
  const rows = await Promise.all(Array.from({length: 5}, (_, i) =>
    checkoutIdCard(db, {uid: a.uid, color: "royal",
      requestId: "t00000010-royal-" + String(i)})));
  assert.equal(rows.filter((r) => r.diamondsCharged === 5000).length, 1);
  assert.equal(rows.filter((r) => r.alreadyOwned === true).length, 4);
  assert.equal(cash(await a.giftRef.get()), 10000);
});

test("concurrent styles cannot overspend 5000 diamond wallet", async () => {
  const a = await makeAccount({gifted: 5000, gm: null});
  const result = await Promise.allSettled([
    checkoutIdCard(db, {uid: a.uid, color: "gold", requestId: "t00000020-gold"}),
    checkoutIdCard(db, {uid: a.uid, color: "pink", requestId: "t00000021-pink"}),
  ]);
  assert.equal(result.filter((x) => x.status === "fulfilled").length, 1);
  assert.equal(result.filter((x) => x.status === "rejected").length, 1);
  assert.equal(cash(await a.giftRef.get()), 0);
  const owned = await readOwnedCards(db, {uid: a.uid});
  assert.equal(owned.length, 1);
});

test("GM personal and gift remote wallets can be atomically split without admin pool", async () => {
  const a = await makeAccount({gifted: 2500, gm: 15000, eligibleGM: true});
  const adminPool = db.collection("deda_admin_diamond_wallets").doc(name("admin-pool"));
  await adminPool.set({balance: 1000000});
  const answer = await checkoutIdCard(db,
      {uid: a.uid, color: "gold", requestId: "t00000030-gold"});
  assert.equal(answer.diamondsCharged, PRICE);
  assert.equal(cash(await a.giftRef.get()), 0);
  assert.equal(cash(await a.gmRef.get()), 12500);
  assert.equal(cash(await adminPool.get()), 1000000);
  const receipt = (await a.receiptRoot.doc("t00000030-gold").get()).data();
  assert.equal(receipt.giftCharged, 2500);
  assert.equal(receipt.gmPersonalCharged, 2500);
});

test("unauthorized ordinary user cannot spend a manager-only personal wallet", async () => {
  const a = await makeAccount({gifted: 100, gm: 1000000, eligibleGM: false});
  await assert.rejects(checkoutIdCard(db,
      {uid: a.uid, color: "gold", requestId: "t00000040-gold"}),
  errorCode("failed-precondition"));
  assert.equal(cash(await a.gmRef.get()), 1000000);
  assert.equal((await a.entitlementRef.get()).exists, false);
});

test("local app diamonds are not server verified and cannot authorize checkout", async () => {
  const a = await makeAccount({gifted: null, gm: null});
  await db.collection("users").doc(a.uid).update({
    locallyDisplayedDiamonds: 1000000,
  });
  await assert.rejects(checkoutIdCard(db,
      {uid: a.uid, color: "pink", requestId: "t00000050-pink"}),
  errorCode("failed-precondition"));
  assert.equal((await a.entitlementRef.get()).exists, false);
});

test("invalid sessions, forged wallet balance or forged ownership are rejected", async () => {
  const a = await makeAccount({gifted: 7000, gm: null});
  const sessionRef = db.collection("deda_sessions").doc(a.uid);
  await sessionRef.update({accountKey: "another_account"});
  await assert.rejects(checkoutIdCard(db,
      {uid: a.uid, color: "gold", requestId: "t00000060-gold"}),
  errorCode("permission-denied"));
  assert.equal(cash(await a.giftRef.get()), 7000);
  assert.equal((await a.entitlementRef.get()).exists, false);
});

test("share registration owner must match same DEDA account, not simply user input", async () => {
  const a = await makeAccount({gifted: 10000, gm: null});
  const victimUid = name("different_owner");
  await db.collection("users").doc(victimUid).set({accountKey: "victim_account"});
  await db.collection("deda_share_ids").doc(a.publicId).update({ownerUid: victimUid});
  await assert.rejects(checkoutIdCard(db,
      {uid: a.uid, color: "gold", requestId: "t00000070-gold"}),
  errorCode("permission-denied"));
  assert.equal(cash(await a.giftRef.get()), 10000);
});

test("rotated UID sharing verified account can still own a card permanently", async () => {
  const formerUid = name("old_anon_uid");
  const newUid = name("new_anon_uid");
  const a = await makeAccount({uid: newUid, registeredOwner: formerUid,
    gifted: 9000, gm: null});
  await checkoutIdCard(db,
      {uid: newUid, color: "diamond", requestId: "t00000080-diamond"});
  assert.deepEqual(await readOwnedCards(db, {uid: newUid}), ["diamond"]);
  assert.equal(cash(await a.giftRef.get()), 4000);
});

test("reusing request token for different card cannot debit a second time", async () => {
  const a = await makeAccount({gifted: 15000, gm: null});
  await checkoutIdCard(db,
      {uid: a.uid, color: "gold", requestId: "t00000090-reused"});
  await assert.rejects(checkoutIdCard(db,
      {uid: a.uid, color: "pink", requestId: "t00000090-reused"}),
  errorCode("failed-precondition"));
  assert.equal(cash(await a.giftRef.get()), 10000);
});

test("malformed colors, request ids, nonexistent session and invalid balances fail closed", async () => {
  const a = await makeAccount({gifted: 10000, gm: null});
  for (const params of [
    {uid: a.uid, color: "blue", requestId: "t00000100-blue"},
    {uid: a.uid, color: "gold", requestId: "../admin"},
    {uid: "", color: "gold", requestId: "t00000101-gold"},
    {uid: "unknown-session", color: "gold", requestId: "t00000102-gold"},
  ]) {
    await assert.rejects(checkoutIdCard(db, params));
  }
  await a.giftRef.update({balance: -1});
  await assert.rejects(checkoutIdCard(db,
      {uid: a.uid, color: "gold", requestId: "t00000103-gold"}),
  errorCode("failed-precondition"));
});

test("untrusted Firestore clients CANNOT mint ownership or rewrite purchase ledger", async () => {
  const a = await makeAccount({gifted: 9000, gm: null});
  await checkoutIdCard(db,
      {uid: a.uid, color: "gold", requestId: "t00000110-gold"});
  const client = env.authenticatedContext(a.uid).firestore();
  const ownerDoc = doc(client, "deda_id_card_entitlements", accountHash(a.key));
  const receiptDoc = doc(client, "deda_id_card_purchase_requests",
      accountHash(a.key), "requests", "t00000110-gold");
  await assertFails(setDoc(ownerDoc, {accountKey: a.key, colors: {pink: true}}));
  await assertFails(setDoc(receiptDoc,
      {diamondsCharged: 0, color: "pink", serverConfirmed: true}));
  await assertFails(getDoc(ownerDoc));
  await assertFails(getDoc(receiptDoc));
  assert.deepEqual(await readOwnedCards(db, {uid: a.uid}), ["gold"]);
});
