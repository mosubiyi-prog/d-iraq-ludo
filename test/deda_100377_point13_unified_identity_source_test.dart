import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_qa32_active_account_scope.dart';
import 'package:d_iraq_ludo/deda_stage50_verified_friend_ink_badge.dart';
import 'package:d_iraq_ludo/deda_100377_point13_unified_identity_projection_staged.dart';

void main() {
  const uid = 'signed-owner-uid';
  const firstOriginal = '@DEDA-AQPYXJ';
  const secondOriginal = '@DEDA-D62UEB';

  test('Point13 existing canonical routing remains immutable even for verified premium owner',
      () {
    const owner = DedaQa32ActiveAccountIdentity(
      uid: uid, originalId: firstOriginal,
      displayId: '@DEDA-IRAQI', fixedColor: 'gold',
    );
    final projected = DedaPoint13UnifiedIdentity.fromVerifiedOwner(
      currentUid: uid, originalId: firstOriginal, proof: owner,
    );
    expect(projected.routeId, firstOriginal);
    expect(projected.canonicalOriginal, firstOriginal);
    expect(projected.stagedDisplayId, '@DEDA-IRAQI');
    expect(projected.permanentColor, 'gold');
    expect(projected.displayedId, firstOriginal);
    expect(projected.hasLivePremiumFoil, isFalse);
    expect(DedaPoint13UnifiedIdentity.releaseEnabled, isFalse);
  });

  test('Point13 wrong account UID and recycled owner proofs never show premium alias',
      () {
    const owner = DedaQa32ActiveAccountIdentity(
      uid: uid, originalId: firstOriginal,
      displayId: '@DEDA-IRAQI', fixedColor: 'gold',
    );
    final wrongUid = DedaPoint13UnifiedIdentity.fromVerifiedOwner(
      currentUid: 'other-user', originalId: firstOriginal, proof: owner);
    final wrongAccount = DedaPoint13UnifiedIdentity.fromVerifiedOwner(
      currentUid: uid, originalId: secondOriginal, proof: owner);
    expect(wrongUid.stagedDisplayId, firstOriginal);
    expect(wrongAccount.stagedDisplayId, secondOriginal);
    expect(wrongUid.permanentColor, isNull);
    expect(wrongAccount.routeId, secondOriginal);
  });

  test('Point13 public card and sender use consistent alias but never change canonical address',
      () {
    const publicProof = DedaStage50PublicIdStyle(
      requestedId: firstOriginal,
      displayId: '@DEDA-IRAQI',
      permanentColor: 'gold',
    );
    final owner = DedaPoint13UnifiedIdentity.fromVerifiedOwner(
      currentUid: uid, originalId: firstOriginal,
      proof: const DedaQa32ActiveAccountIdentity(
        uid: uid, originalId: firstOriginal,
        displayId: '@DEDA-IRAQI', fixedColor: 'gold',
      ),
    );
    final public = DedaPoint13UnifiedIdentity.fromTrustedPublicBridge(
      originalId: firstOriginal, proof: publicProof);
    expect(owner.stagedDisplayId, public.stagedDisplayId);
    expect(owner.permanentColor, public.permanentColor);
    expect(public.routeId, firstOriginal);
    expect(public.displayedId, firstOriginal); // signed rollout remains off
  });

  test('Point13 stale/cross-account public projection reverts to original',
      () {
    const other = DedaStage50PublicIdStyle(
      requestedId: secondOriginal,
      displayId: '@DEDA-SALEM',
      permanentColor: 'royal',
    );
    final guarded = DedaPoint13UnifiedIdentity.fromTrustedPublicBridge(
      originalId: firstOriginal, proof: other);
    expect(guarded.stagedDisplayId, firstOriginal);
    expect(guarded.permanentColor, isNull);
    expect(guarded.isServerVerified, isFalse);
    final fallback = DedaPoint13UnifiedIdentity.fromTrustedPublicBridge(
      originalId: secondOriginal, proof: null);
    expect(fallback.displayedId, secondOriginal);
    expect(() => DedaPoint13UnifiedIdentity.originalOnly('@DEDA'),
        throwsStateError);
  });

  test('Point13 grants to different accounts must retain original and cannot assign an active ID elsewhere',
      () {
    const secondOwner = DedaQa32ActiveAccountIdentity(
      uid: 'account-B', originalId: secondOriginal,
      displayId: '@DEDA-SALEM', fixedColor: 'diamond',
    );
    final b = DedaPoint13UnifiedIdentity.fromVerifiedOwner(
      currentUid: 'account-B', originalId: secondOriginal,
      proof: secondOwner,
    );
    expect(b.routeId, secondOriginal);
    expect(b.stagedDisplayId, '@DEDA-SALEM');
    final a = DedaPoint13UnifiedIdentity.fromVerifiedOwner(
      currentUid: uid, originalId: firstOriginal,
      proof: secondOwner,
    );
    expect(a.stagedDisplayId, firstOriginal);
    expect(a.hasLivePremiumFoil, isFalse);
  });
}
