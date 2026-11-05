import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:d_iraq_ludo/deda_step2_recovery_guardian.dart';

/// STAGED QA ONLY. Run after resolving the vault/source test package layout.
/// These tests use no Firebase or real accounts, and cannot authorize release.
const account = '9647712345678';
const uid = 'owner-original-uid';
const originalId = '@DEDA-ABC123';
const intent = 'private_recovery_intent_20261104';

class _Journal implements DedaVaultRecoveryJournal {
  final rows = <String, DedaVaultJournalRow>{};
  int created = 0;
  int complete = 0;
  String key(DedaVaultVerifiedScope s, DedaVaultCode c) =>
      s.operationKey(c);

  @override
  Future<DedaVaultJournalRow?> read(
      DedaVaultVerifiedScope s, DedaVaultCode code) async => rows[key(s, code)];

  @override
  Future<bool> reserveIfAbsent(
      DedaVaultVerifiedScope s, DedaVaultCode code, String op) async {
    if (rows.containsKey(key(s, code))) return false;
    created++;
    rows[key(s, code)] = DedaVaultJournalRow(
        operationKey: op, state: DedaVaultJournalState.reserved);
    return true;
  }

  @override
  Future<void> markVerified(DedaVaultVerifiedScope s,
      DedaVaultCode code, String op, String receipt) async {
    final current = rows[key(s, code)];
    if (current == null || current.operationKey != op) {
      throw StateError('missing atomic reservation');
    }
    if (current.state == DedaVaultJournalState.verified &&
        current.receiptId != receipt) {
      throw StateError('receipt changed');
    }
    complete++;
    rows[key(s, code)] = DedaVaultJournalRow(
        operationKey: op, state: DedaVaultJournalState.verified,
        receiptId: receipt);
  }
}

class _Worker implements DedaVaultWorkerAdapter {
  _Worker(this.code);
  @override
  final DedaVaultCode code;
  int executions = 0;
  DedaVaultReceipt? receipt;
  Completer<void>? holdExecution;
  bool badReceipt = false;

  @override
  Future<void> executeOnce(DedaVaultVerifiedScope s, String op) async {
    executions++;
    if (holdExecution != null) await holdExecution!.future;
    receipt = DedaVaultReceipt(
      accountKey: badReceipt ? 'other-account' : s.accountKey,
      originalUid: s.originalUid,
      code: code,
      operationKey: op,
      receiptId: 'trusted-readback-001',
    );
  }

  @override
  Future<DedaVaultReceipt?> confirmByReadback(
      DedaVaultVerifiedScope scope, String operationKey) async => receipt;
}

/// A reviewed adapter can defer ONLY its own optional source domain.
class _PreflightWorker extends _Worker implements DedaVaultPreflightAdapter {
  _PreflightWorker(super.code, this.outcome);
  final DedaVaultPreflightOutcome outcome;
  int preflights = 0;
  @override
  Future<DedaVaultPreflightOutcome> preflight(
      DedaVaultVerifiedScope scope) async {
    preflights++;
    await scope.checkOwner();
    return outcome;
  }
}

DedaVaultVerifiedScope _scope({
  bool Function()? current, Future<bool> Function()? owner,
}) => DedaVaultVerifiedScope(
  accountKey: account,
  originalUid: uid,
  originalId: originalId,
  intentId: intent,
  isCurrentIntent: current ?? () => true,
  verifyOriginalOwnerOnServer: owner ?? () async => true,
);

DedaStep2RecoveryGuardian _guardian(
    _Journal j, Map<DedaVaultCode, DedaVaultWorkerAdapter> adapters,
    {bool enabled = true}) =>
  DedaStep2RecoveryGuardian(journal: j, adapters: adapters,
      enabledForPrivateTests: enabled);

void main() {
  const evidence = DedaVaultCode.originalBackupReadback;
  const paid = DedaVaultCode.linkedPinReissue;
  const social = DedaVaultCode.socialService;
  const points = DedaVaultCode.levelPointsRestore;

  test('all 12 original codes are registered exactly once', () {
    expect(DedaVaultManifest.all.length, 12);
    expect(DedaVaultManifest.all.map((x) => x.code).toSet(),
        DedaVaultCode.values.toSet());
    expect(DedaVaultManifest.spec(paid).mode,
        DedaVaultWorkerMode.separateServerProcess);
    expect(DedaVaultManifest.spec(social).mode,
        DedaVaultWorkerMode.reviewOnly);
    expect(DedaVaultManifest.spec(points).dependencies, contains(evidence));
  });

  test('guardian is OFF by default and no background action exists', () async {
    final j = _Journal();
    final g = DedaStep2RecoveryGuardian(journal: j, adapters: {});
    expect(dedaStep2RecoveryGuardianEnabled, false);
    await expectLater(
      g.run(scope: _scope(),
        trigger: DedaVaultRecoveryTrigger.explicitUserRequest,
        phase: DedaVaultRecoveryPhase.verifiedReplacementPhone,
        selectedCodes: {evidence}),
      throwsStateError,
    );
    expect(j.created, 0);
  });

  test('PIN backend, UID linking, UI and social writes cannot auto-dispatch', () async {
    final j = _Journal();
    expect(() => _guardian(j, {social: _Worker(social)}), throwsArgumentError);
    final g = _guardian(j, {evidence: _Worker(evidence)});
    for (final forbidden in <DedaVaultCode>[
      paid, social, DedaVaultCode.ownerUidContinuity,
      DedaVaultCode.ownerConfirmationUi, DedaVaultCode.assetsReadback,
    ]) {
      await expectLater(
        g.run(scope: _scope(),
          trigger: DedaVaultRecoveryTrigger.explicitUserRequest,
          phase: DedaVaultRecoveryPhase.verifiedReplacementPhone,
          selectedCodes: {forbidden}),
        throwsStateError,
      );
    }
    expect(j.created, 0);
  });

  test('explicit verified readback reserves once, verifies, never claims full recovery', () async {
    final j = _Journal(), w = _Worker(evidence);
    final g = _guardian(j, {evidence: w});
    final first = await g.run(
      scope: _scope(), trigger: DedaVaultRecoveryTrigger.explicitUserRequest,
      phase: DedaVaultRecoveryPhase.verifiedReplacementPhone,
      selectedCodes: {evidence},
    );
    expect(j.created, 1);
    expect(j.complete, 1);
    expect(w.executions, 1);
    expect(first.stepStates[evidence], DedaVaultStepState.verified);
    expect(first.fullAccountRestored, false);
    expect(first.mayGrantDiamonds, false);
    expect(first.mayGrantRewards, false);
    final second = await g.run(
      scope: _scope(), trigger: DedaVaultRecoveryTrigger.explicitUserRequest,
      phase: DedaVaultRecoveryPhase.verifiedReplacementPhone,
      selectedCodes: {evidence},
    );
    expect(second.stepStates[evidence], DedaVaultStepState.verified);
    expect(j.created, 1);
    expect(w.executions, 1);
  });

  test('missing paid source stays review-only while level and place proceed',
      () async {
    final journal=_Journal();
    final original=_Worker(evidence);
    final purchase=_PreflightWorker(
      DedaVaultCode.purchaseBackupReadback,
      DedaVaultPreflightOutcome.evidenceNeedsReview);
    final level=_Worker(points);
    final published=_Worker(DedaVaultCode.publishedPlaceRecovery);
    final guardian=_guardian(journal,{
      evidence:original,
      purchase.code:purchase,
      points:level,
      published.code:published,
    });
    final result=await guardian.run(
      scope:_scope(),trigger:DedaVaultRecoveryTrigger.explicitUserRequest,
      phase:DedaVaultRecoveryPhase.verifiedReplacementPhone,
      selectedCodes:{evidence,purchase.code,points,published.code});
    expect(result.stoppedSafely,false);
    expect(result.stepStates[evidence],DedaVaultStepState.verified);
    expect(result.stepStates[purchase.code],DedaVaultStepState.needsReview);
    expect(result.stepStates[points],DedaVaultStepState.verified);
    expect(result.stepStates[published.code],DedaVaultStepState.verified);
    expect(journal.created,3);
    expect(purchase.preflights,1);
    expect(purchase.executions,0);
    expect(journal.rows.containsKey(_scope().operationKey(purchase.code)),false);
    expect(result.fullAccountRestored,false);
    expect(result.mayGrantDiamonds,false);
  });

  test('no published place is not applicable, not a fake verified receipt',
      () async {
    final journal=_Journal();
    final absent=_PreflightWorker(
      DedaVaultCode.publishedPlaceRecovery,
      DedaVaultPreflightOutcome.notApplicable);
    final original=_Worker(evidence);
    final level=_Worker(points);
    final guardian=_guardian(journal,{
      evidence:original,points:level,absent.code:absent});
    for (var n=0;n<2;n++) {
      final result=await guardian.run(
        scope:_scope(),trigger:DedaVaultRecoveryTrigger.explicitUserRequest,
        phase:DedaVaultRecoveryPhase.verifiedReplacementPhone,
        selectedCodes:{evidence,points,absent.code});
      expect(result.stoppedSafely,false);
      expect(result.stepStates[absent.code],DedaVaultStepState.notApplicable);
      expect(result.fullAccountRestored,false);
    }
    expect(journal.created,2);
    expect(absent.preflights,2);
    expect(absent.executions,0);
    expect(journal.rows.containsKey(_scope().operationKey(absent.code)),false);
  });

  test('existing uncertain reservation is never re-executed', () async {
    final j = _Journal(), w = _Worker(evidence), s = _scope();
    j.rows[s.operationKey(evidence)] = DedaVaultJournalRow(
      operationKey: s.operationKey(evidence),
      state: DedaVaultJournalState.reserved,
    );
    final result = await _guardian(j, {evidence: w}).run(
      scope: s, trigger: DedaVaultRecoveryTrigger.explicitUserRequest,
      phase: DedaVaultRecoveryPhase.verifiedReplacementPhone,
      selectedCodes: {evidence},
    );
    expect(result.stepStates[evidence], DedaVaultStepState.needsReview);
    expect(w.executions, 0);
  });

  test('verified resume without an existing journal cannot invent a new task', () async {
    final j = _Journal(), w = _Worker(evidence);
    final result = await _guardian(j, {evidence: w}).run(
      scope: _scope(),
      trigger: DedaVaultRecoveryTrigger.explicitlyVerifiedResume,
      phase: DedaVaultRecoveryPhase.verifiedReplacementPhone,
      selectedCodes: {evidence},
    );
    expect(result.stepStates[evidence], DedaVaultStepState.blocked);
    expect(w.executions, 0);
    expect(j.created, 0);
  });

  test('wrong server owner proof rejects without journal or execution', () async {
    final j = _Journal(), w = _Worker(evidence);
    await expectLater(
      _guardian(j, {evidence: w}).run(
        scope: _scope(owner: () async => false),
        trigger: DedaVaultRecoveryTrigger.explicitUserRequest,
        phase: DedaVaultRecoveryPhase.verifiedReplacementPhone,
        selectedCodes: {evidence},
      ),
      throwsStateError,
    );
    expect(j.created, 0);
    expect(w.executions, 0);
  });

  test('changed identity intent aborts before work', () async {
    final j = _Journal(), w = _Worker(evidence);
    await expectLater(
      _guardian(j, {evidence: w}).run(
        scope: _scope(current: () => false),
        trigger: DedaVaultRecoveryTrigger.explicitUserRequest,
        phase: DedaVaultRecoveryPhase.verifiedReplacementPhone,
        selectedCodes: {evidence},
      ),
      throwsStateError,
    );
    expect(w.executions, 0);
  });

  test('foreign UID/account receipt is never accepted', () async {
    final j = _Journal(), w = _Worker(evidence)..badReceipt = true;
    final result = await _guardian(j, {evidence: w}).run(
      scope: _scope(), trigger: DedaVaultRecoveryTrigger.explicitUserRequest,
      phase: DedaVaultRecoveryPhase.verifiedReplacementPhone,
      selectedCodes: {evidence},
    );
    expect(result.stepStates[evidence], DedaVaultStepState.needsReview);
    expect(j.complete, 0);
  });

  test('missing dependency prevents points replay', () async {
    final j = _Journal(), w = _Worker(points);
    final result = await _guardian(j, {points: w}).run(
      scope: _scope(), trigger: DedaVaultRecoveryTrigger.explicitUserRequest,
      phase: DedaVaultRecoveryPhase.verifiedReplacementPhone,
      selectedCodes: {points},
    );
    expect(result.stepStates[points], DedaVaultStepState.blockedByDependency);
    expect(w.executions, 0);
  });

  test('concurrent requests cannot both execute on one guardian', () async {
    final j = _Journal(), w = _Worker(evidence);
    w.holdExecution = Completer<void>();
    final g = _guardian(j, {evidence: w});
    final started = g.run(
      scope: _scope(), trigger: DedaVaultRecoveryTrigger.explicitUserRequest,
      phase: DedaVaultRecoveryPhase.verifiedReplacementPhone,
      selectedCodes: {evidence},
    );
    await expectLater(
      g.run(scope: _scope(),
        trigger: DedaVaultRecoveryTrigger.explicitUserRequest,
        phase: DedaVaultRecoveryPhase.verifiedReplacementPhone,
        selectedCodes: {evidence}),
      throwsStateError,
    );
    w.holdExecution!.complete();
    final result = await started;
    expect(result.stepStates[evidence], DedaVaultStepState.verified);
    expect(w.executions, 1);
  });
}
