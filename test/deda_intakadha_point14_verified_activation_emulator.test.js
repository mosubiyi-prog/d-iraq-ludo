"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {createRequire} = require("node:module");
const {resolve} = require("node:path");
const {readFileSync} = require("node:fs");
assert.match(process.env.FIRESTORE_EMULATOR_HOST || "",
    /^(127\.0\.0\.1|localhost):[0-9]+$/, "SAFE_STOP emulator required");
const projectId = "demo-deda-point14-verified-card-use";
const req = createRequire(resolve(__dirname, "../functions/package.json"));
const {initializeApp, deleteApp} = req("firebase-admin/app");
const {getFirestore} = req("firebase-admin/firestore");
const {initializeTestEnvironment, assertFails} = req("@firebase/rules-unit-testing");
const {doc, getDoc, setDoc, updateDoc} = req("firebase/firestore");
const {checkoutIdCard, accountHash} =
    require("../tools/deda_intakadha_point13_atomic_id_card_checkout_2026_10_19.js");
const {readVerifiedCardState, activateVerifiedCard} =
    require("../tools/deda_intakadha_point14_verified_card_activation_2026_10_19.js");

let db;
let app;
let env;
let serial = 0;
function fresh(label) {
  serial++;
  return label + "_" + String(serial).padStart(5, "0");
}
function matchesError(code) {
  return (err) => Boolean(err && err.code === code);
}
async function registered({
  balance = 20000, account = null, uid = null, registeredUid = null,
} = {}) {
  const key = account || fresh("account");
  const currentUid = uid || fresh("user");
  const originalUid = registeredUid || currentUid;
  const publicId = "@DEDA-" + String(serial).padStart(6, "0");
  const batch = db.batch();
  batch.set(db.collection("users").doc(currentUid), {
    accountKey: key, sharePersonalId: publicId, name: "Stable User",
  });
  batch.set(db.collection("deda_sessions").doc(currentUid), {
    accountKey: key, uid: currentUid,
  });
  if (originalUid !== currentUid) {
    batch.set(db.collection("users").doc(originalUid), {accountKey: key});
  }
  batch.set(db.collection("deda_share_ids").doc(publicId), {
    publicId, kind: "personal", active: true, ownerUid: originalUid,
  });
  batch.set(db.collection("deda_diamond_gift_balances").doc(publicId), {
    publicId, balance,
  });
  await batch.commit();
  return {
    uid: currentUid, account: key, publicId,
    wallet: db.collection("deda_diamond_gift_balances").doc(publicId),
    entitlement: db.collection("deda_id_card_entitlements").doc(accountHash(key)),
  };
}
async function purchase(user, color, requestId = null) {
  return checkoutIdCard(db, {
    uid: user.uid, color,
    requestId: requestId || fresh("purchase_request"),
  });
}
async function state(user) {
  return readVerifiedCardState(db, {uid: user.uid});
}
async function activate(user, color) {
  return activateVerifiedCard(db, {uid: user.uid, color});
}

test.before(async () => {
  app = initializeApp({projectId}, "point14-verified-card-only");
  db = getFirestore(app);
  env = await initializeTestEnvironment({
    projectId,
    firestore: {
      host: "127.0.0.1",
      port: Number(process.env.FIRESTORE_EMULATOR_HOST.split(":")[1]),
      rules: readFileSync(resolve(__dirname, "../firestore.rules"), "utf8"),
    },
  });
});
test.after(async () => {
  if (env) await env.cleanup();
  if (app) await deleteApp(app);
});

test("no payment record means no owned colors and normal profile ID", async () => {
  const u = await registered();
  assert.deepEqual(await state(u), {
    identifier: u.publicId, ownedColors: [], activeColor: null,
  });
  await assert.rejects(activate(u, "gold"), matchesError("permission-denied"));
  assert.equal((await u.entitlement.get()).exists, false);
});

test("purchased style activates and persists through fresh server read", async () => {
  const u = await registered();
  await purchase(u, "gold");
  const before = await state(u);
  assert.deepEqual(before.ownedColors, ["gold"]);
  assert.equal(before.activeColor, null);
  const selected = await activate(u, "gold");
  assert.deepEqual(selected, {
    identifier: u.publicId,
    ownedColors: ["gold"],
    activeColor: "gold",
  });
  assert.deepEqual(await state(u), selected);
  assert.equal((await u.wallet.get()).data().balance, 15000);
  assert.equal((await u.entitlement.get()).data().activeColor, "gold");
});

test("switch owned colors without charging diamonds or losing ownership", async () => {
  const u = await registered({balance: 25000});
  await purchase(u, "gold");
  await purchase(u, "pink");
  const afterTwoBuys = (await u.wallet.get()).data().balance;
  assert.equal(afterTwoBuys, 15000);
  await activate(u, "gold");
  await activate(u, "pink");
  const fresh = await state(u);
  assert.deepEqual(fresh.ownedColors, ["gold", "pink"]);
  assert.equal(fresh.activeColor, "pink");
  assert.equal((await u.wallet.get()).data().balance, afterTwoBuys);
  const rows = await u.entitlement.get();
  assert.deepEqual(rows.data().colors, {gold: true, pink: true});
});

test("unowned style and forged display color fail, without charging or writing", async () => {
  const u = await registered();
  await purchase(u, "royal");
  for (const color of ["pink", "diamond", "gold"]) {
    await assert.rejects(activate(u, color), matchesError("permission-denied"));
  }
  await assert.rejects(activate(u, "purple"), matchesError("invalid-argument"));
  assert.equal((await u.entitlement.get()).data().activeColor, undefined);
  assert.equal((await u.wallet.get()).data().balance, 15000);
});

test("same account after rotating anonymous UID retains active and owned color", async () => {
  const previousUid = fresh("old_user");
  const nextUid = fresh("new_user");
  const u = await registered({uid: nextUid, registeredUid: previousUid});
  await purchase(u, "diamond");
  await activate(u, "diamond");
  assert.deepEqual(await state(u), {
    identifier: u.publicId, ownedColors: ["diamond"], activeColor: "diamond",
  });
  assert.equal((await u.wallet.get()).data().balance, 15000);
});

test("cannot use another account's owned card even with same requested color", async () => {
  const owner = await registered();
  const other = await registered();
  await purchase(owner, "gold");
  await activate(owner, "gold");
  await assert.rejects(activate(other, "gold"), matchesError("permission-denied"));
  assert.deepEqual((await state(other)).ownedColors, []);
  assert.equal((await other.wallet.get()).data().balance, 20000);
  assert.equal((await owner.wallet.get()).data().balance, 15000);
});

test("invalid session or stolen registered ID blocks read and activation", async () => {
  const u = await registered();
  await purchase(u, "gold");
  await db.collection("deda_sessions").doc(u.uid).update({
    accountKey: "impersonated-account",
  });
  await assert.rejects(state(u), matchesError("permission-denied"));
  await assert.rejects(activate(u, "gold"), matchesError("permission-denied"));
  await db.collection("deda_sessions").doc(u.uid).update({
    accountKey: u.account,
  });
  await db.collection("users").doc(fresh("victim")).set({accountKey: "victim"});
  const share = db.collection("deda_share_ids").doc(u.publicId);
  await share.update({ownerUid: "unknown_registered_owner"});
  await assert.rejects(state(u), matchesError("permission-denied"));
});

test("concurrent activation switches remain one valid owned color with no debit", async () => {
  const u = await registered({balance: 20000});
  await purchase(u, "gold");
  await purchase(u, "pink");
  const results = await Promise.all([
    activate(u, "gold"), activate(u, "pink"), activate(u, "gold"),
  ]);
  assert.equal(results.length, 3);
  const finalState = await state(u);
  assert.ok(["gold", "pink"].includes(finalState.activeColor));
  assert.deepEqual(finalState.ownedColors, ["gold", "pink"]);
  assert.equal((await u.wallet.get()).data().balance, 10000);
});

test("invalid database activeColor cannot be promoted to unowned membership", async () => {
  const u = await registered();
  await purchase(u, "gold");
  await u.entitlement.update({activeColor: "pink"});
  const fresh = await state(u);
  assert.equal(fresh.activeColor, null);
  await assert.rejects(activate(u, "pink"), matchesError("permission-denied"));
  await activate(u, "gold");
  assert.equal((await state(u)).activeColor, "gold");
});

test("untrusted mobile client cannot mint or update activeColor or owned list", async () => {
  const u = await registered();
  await purchase(u, "gold");
  await activate(u, "gold");
  const client = env.authenticatedContext(u.uid).firestore();
  const entitlementRef = doc(client,
      "deda_id_card_entitlements", accountHash(u.account));
  await assertFails(updateDoc(entitlementRef, {activeColor: "pink"}));
  await assertFails(setDoc(entitlementRef, {
    accountKey: u.account, colors: {pink: true}, activeColor: "pink",
  }));
  await assertFails(getDoc(entitlementRef));
  assert.equal((await state(u)).activeColor, "gold");
});

test("activation never changes account public ID, profile, wallet or the admin gift pool", async () => {
  const u = await registered({balance: 9000});
  const pool = db.collection("deda_admin_diamond_wallets").doc(fresh("gift_pool"));
  await pool.set({balance: 1000000});
  await purchase(u, "royal");
  const beforeUser = (await db.collection("users").doc(u.uid).get()).data();
  const beforeShare = (await db.collection("deda_share_ids").doc(u.publicId).get()).data();
  const beforeBalance = (await u.wallet.get()).data().balance;
  await activate(u, "royal");
  assert.deepEqual((await db.collection("users").doc(u.uid).get()).data(), beforeUser);
  assert.deepEqual((await db.collection("deda_share_ids").doc(u.publicId).get()).data(), beforeShare);
  assert.equal((await u.wallet.get()).data().balance, beforeBalance);
  assert.equal((await pool.get()).data().balance, 1000000);
});
