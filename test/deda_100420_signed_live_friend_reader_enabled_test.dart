import 'package:flutter_test/flutter_test.dart';
import '../lib/deda_legacy340_active_selection_100418.dart';
import '../lib/deda_unified_active_id_100410.dart';

void main() {
  const original='@DEDA-AB12CD';
  const premium='@DEDA-IRAQI';
  const normal='@DEDA-ZZABCD';
  test('Signed 100420 guard ON only after audited live read-only rules',() {
    expect(DedaLegacy340ActiveSelection100418.enabled,isTrue);
  });
  test('Friend 340 NORMAL from server confirmed missing Stage71 row',() {
    final result=DedaLegacy340ActiveSelection100418.verifiedSelection(
      original:normal,
      route:{'publicId':normal,'ownerUid':'old-client-owner',
             'kind':'personal','active':true},
      active:null,
    );
    expect(result,normal);
  });
  test('Friend 340 PREMIUM from selected server Stage71, never old ID',() {
    final result=DedaLegacy340ActiveSelection100418.verifiedSelection(
      original:original,
      route:{'publicId':original,'ownerUid':'premium-owner',
             'kind':'personal','active':true},
      active:{'originalId':original,'activeId':premium,'updatedAt':'server'},
    );
    expect(result,premium);
    expect(result,isNot(original));
  });
  test('Untrusted nonactive route does not prove original even with missing row',(){
    expect(DedaLegacy340ActiveSelection100418.verifiedSelection(
      original:original,
      route:{'publicId':original,'ownerUid':'premium-owner',
             'kind':'personal','active':false},
      active:null,
    ),isNull);
  });
  test('New unified display does not show stale cached original with no server choice',(){
    DedaUnifiedActiveId100410.resetPublicForTest();
    expect(DedaUnifiedActiveId100410.accept(original,{
      'originalId':original,'activeId':original,'baseColor':null,
      'updatedAt':'stale-normal-projection',
    }),isTrue);
    expect(DedaUnifiedActiveId100410.display(original),isNull);
  });
}
