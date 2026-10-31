import 'package:flutter_test/flutter_test.dart';
import '../lib/deda_unified_active_id_100410.dart';
import '../lib/deda_verified_active_id_store.dart';

void main() {
  const original='@DEDA-AQPYXJ';
  const premium='@DEDA-IRAQI';
  setUp(DedaUnifiedActiveId100410.resetPublicForTest);

  test('one public source shows the premium ID, not original, in all routes', () {
    expect(DedaUnifiedActiveId100410.display(original),isNull);
    final good={
      'originalId':original,'activeId':premium,'baseColor':'gold',
      'updatedAt':'verified-fixture',
    };
    expect(DedaUnifiedActiveId100410.accept(original,good),isTrue);
    for(final section in ['profile','weekly','admin','friends','shared']){
      expect(DedaUnifiedActiveId100410.display(original),premium,
        reason:section);
    }
  });

  test('missing or malformed projection never exposes the retired ID', () {
    expect(DedaUnifiedActiveId100410.accept(original,{
      'originalId':original,'activeId':'@DEDA-FAKE!',
      'baseColor':'gold','updatedAt':'x',
    }),isFalse);
    expect(DedaUnifiedActiveId100410.display(original),isNull);
    expect(DedaUnifiedActiveId100410.accept(original,{
      'originalId':'@DEDA-DWPKYD','activeId':premium,
      'baseColor':'gold','updatedAt':'x',
    }),isFalse);
    expect(DedaUnifiedActiveId100410.display(original),isNull);
  });

  test('real server normal selection can replace previously active premium', () {
    expect(DedaUnifiedActiveId100410.accept(original,{
      'originalId':original,'activeId':premium,'baseColor':'gold',
      'updatedAt':'x',
    }),isTrue);
    expect(DedaUnifiedActiveId100410.accept(original,{
      'originalId':original,'activeId':original,'baseColor':null,
      'updatedAt':'x',
    }),isTrue);
    expect(DedaUnifiedActiveId100410.display(original),original);
  });

  test('UID proof never accepts a different account original', () {
    const cache=DedaVerifiedActiveId(
      uid:'salam-uid',originalId:original,
      displayId:premium,fixedColor:'gold',
    );
    expect(cache.wellFormed,isTrue);
    expect(cache.originalId== '@DEDA-DWPKYD',isFalse);
    expect(DedaVerifiedActiveId.fromJson({
      'uid':'hana-uid','originalId':'@DEDA-DWPKYD',
      'displayId':premium,'fixedColor':'impossible',
    }),isNull);
  });
}
