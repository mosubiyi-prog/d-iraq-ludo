import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_qa32_admin_gift_recipient_alias_bridge.dart';
import 'package:d_iraq_ludo/deda_gift_recipient_preview.dart';

void main() {
  const original='@DEDA-AQPYXJ', premium='@DEDA-IRAQI';
  test('prod-off flags protect real gem wallet and gift routing until approved', () {
    expect(DedaQa32AdminGiftRecipientAliasBridge.enabled, isFalse);
  });
  test('verify alias maps exactly to original 6 char recipient; never UID', () {
    final proof=<String,dynamic>{
      'requestedId':premium,'originalId':original,'serverConfirmed':true};
    expect(DedaQa32AdminGiftRecipientAliasBridge.verifiedOriginalFromReply(
      proof,premium), original);
    expect(DedaQa32AdminGiftRecipientAliasBridge.verifiedOriginalFromReply(
      {...proof,'serverConfirmed':false,'originalId':null},premium),null);
    expect(()=>DedaQa32AdminGiftRecipientAliasBridge.verifiedOriginalFromReply(
      {...proof,'ownerUid':'forged'},premium),throwsStateError);
    expect(()=>DedaQa32AdminGiftRecipientAliasBridge.verifiedOriginalFromReply(
      {...proof,'requestedId':'@DEDA-STOLEN'},premium),throwsStateError);
    expect(()=>DedaQa32AdminGiftRecipientAliasBridge.verifiedOriginalFromReply(
      {...proof,'originalId':'@DEDA-OTHER'},premium),throwsStateError);
    expect(()=>DedaQa32AdminGiftRecipientAliasBridge.verifiedOriginalFromReply(
      {...proof,'serverConfirmed':false},premium),throwsStateError);
  });
  testWidgets('confirmed GM target displays active alias, retains original transfer ID',
      (tester) async {
    final profile=<String,dynamic>{
      'publicId':original,'activeDisplayId':premium,
      'displayName':'سالم حسن','level':1,'avatarStyle':0,'frameStyle':3};
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:
      DedaGiftRecipientPreview(profile:profile,isArabic:true))));
    expect(find.text('سالم حسن'), findsOneWidget);
    expect(find.text(premium), findsOneWidget);
    expect(find.text(original), findsNothing);
    expect(profile['publicId'],original,
      reason:'The grant transaction must still target canonical original');
    expect(tester.takeException(),isNull);
  });
}
