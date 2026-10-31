import 'package:flutter_test/flutter_test.dart';
import '../lib/deda_legacy340_active_selection_100418.dart';

void main() {
  const original='@DEDA-AB12CD';
  const premium='@DEDA-IRAQI';
  final route=<String,dynamic>{
    'publicId':original,'ownerUid':'uid-340',
    'kind':'personal','active':true,
  };

  test('old Play 340 with NO Stage71 means NORMAL only with verified route',() {
    expect(DedaLegacy340ActiveSelection100418.verifiedSelection(
      original:original,route:route,active:null),original);
    expect(DedaLegacy340ActiveSelection100418.verifiedSelection(
      original:original,route:null,active:null),isNull);
    expect(DedaLegacy340ActiveSelection100418.verifiedSelection(
      original:original,route:{...route,'active':false},active:null),isNull);
  });
  test('old Play 340 premium keeps CURRENT alias even when projection missing',(){
    expect(DedaLegacy340ActiveSelection100418.verifiedSelection(
      original:original,route:route,active:{
        'originalId':original,'activeId':premium,'updatedAt':'server-value'
      }),premium);
  });
  test('wrong original, malformed premium, private extra field fail closed',(){
    for(final active in <Map<String,dynamic>>[
      {'originalId':'@DEDA-DIFFER','activeId':premium,'updatedAt':1},
      {'originalId':original,'activeId':'@DEDA-HACK!','updatedAt':1},
      {'originalId':original,'activeId':premium,'updatedAt':1,
       'privateGrant':'never-expose'},
      {'originalId':original,'activeId':premium,'updatedAt':null},
    ]) {
      expect(DedaLegacy340ActiveSelection100418.verifiedSelection(
        original:original,route:route,active:active),isNull);
    }
  });
  test('read flag OFF by default until owner approves production rule change',(){
    expect(DedaLegacy340ActiveSelection100418.enabled,isFalse);
  });
}
