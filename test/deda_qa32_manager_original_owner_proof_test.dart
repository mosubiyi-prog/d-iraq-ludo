import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_qa32_manager_original_owner_proof.dart';

const original='@DEDA-AQPYXJ';
const uid='gm-verified-uid';

Map<String,dynamic> account([Map<String,dynamic> patch=const {}]) =>
    {'accountKey':'account-001', ...patch};
Map<String,dynamic> session([Map<String,dynamic> patch=const {}]) =>
    {'accountKey':'account-001', ...patch};
Map<String,dynamic> route([Map<String,dynamic> patch=const {}]) =>
    {'publicId':original,'ownerUid':uid,'kind':'personal','active':true,...patch};

bool verify({String id=original,String user=uid,
    Map<String,dynamic>? a,Map<String,dynamic>? s,Map<String,dynamic>? r}) =>
  DedaQa32ManagerOriginalOwnerProof.authentic(
    expectedOriginal:id,authUid:user,
    account:a??account(),session:s??session(),route:r??route(),
  );

void main(){
  test('legacy account without sharePersonalId can self-use only with route owner UID',(){
    expect(verify(),isTrue);
    expect(verify(a:account({'sharePersonalId':original})),isTrue);
    expect(verify(a:account({'sharePersonalId':'@DEDA-000000'})),isFalse);
  });
  test('fake or other UID, accountKey mismatch and missing route are rejected',(){
    expect(verify(user:'other-user'),isFalse);
    expect(verify(user:''),isFalse);
    expect(verify(r:route({'ownerUid':'another-uid'})),isFalse);
    expect(verify(r:route({'ownerUid':null})),isFalse);
    expect(verify(s:session({'accountKey':'another-account'})),isFalse);
    expect(verify(a:account({'accountKey':null})),isFalse);
    expect(verify(a:account({'accountKey':''})),isFalse);
    expect(verify(r:route({'kind':'place'})),isFalse);
    expect(verify(r:route({'active':false})),isFalse);
    expect(verify(r:route({'publicId':'@DEDA-OTHER'})),isFalse);
    expect(verify(id:'@DEDA-IRAQI'),isFalse);
  });
}
