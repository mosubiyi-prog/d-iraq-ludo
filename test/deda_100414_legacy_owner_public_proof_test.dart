import 'package:flutter_test/flutter_test.dart';
import '../lib/deda_owner_legacy_public_proof_100414.dart';

void main() {
  const uid='verified-uid';
  const id='@DEDA-ABC123';
  final account={'accountKey':'07700111222'};
  final session={'accountKey':'07700111222'};
  final route={'publicId':id,'kind':'personal','active':true,'ownerUid':uid};

  test('normal legacy account may backfill only its own missing field', () {
    expect(DedaOwnerLegacyPublicProof100414.sameAuthenticatedOwner(
        expectedUid:uid,originalId:id,user:account,session:session,
        route:route),isTrue);
    expect(DedaOwnerLegacyPublicProof100414.sameAuthenticatedOwner(
        expectedUid:uid,originalId:id,
        user:{...account,'sharePersonalId':id},session:session,
        route:route),isTrue);
  });
  test('legacy repair refuses UID/account mismatch and rekey collisions', () {
    expect(DedaOwnerLegacyPublicProof100414.sameAuthenticatedOwner(
        expectedUid:'other',originalId:id,user:account,session:session,
        route:route),isFalse);
    expect(DedaOwnerLegacyPublicProof100414.sameAuthenticatedOwner(
        expectedUid:uid,originalId:id,user:account,
        session:{'accountKey':'other'},route:route),isFalse);
    expect(DedaOwnerLegacyPublicProof100414.sameAuthenticatedOwner(
        expectedUid:uid,originalId:id,
        user:{...account,'sharePersonalId':'@DEDA-OTHER1'},
        session:session,route:route),isFalse);
    expect(DedaOwnerLegacyPublicProof100414.sameAuthenticatedOwner(
        expectedUid:uid,originalId:id,user:account,session:session,
        route:{...route,'ownerUid':'old-uid'}),isFalse);
  });
  test('never creates a normal active row for a premium selection', () {
    expect(DedaOwnerLegacyPublicProof100414.activeSelectionSafe(
        originalId:id,expectedActiveId:id,selection:null),isTrue);
    expect(DedaOwnerLegacyPublicProof100414.activeSelectionSafe(
        originalId:id,expectedActiveId:'@DEDA-IRAQI',selection:null),isFalse);
    expect(DedaOwnerLegacyPublicProof100414.activeSelectionSafe(
        originalId:id,expectedActiveId:id,
        selection:{'originalId':id,'activeId':'@DEDA-IRAQI'}),isFalse);
    expect(DedaOwnerLegacyPublicProof100414.activeSelectionSafe(
        originalId:id,expectedActiveId:'@DEDA-IRAQI',
        selection:{'originalId':id,'activeId':'@DEDA-IRAQI'}),isTrue);
  });
}
