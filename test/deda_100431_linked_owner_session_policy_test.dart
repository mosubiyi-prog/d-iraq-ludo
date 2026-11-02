import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_100431_linked_owner_session_policy.dart';

void main() {
  const original='@DEDA-ABC123', uid='source_owner_uid_1', phone='07712345678';
  Map<String,dynamic> directory() => {
    'accountKey':phone,'active':true,'createdUid':uid,
  };
  Map<String,dynamic> session() => {
    'uid':uid,'accountKey':phone,'installId':'safe-install-token',
  };
  Map<String,dynamic> projection() => {
    'accountKey':phone,'sharePersonalId':original,
  };
  Map<String,dynamic> route() => {
    'publicId':original,'kind':'personal','active':true,'ownerUid':uid,
  };
  bool check({String user=uid,String accountKey=phone,
    Map<String,dynamic>? d,Map<String,dynamic>? s,
    Map<String,dynamic>? p,Map<String,dynamic>? r}) =>
      DedaLinkedOwnerSessionPolicy.ownerDocumentsMatch(
        uid:user,accountKey:accountKey,
        directory:d??directory(),session:s??session(),
        projection:p??projection(),route:r??route(),
      );
  test('Recovery linked-user compatibility remains OFF by default',(){
    expect(dedaLinkedOwnerCompatEnabled,false);
  });
  test('Only exact synthetic DEDA owner email matches, not real admin email',(){
    expect(DedaLinkedOwnerSessionPolicy.emailMatches(
      '$phone@deda-login.invalid',phone),true);
    expect(DedaLinkedOwnerSessionPolicy.emailMatches(
      'staff@gmail.com',phone),false);
    expect(DedaLinkedOwnerSessionPolicy.emailMatches(
      '07799999999@deda-login.invalid',phone),false);
    expect(DedaLinkedOwnerSessionPolicy.emailMatches(
      '$phone@deda-login.invalid',''),false);
  });
  test('verified new-phone boot permits ONLY original UID + exact account + password email',(){
    const linkedAccount = '9647712345678';
    const originalUid = 'original_firebase_owner_uid';
    const email = '$linkedAccount@deda-login.invalid';
    bool resume({
      String? uid = originalUid,
      String? account = linkedAccount,
      String phone = '+9647712345678',
      String? liveUid = originalUid,
      String? liveEmail = email,
      bool anonymous = false,
    }) => DedaLinkedOwnerSessionPolicy.mayResumeLinkedLocalLogin(
      savedOriginalUid:uid,savedAccountKey:account,
      localPhone:phone,currentUid:liveUid,currentEmail:liveEmail,
      currentIsAnonymous:anonymous,
    );
    expect(resume(),true);
    expect(resume(liveUid:'new-device-anonymous'),false);
    expect(resume(liveUid:null),false);
    expect(resume(anonymous:true),false);
    expect(resume(liveEmail:'administrator@deda-login.invalid'),false);
    expect(resume(liveEmail:null),false);
    expect(resume(account:'9647000000000'),false);
    expect(resume(phone:'+9647900000000'),false);
    expect(resume(uid:null),false);
    expect(resume(uid:''),false);
    expect(resume(account:null),false);
    expect(resume(account:''),false);
  });

  test('All original owner, old UID, personal ID and account documents match',(){
    expect(check(),true);
  });
  test('A cloned new UID with another device cannot inherit owner entitlement',(){
    expect(check(user:'new_anonymous_uid'),false);
  });
  test('A premium display ID is never canonical personal account route',(){
    expect(check(p:{...projection(),'sharePersonalId':'@DEDA-KING99'}),false);
    expect(check(r:{...route(),'publicId':'@DEDA-KING99'}),false);
  });
  test('Original owner route must remain active and contain exact UID',(){
    expect(check(r:{...route(),'active':false}),false);
    expect(check(r:{...route(),'ownerUid':'another_uid'}),false);
    expect(check(r:{...route(),'kind':'place'}),false);
  });
  test('Directory original UID and session account cannot be changed',(){
    expect(check(d:{...directory(),'createdUid':'another_uid'}),false);
    expect(check(s:{...session(),'accountKey':'07799999999'}),false);
    expect(check(d:{...directory(),'active':false}),false);
  });
  test('Changed profile source account and absent original ID fail closed',(){
    expect(check(p:{...projection(),'accountKey':'07799999999'}),false);
    expect(check(p:{'accountKey':phone}),false);
  });
  test('No account owner authority can be inferred from missing records',(){
    expect(DedaLinkedOwnerSessionPolicy.ownerDocumentsMatch(
      uid:uid,accountKey:phone,directory:null,session:session(),
      projection:projection(),route:route()),false);
    expect(DedaLinkedOwnerSessionPolicy.ownerDocumentsMatch(
      uid:uid,accountKey:phone,directory:directory(),session:null,
      projection:projection(),route:route()),false);
    expect(DedaLinkedOwnerSessionPolicy.ownerDocumentsMatch(
      uid:uid,accountKey:phone,directory:directory(),session:session(),
      projection:projection(),route:null),false);
  });
}
