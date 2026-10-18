"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {createRequire} = require("node:module");
const {resolve} = require("node:path");
const {readFileSync} = require("node:fs");
assert.match(process.env.FIRESTORE_EMULATOR_HOST || "",
    /^(127\.0\.0\.1|localhost):[0-9]+$/, "SAFE_STOP emulator required");
const projectId = "demo-deda-point15-owned-identifiers";
const req = createRequire(resolve(__dirname, "../functions/package.json"));
const {initializeApp, deleteApp} = req("firebase-admin/app");
const {getFirestore} = req("firebase-admin/firestore");
const {initializeTestEnvironment, assertFails} = req("@firebase/rules-unit-testing");
const {doc, getDoc, setDoc, updateDoc} = req("firebase/firestore");
const {accountHash} = require("../tools/deda_intakadha_point13_atomic_id_card_checkout_2026_10_19.js");
const {readOwnedIdentifiers, activateOwnedIdentifier, adminGrantReservedIdentifier,
  privateReservedCatalog, resolveIdentifierAlias, hashed} =
    require("../tools/deda_intakadha_point15_identifier_ownership_admin_gifts_2026_10_19.js");

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
test.before(async () => {
  app = initializeApp({projectId}, "point15-ownership-emulator-only");
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


const privateNames = Array.from({length: 100},
  (_, i) => "R" + String(i).padStart(3, "0"));
const privateList = privateReservedCatalog(privateNames);
const nameAt = (i) => "@DEDA-" + privateNames[i];
async function gmAccount() {
  const actor = await registered({balance: 9000});
  await db.collection("admin_entry_access").doc(actor.account).set({
    accountKey: actor.account,
    active: true, status: "active",
    allowedRole: "general_manager",
    accessType: "general_manager_gateway",
  });
  return actor;
}
async function gift(gm, recipient, at = 0, color = "royal") {
  return adminGrantReservedIdentifier(db, {
    adminUid: gm.uid, recipientOriginalId: recipient.publicId,
    identifier: nameAt(at), color, privateCatalog: privateList,
  });
}

test("point15 private catalog must be complete exactly 100 unique and never shipped publicly", () => {
  assert.equal(privateList.count, 100);
  for (const input of [null, [], ["SALEM"], [...privateNames, "X999"],
    [...privateNames.slice(0, 99), privateNames[0]], ["..", ...privateNames.slice(1)]]) {
    assert.throws(() => privateReservedCatalog(input));
  }
  assert.equal(privateList.contains(nameAt(4)), true);
  assert.equal(privateList.contains("@DEDA-UNLISTED"), false);
});

test("original ID always appears as owned and active without any migration", async () => {
  const a = await registered({balance: 17000});
  const state = await readOwnedIdentifiers(db, {uid: a.uid});
  assert.deepEqual(state, {
    originalId: a.publicId, activeId: a.publicId,
    ownedIds: [a.publicId], serverConfirmed: true,
  });
  assert.equal((await db.collection("deda_owned_identifier_accounts")
      .doc(hashed(a.account)).get()).exists, false);
});

test("without an owned premium: activation denied, original unaffected", async () => {
  const a = await registered();
  await assert.rejects(activateOwnedIdentifier(db,
    {uid: a.uid, identifier: nameAt(1)}), matchesError("permission-denied"));
  await assert.rejects(activateOwnedIdentifier(db,
    {uid: a.uid, identifier: "@DEDA-NAME"}), matchesError("permission-denied"));
  assert.equal((await readOwnedIdentifiers(db, {uid: a.uid})).activeId, a.publicId);
});

test("ordinary users and forged catalog objects cannot grant reserved IDs", async () => {
  const actor = await registered();
  const target = await registered();
  await assert.rejects(gift(actor, target), matchesError("permission-denied"));
  await assert.rejects(adminGrantReservedIdentifier(db, {
    adminUid: actor.uid, recipientOriginalId: target.publicId,
    identifier: nameAt(2), color: "gold",
    privateCatalog: {count: 100, contains: () => true},
  }), matchesError("permission-denied"));
  assert.equal((await readOwnedIdentifiers(db, {uid: target.uid})).ownedIds.length, 1);
});

test("verified GM grants reserved name with designated color; owns it permanently", async () => {
  const gm = await gmAccount();
  const target = await registered({balance: 16000});
  const beforeUser = (await db.collection("users").doc(target.uid).get()).data();
  const beforeWallet = (await target.wallet.get()).data().balance;
  const g = await gift(gm, target, 3, "diamond");
  assert.equal(g.assignedColor, "diamond");
  assert.deepEqual(g.ownedIds, [target.publicId, nameAt(3)]);
  assert.equal(g.activeId, target.publicId);
  assert.deepEqual((await readOwnedIdentifiers(db, {uid: target.uid})).ownedIds,
    [target.publicId, nameAt(3)]);
  const registry = (await db.collection("deda_owned_identifier_registry")
    .doc(nameAt(3)).get()).data();
  assert.equal(registry.assignedColor, "diamond");
  assert.equal(registry.accountKey, target.account);
  assert.equal((await target.wallet.get()).data().balance, beforeWallet);
  assert.deepEqual((await db.collection("users").doc(target.uid).get()).data(), beforeUser);
  assert.equal((await db.collection("deda_id_card_entitlements")
    .doc(accountHash(target.account)).get()).exists, false,
    "admin assigning identifier/color does not fake ownership of premium cosmetics");
});

test("switch original -> premium -> original, all IDs permanent; no diamonds charged", async () => {
  const gm = await gmAccount();
  const target = await registered({balance: 13000});
  await gift(gm, target, 4, "gold");
  await gift(gm, target, 5, "pink");
  const walletBefore = (await target.wallet.get()).data();
  const one = await activateOwnedIdentifier(db, {uid: target.uid, identifier: nameAt(4)});
  assert.equal(one.activeId, nameAt(4));
  const again = await activateOwnedIdentifier(db, {uid: target.uid, identifier: nameAt(4)});
  assert.deepEqual(again, one);
  await activateOwnedIdentifier(db, {uid: target.uid, identifier: nameAt(5)});
  await activateOwnedIdentifier(db, {uid: target.uid, identifier: target.publicId});
  const state = await readOwnedIdentifiers(db, {uid: target.uid});
  assert.equal(state.activeId, target.publicId);
  assert.deepEqual(state.ownedIds, [target.publicId, nameAt(4), nameAt(5)]);
  assert.deepEqual((await target.wallet.get()).data(), walletBefore);
  assert.equal((await db.collection("deda_owned_identifier_registry")
    .doc(nameAt(4)).get()).exists, true);
});

test("both old alias and active premium resolve to SAME account; resolver never returns location", async () => {
  const gm = await gmAccount();
  const target = await registered();
  await gift(gm, target, 6, "royal");
  await activateOwnedIdentifier(db, {uid: target.uid, identifier: nameAt(6)});
  assert.deepEqual(await resolveIdentifierAlias(db, {identifier: target.publicId}),
    {originalId: target.publicId, accountKey: target.account});
  assert.deepEqual(await resolveIdentifierAlias(db, {identifier: nameAt(6)}),
    {originalId: target.publicId, accountKey: target.account});
  assert.equal(await resolveIdentifierAlias(db, {identifier: "@DEDA-ZZZZ"}), null);
});

test("no duplicate reserved ID grants, including concurrent grants to different users", async () => {
  const gm = await gmAccount();
  const first = await registered();
  const other = await registered();
  const pairs = await Promise.allSettled([
    gift(gm, first, 7, "gold"), gift(gm, other, 7, "royal"),
  ]);
  assert.equal(pairs.filter(x => x.status === "fulfilled").length, 1);
  assert.equal(pairs.filter(x => x.status === "rejected").length, 1);
  const owners = [first, other];
  let ownedCount = 0;
  for (const owner of owners) {
    const state = await readOwnedIdentifiers(db, {uid: owner.uid});
    ownedCount += Number(state.ownedIds.includes(nameAt(7)));
  }
  assert.equal(ownedCount, 1);
  assert.equal((await db.collection("deda_owned_identifier_registry")
    .doc(nameAt(7)).get()).data().status, "owned");
});

test("disabled general manager cannot gift; neither GM wallet nor admin pool spent", async () => {
  const gm = await gmAccount();
  const target = await registered();
  const entry = db.collection("admin_entry_access").doc(gm.account);
  await entry.update({active: false});
  await assert.rejects(gift(gm, target, 8), matchesError("permission-denied"));
  const pool = db.collection("deda_admin_diamond_wallets").doc(fresh("pool"));
  await pool.set({balance: 500000});
  assert.equal((await pool.get()).data().balance, 500000);
  assert.equal((await target.wallet.get()).data().balance, 20000);
});

test("reserved names outside private catalog never grant even by GM", async () => {
  const gm = await gmAccount();
  const target = await registered();
  await assert.rejects(adminGrantReservedIdentifier(db, {
    adminUid: gm.uid, recipientOriginalId: target.publicId,
    identifier: "@DEDA-PRIVATEX", color: "gold", privateCatalog: privateList,
  }), matchesError("permission-denied"));
  await assert.rejects(adminGrantReservedIdentifier(db, {
    adminUid: gm.uid, recipientOriginalId: target.publicId,
    identifier: nameAt(9), color: "silver", privateCatalog: privateList,
  }), matchesError("permission-denied"));
});

test("an existing personal share identifier prevents issuing the same reserved name", async () => {
  const gm = await gmAccount();
  const target = await registered();
  await db.collection("deda_share_ids").doc(nameAt(10)).set({
    kind: "personal", publicId: nameAt(10),
    ownerUid: "some-other-person", active: true,
  });
  await assert.rejects(gift(gm, target, 10), matchesError("already-exists"));
  assert.equal((await readOwnedIdentifiers(db, {uid: target.uid})).ownedIds.length, 1);
});

test("tampered alias/registry ledger cannot grant display or activation", async () => {
  const gm = await gmAccount();
  const target = await registered();
  await gift(gm, target, 11);
  await db.collection("deda_owned_identifier_aliases").doc(nameAt(11))
      .update({accountKey: "different_account"});
  await assert.rejects(readOwnedIdentifiers(db, {uid: target.uid}),
    matchesError("failed-precondition"));
  await assert.rejects(activateOwnedIdentifier(db, {
    uid: target.uid, identifier: nameAt(11),
  }), matchesError("failed-precondition"));
});

test("rotated anonymous UID of SAME verified DEDA account keeps all IDs", async () => {
  const gm = await gmAccount();
  const oldUid = fresh("old");
  const newUid = fresh("new");
  const target = await registered({uid: newUid, registeredUid: oldUid});
  // Old UID has only accountKey; gift recipient verifies original sharePersonalId.
  await db.collection("users").doc(oldUid).update({sharePersonalId: target.publicId});
  await gift(gm, target, 12);
  const selected = await activateOwnedIdentifier(db, {
    uid: newUid, identifier: nameAt(12),
  });
  assert.equal(selected.activeId, nameAt(12));
  assert.deepEqual((await readOwnedIdentifiers(db, {uid: newUid})).ownedIds,
    [target.publicId, nameAt(12)]);
});

test("logout/session spoof blocks selection, does not erase existing active ID", async () => {
  const gm = await gmAccount();
  const target = await registered();
  await gift(gm, target, 13);
  await activateOwnedIdentifier(db, {uid: target.uid, identifier: nameAt(13)});
  await db.collection("deda_sessions").doc(target.uid)
    .update({accountKey: "forged_another_account"});
  await assert.rejects(readOwnedIdentifiers(db, {uid: target.uid}),
    matchesError("permission-denied"));
  await assert.rejects(activateOwnedIdentifier(db, {
    uid: target.uid, identifier: target.publicId,
  }), matchesError("permission-denied"));
  const snapshot = await db.collection("deda_owned_identifier_accounts")
    .doc(hashed(target.account)).get();
  assert.equal(snapshot.data().activeId, nameAt(13));
});

test("untrusted mobile clients cannot write gift, ownership registry, alias or account ledger", async () => {
  const gm = await gmAccount();
  const target = await registered();
  await gift(gm, target, 14);
  const client = env.authenticatedContext(target.uid).firestore();
  const safe = [
    doc(client, "deda_owned_identifier_accounts", hashed(target.account)),
    doc(client, "deda_owned_identifier_registry", nameAt(14)),
    doc(client, "deda_owned_identifier_aliases", nameAt(14)),
  ];
  for (const ref of safe) {
    await assertFails(setDoc(ref, {accountKey: target.account,
      originalId: target.publicId, ownedIds: [nameAt(14)],
      activeId: nameAt(14)}));
    await assertFails(getDoc(ref));
  }
});

test("concurrent owned switch settles to one valid active ID with permanent old aliases", async () => {
  const gm = await gmAccount();
  const target = await registered();
  await gift(gm, target, 15);
  await gift(gm, target, 16);
  const results = await Promise.all([
    activateOwnedIdentifier(db, {uid: target.uid, identifier: nameAt(15)}),
    activateOwnedIdentifier(db, {uid: target.uid, identifier: nameAt(16)}),
  ]);
  assert.equal(results.length, 2);
  const final = await readOwnedIdentifiers(db, {uid: target.uid});
  assert.ok([nameAt(15), nameAt(16)].includes(final.activeId));
  assert.deepEqual(final.ownedIds,
    [target.publicId, nameAt(15), nameAt(16)]);
});

test("no identity reuse through tampered personal share owner mapping", async () => {
  const gm = await gmAccount();
  const target = await registered();
  await gift(gm, target, 17);
  await db.collection("deda_share_ids").doc(target.publicId)
    .update({ownerUid: "stolen_owner"});
  await assert.rejects(activateOwnedIdentifier(db, {
    uid: target.uid, identifier: nameAt(17),
  }), matchesError("permission-denied"));
});
