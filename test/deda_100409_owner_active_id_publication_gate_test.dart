import 'package:flutter_test/flutter_test.dart';
import '../lib/deda_active_id_public_sync_100409.dart';
import '../lib/deda_qa32_spark_public_identifier_directory.dart';

void main() {
  const uid = 'actual-owner-uid';
  const original = '@DEDA-AQPYXJ';
  const premium = '@DEDA-IRAQI';

  test('verified premium projection gated by matching Firebase UID', () {
    expect(DedaActiveIdPublicSync100409.shouldPublish(
      uid: uid, currentUid: uid, originalId: original,
      activeId: premium, fixedColor: 'gold',
    ), isTrue);
    expect(DedaActiveIdPublicSync100409.shouldPublish(
      uid: uid, currentUid: 'other-account', originalId: original,
      activeId: premium, fixedColor: 'gold',
    ), isFalse);
  });

  test('never publishes guessed, original, wrongly-colored IDs', () {
    for (final candidate in [
      ('@DEDA-FAKE!', 'gold'),
      (premium, 'invalid'),
      (premium, null),
    ]) {
      expect(DedaActiveIdPublicSync100409.shouldPublish(
        uid: uid, currentUid: uid, originalId: original,
        activeId: candidate.$1, fixedColor: candidate.$2,
      ), isFalse);
    }
  });

  test('server-confirmed return to original ID can clear public premium display', () {
    expect(DedaActiveIdPublicSync100409.shouldPublish(
      uid: uid, currentUid: uid, originalId: original,
      activeId: original, fixedColor: null,
    ), isTrue);
    expect(DedaActiveIdPublicSync100409.shouldPublish(
      uid: uid, currentUid: uid, originalId: original,
      activeId: original, fixedColor: 'gold',
    ), isFalse);
  });

  test('remote change back to an earlier premium ID must be reconciled', () {
    final active = <String, dynamic>{
      'originalId': original,
      'activeId': '@DEDA-NEWER',
      'baseColor': 'royal',
      'updatedAt': 'server-time',
    };
    final staleRoute = <String, dynamic>{
      'aliasId': premium,
      'originalId': original,
      'baseColor': 'gold',
      'updatedAt': 'server-time',
    };
    // This ID may have been successfully published previously. That success
    // is not evidence that the present public projection still matches.
    expect(DedaActiveIdPublicSync100409.needsPublication(
      originalId: original, activeId: premium, fixedColor: 'gold',
      currentProjection: active, aliasRoute: staleRoute,
    ), isTrue);
  });

  test('matching premium projection does not require a Firestore write', () {
    final active = <String, dynamic>{
      'originalId': original,
      'activeId': premium,
      'baseColor': 'gold',
      'updatedAt': 'server-time',
    };
    final route = <String, dynamic>{
      'aliasId': premium, 'originalId': original,
      'baseColor': 'gold', 'updatedAt': 'server-time',
    };
    expect(DedaActiveIdPublicSync100409.needsPublication(
      originalId: original, activeId: premium, fixedColor: 'gold',
      currentProjection: active, aliasRoute: route,
    ), isFalse);
    expect(DedaActiveIdPublicSync100409.needsPublication(
      originalId: original, activeId: original, fixedColor: null,
      currentProjection: active, aliasRoute: null,
    ), isTrue);
  });

  test('strict public projection proof rejects stale, mismatched aliases', () {
    final exact = <String, dynamic>{
      'originalId': original, 'activeId': premium,
      'baseColor': 'gold', 'updatedAt': 'timestamp-fixture',
    };
    expect(DedaQa32SparkPublicIdentifierDirectory.styleFromProjection(
      original, exact)?['displayId'], premium);
    expect(DedaQa32SparkPublicIdentifierDirectory.styleFromProjection(
      '@DEDA-DWPKYD', exact), isNull);
    expect(DedaQa32SparkPublicIdentifierDirectory.styleFromProjection(
      original, {...exact, 'unknown': true}), isNull);
    expect(DedaQa32SparkPublicIdentifierDirectory.styleFromProjection(
      original, {...exact, 'activeId': original}), isNull);
  });
}
