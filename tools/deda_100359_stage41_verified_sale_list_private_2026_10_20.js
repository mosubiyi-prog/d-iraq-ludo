"use strict";

// Server-side list of genuinely sale-approved GROUP002 identifiers only.
// NOT an APK-side mock catalog. Never expose the exclusive owner Group001.
// Inventory is only a preview: purchase rechecks collisions atomically.
// No production export, deployment or database modification here.

const PRICE = 10000;
const ID = /^@DEDA-[A-Z0-9]{6}$/;
function deny(code) {const e=new Error("deda-sale-"+code); e.code=code; throw e;}
const data = x => x.exists ? x.data() || {} : {};

async function readAvailableApprovedIdentifiers(db, {
  approvedCatalog, approvedSuffixes,
} = {}) {
  if (!db || typeof db.collection !== "function" ||
      !approvedCatalog || typeof approvedCatalog.allows !== "function" ||
      !Array.isArray(approvedSuffixes) || approvedSuffixes.length > 100 ||
      new Set(approvedSuffixes).size !== approvedSuffixes.length ||
      !approvedSuffixes.every(x => typeof x === "string" &&
        /^[A-Z0-9]{6}$/.test(x))) {
    deny("failed-precondition");
  }
  const confirmed = [];
  for (const suffix of approvedSuffixes) {
    const identifier = "@DEDA-" + suffix;
    if (!ID.test(identifier) || !approvedCatalog.allows(identifier)) {
      deny("failed-precondition");
    }
    const refs = [
      db.collection("deda_verified_id_sale_catalog").doc(identifier),
      db.collection("deda_owned_identifier_registry").doc(identifier),
      db.collection("deda_owned_identifier_aliases").doc(identifier),
      db.collection("deda_share_ids").doc(identifier),
    ];
    const [stock, owner, alias, legacy] = await Promise.all(
      refs.map(ref => ref.get()));
    const row = data(stock);
    if (stock.exists && row.identifier === identifier &&
        row.group === "002" && row.status === "verified_available" &&
        row.ownerApproved === true && row.priceDiamonds === PRICE &&
        !owner.exists && !alias.exists && !legacy.exists) {
      confirmed.push(Object.freeze({
        identifier, priceDiamonds: PRICE,
      }));
    }
  }
  return Object.freeze({
    serverConfirmed: true,
    priceDiamonds: PRICE,
    identifiers: Object.freeze(confirmed),
  });
}
module.exports = {PRICE, readAvailableApprovedIdentifiers};
