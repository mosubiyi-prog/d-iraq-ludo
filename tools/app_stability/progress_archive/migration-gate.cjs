'use strict';
// UNWIRED trusted-worker contract, not an approval producer or client API.
// Every document below must be produced by a separate migration reviewer.
const core = require('./reconcile-core.cjs');
const {validateBaselineEvidence}=require('./baseline-evidence.cjs');
const {reconcileVerifiedReceipt} = require('./reconcile-store.cjs');
function fail(code) { throw Object.assign(new Error(code), {code}); }
function exact(value, keys, code) {
  if (!value || typeof value !== 'object' || Array.isArray(value) ||
      Object.keys(value).length !== keys.length ||
      !keys.every(key => Object.hasOwn(value, key))) fail(code);
}
function id(value) { return typeof value === 'string' && /^[A-Za-z0-9_-]{20,80}$/.test(value); }
function hash(value) { return typeof value === 'string' && /^[a-f0-9]{64}$/.test(value); }
function parseMigration(raw, accountKey) {
  core.account(accountKey);
  exact(raw, ['format','accountKey','migrationId','phase','evidenceDigest','baselineEventKey','settlementId'], 'migration-required');
  if (raw.format !== 1 || raw.accountKey !== accountKey || !id(raw.migrationId) ||
      !['pending','evidence-saved','baseline-approved','cutover-complete'].includes(raw.phase)) fail('invalid-migration');
  if (raw.phase === 'pending') {
    if ([raw.evidenceDigest, raw.baselineEventKey, raw.settlementId].some(v => v !== null)) fail('invalid-migration');
  } else {
    if (!hash(raw.evidenceDigest)) fail('invalid-migration');
    if (raw.phase === 'evidence-saved') {
      if (raw.baselineEventKey !== null || raw.settlementId !== null) fail('invalid-migration');
    } else if (!hash(raw.baselineEventKey) ||
      (raw.phase === 'baseline-approved' ? raw.settlementId !== null && !id(raw.settlementId) : !id(raw.settlementId))) fail('invalid-migration');
  }
  return Object.freeze({...raw});
}
function validateSettlement(raw, migration) {
  exact(raw, ['format','accountKey','migrationId','evidenceDigest','baselineEventKey','legacyFenceId','pendingPurchases','pendingReservations'], 'migration-settlement-required');
  if (raw.format !== 1 || raw.accountKey !== migration.accountKey ||
      raw.migrationId !== migration.migrationId || raw.evidenceDigest !== migration.evidenceDigest ||
      raw.baselineEventKey !== migration.baselineEventKey || !id(raw.legacyFenceId) ||
      raw.pendingPurchases !== 0 || raw.pendingReservations !== 0) fail('migration-not-settled');
}
async function reconcileMigratedReceipt({store, accountKey, receiptId}) {
  core.account(accountKey);
  if (!id(receiptId)) fail('invalid-receipt-id');
  // Wrap the SAME transaction. Approval/classification reads participate in
  // conflicts/retries; no check outside a transaction or second wallet write.
  const gatedStore = {
    serverTimestamp: () => store.serverTimestamp(),
    runTransaction: action => store.runTransaction(async tx => {
      const root = `deda_progress_migrations/${accountKey}`;
      const migration = parseMigration(await tx.get(root), accountKey);
      if (migration.phase !== 'cutover-complete') fail('migration-pending');
      validateSettlement(await tx.get(`${root}/settlements/${migration.settlementId}`), migration);
      const state = core.parseState(await tx.get(`deda_verified_progress/${accountKey}`), accountKey);
      if (state.initializedBy !== migration.baselineEventKey) fail('migration-baseline-conflict');
      const baseline = await tx.get(`deda_verified_progress/${accountKey}/events/${migration.baselineEventKey}`);
      if (!baseline || baseline.format !== 1 || baseline.accountKey !== accountKey ||
          baseline.eventKey !== migration.baselineEventKey || baseline.appliedVersion !== 1) fail('migration-baseline-missing');
      const initial = core.parseReceipt(baseline.receipt, accountKey);
      if (initial.source !== 'legacy-baseline-v1' || core.eventKey(initial) !== migration.baselineEventKey) fail('migration-baseline-conflict');
      await validateBaselineEvidence(tx,migration,initial);
      const raw = await tx.get(`deda_progress_receipts/${accountKey}/events/${receiptId}`);
      if (raw === null) fail('verified-receipt-missing');
      const receipt = core.parseReceipt(raw, accountKey);
      if (receipt.kind === 'baseline') fail('migration-baseline-already-sealed');
      const key = core.eventKey(receipt);
      const classification = await tx.get(`${root}/classifications/${key}`);
      exact(classification, ['format','accountKey','migrationId','evidenceDigest','disposition','receipt'], 'migration-classification-required');
      if (classification.format !== 1 || classification.accountKey !== accountKey ||
          classification.migrationId !== migration.migrationId || classification.evidenceDigest !== migration.evidenceDigest ||
          !['included-in-baseline','after-cutover'].includes(classification.disposition) ||
          !core.sameEvent(core.parseReceipt(classification.receipt, accountKey), receipt)) fail('migration-classification-conflict');
      if (classification.disposition === 'included-in-baseline') {
        // Detect contradictory prior use through the low-level prototype.
        if (await tx.get(`deda_verified_progress/${accountKey}/events/${key}`) !== null) fail('migration-event-already-applied');
        return Object.freeze({replayed: true, includedInBaseline: true, state});
      }
      return action(tx);
    }),
  };
  return reconcileVerifiedReceipt({store: gatedStore, accountKey, receiptId});
}
module.exports = {parseMigration, validateSettlement, reconcileMigratedReceipt};
