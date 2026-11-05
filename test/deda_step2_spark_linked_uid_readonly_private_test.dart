import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_step2_spark_linked_uid_readonly.dart';

const account = '9647712345678';
const uid = 'linked-original-uid';
const originalId = '@DEDA-ABC123';

String owner({
  String key = account, String ownerUid = uid,
  String? email = '$account@deda-login.invalid',
  bool anonymous = false, bool admin = false,
  Map<String,dynamic>? directory,
  Map<String,dynamic>? user,
  Map<String,dynamic>? route,
  Map<String,dynamic>? session,
}) => DedaStep2SparkLinkedUidReadOnlyProof.verify(
  accountKey:key, originalUid:ownerUid, authEmail:email,
  anonymous:anonymous, adminDocumentExists:admin,
  directory:directory ?? {
    'active':true,'accountKey':account,'createdUid':uid,
  },
  user:user ?? {'accountKey':account,'sharePersonalId':originalId},
  route:route ?? {
    'publicId':originalId,'kind':'personal','active':true,'ownerUid':uid,
  },
  session:session ?? {'uid':uid,'accountKey':account},
);

void main() {
  test('public APK default OFF: no implicit old-account recovery', () {
    expect(dedaStep2SparkLinkedUidReadOnlyEnabled,false);
  });
  test('Spark legacy old-phone link requires explicit archive before UID linking',
      () {
    void approve({
      bool spark = true,
      bool compat = true,
      bool checkpoint = true,
      bool callback = true,
    }) => DedaStep2SparkLegacyPrelinkPolicy.requireEvidenceBeforeLink(
      sparkPilotEnabled: spark,
      linkedOwnerCompatEnabled: compat,
      prelinkCheckpointEnabled: checkpoint,
      hasArchiveCallback: callback,
    );
    expect(approve, returnsNormally);
    expect(() => approve(checkpoint: false), throwsStateError);
    expect(() => approve(callback: false), throwsStateError);
    expect(() => approve(compat: false), throwsStateError);
    expect(() => approve(spark: false, compat: false,
        checkpoint: false, callback: false), returnsNormally);
  });
  test('original Firebase UID with existing session is eligible for read only',
      () {
    expect(owner(), originalId);
  });
  test('anonymous, different UID, email, account and staff are DENIED', () {
    expect(()=>owner(anonymous:true),throwsStateError);
    expect(()=>owner(ownerUid:'different-uid'),throwsStateError);
    expect(()=>owner(ownerUid:'short'),throwsStateError);
    expect(()=>owner(email:'staff@example.com'),throwsStateError);
    expect(()=>owner(key:'07712345678'),throwsStateError);
    expect(()=>owner(admin:true),throwsStateError);
  });
  test('no immutable directory, cross-account, inactive account denied', () {
    for (final row in [
      <String,dynamic>{'active':false,'accountKey':account,'createdUid':uid},
      <String,dynamic>{'active':true,'accountKey':'different','createdUid':uid},
      <String,dynamic>{'active':true,'accountKey':account,'createdUid':'wrong'},
    ]) {
      expect(()=>owner(directory:row),throwsStateError);
    }
    expect(()=>DedaStep2SparkLinkedUidReadOnlyProof.verify(
      accountKey:account,originalUid:uid,authEmail:'$account@deda-login.invalid',
      anonymous:false,directory:null,
      user:{'accountKey':account,'sharePersonalId':originalId},
      route:{'publicId':originalId,'kind':'personal','active':true,'ownerUid':uid},
      session:{'uid':uid,'accountKey':account},
      adminDocumentExists:false),throwsStateError);
  });
  test('missing, foreign or changed original ID route denied', () {
    expect(()=>owner(user:{'accountKey':account}),throwsStateError);
    expect(()=>owner(user:{'accountKey':'other','sharePersonalId':originalId}),
      throwsStateError);
    expect(()=>owner(user:{'accountKey':account,'sharePersonalId':'@DEDA-???'}),
      throwsStateError);
    expect(()=>owner(route:{
      'publicId':originalId,'kind':'personal','active':true,'ownerUid':'other',
    }),throwsStateError);
    expect(()=>owner(route:{
      'publicId':originalId,'kind':'place','active':true,'ownerUid':uid,
    }),throwsStateError);
    expect(()=>owner(route:{
      'publicId':originalId,'kind':'personal','active':false,'ownerUid':uid,
    }),throwsStateError);
  });
  test('new UID or mismatched server session cannot fabricate replacement',
      () {
    expect(()=>owner(session:{'uid':'new-device-uid','accountKey':account}),
      throwsStateError);
    expect(()=>owner(session:{'uid':uid,'accountKey':'another'}),
      throwsStateError);
    expect(()=>DedaStep2SparkLinkedUidReadOnlyProof.verify(
      accountKey:account,originalUid:uid,authEmail:'$account@deda-login.invalid',
      anonymous:false,
      directory:{'active':true,'accountKey':account,'createdUid':uid},
      user:{'accountKey':account,'sharePersonalId':originalId},
      route:{'publicId':originalId,'kind':'personal','active':true,'ownerUid':uid},
      session:null,adminDocumentExists:false),throwsStateError);
  });
}
