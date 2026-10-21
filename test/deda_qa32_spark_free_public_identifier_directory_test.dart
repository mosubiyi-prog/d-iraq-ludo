import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_qa32_spark_public_identifier_directory.dart';

void main() {
  const orig = '@DEDA-AQPYXJ';
  const alias = '@DEDA-IRAQI';
  const alias2 = '@DEDA-ROYAL';
  Map<String, dynamic> route({String id=alias,String original=orig,
      String color='gold'}) => {
    'aliasId':id,'originalId':original,'baseColor':color,
    'updatedAt': 'server-only-timestamp',
  };
  Map<String, dynamic> active({String id=alias,String color='gold'}) => {
    'originalId':orig,'activeId':id,'baseColor':color,
    'updatedAt': 'server-only-timestamp',
  };

  test('Spark free-only route is gated until REAL verified Firestore rules exist', () {
    expect(DedaQa32SparkPublicIdentifierDirectory.enabled, false);
  });

  test('same original account for valid active alias and matching public foil', () {
    expect(DedaQa32SparkPublicIdentifierDirectory.originalFromProjection(
      alias, route(), active()), orig);
    expect(DedaQa32SparkPublicIdentifierDirectory.styleFromProjection(
      orig, active()), {
      'requestedId':orig,'displayId':alias,'permanentColor':'gold',
      'serverConfirmed':true,
    });
  });

  test('stale former alias cannot resolve after owner changes active ID', () {
    expect(DedaQa32SparkPublicIdentifierDirectory.originalFromProjection(
      alias, route(), active(id:alias2)), null);
    expect(DedaQa32SparkPublicIdentifierDirectory.originalFromProjection(
      alias, route(), active(id:orig)), null);
    expect(DedaQa32SparkPublicIdentifierDirectory.styleFromProjection(
      orig, active(id:orig,color:'gold')), null);
  });

  test('reject forged, mismatched color, wrong ID or injected identity fields', () {
    expect(DedaQa32SparkPublicIdentifierDirectory.originalFromProjection(
      alias, route(), active(color:'pink')), null);
    expect(DedaQa32SparkPublicIdentifierDirectory.originalFromProjection(
      alias, route(color:'purple'), active(color:'purple')), null);
    expect(DedaQa32SparkPublicIdentifierDirectory.originalFromProjection(
      alias, {...route(),'ownerUid':'spoof'}, active()), null);
    expect(DedaQa32SparkPublicIdentifierDirectory.originalFromProjection(
      alias, route(original:'@DEDA-OTHER'), active()), null);
    expect(DedaQa32SparkPublicIdentifierDirectory.originalFromProjection(
      '@DEDA-A', route(), active()), null);
    expect(DedaQa32SparkPublicIdentifierDirectory.styleFromProjection(
      orig, {...active(),'diamonds':1000000}), null);
    expect(DedaQa32SparkPublicIdentifierDirectory.styleFromProjection(
      orig, active(color:'purple')), null);
  });
}
