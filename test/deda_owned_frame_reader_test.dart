import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import '../lib/deda_owned_frame_reader.dart';
import '../lib/deda_lab_frame_secure_checkout.dart';

const original='@DEDA-ABC234';
class Io implements DedaOwnedFrameReadIo {
  @override Object? principal=('new-uid',1);
  String registeredUid='old-uid';int proofs=0,reads=0;
  bool deny=false;Future<void> Function()? beforeProof,beforePair;
  final receipts=<String,DedaOwnedFramePair>{};
  @override Future<String> verifyOriginalOwner(String id) async {
    proofs++;await beforeProof?.call();if(deny)throw StateError('foreign-account');
    return (principal as (String,int)).$1;
  }
  @override Future<DedaOwnedFramePair> readPair(String id,String frame) async {
    reads++;await beforePair?.call();
    return receipts[frame]??const DedaOwnedFramePair(null,null);
  }
  void own(String frame) {receipts[frame]=DedaOwnedFramePair(
    {'kind':'lab_frame','publicId':original,'frameId':frame,'cost':1000},
    {'publicId':original,'frameId':frame,'receiptId':'${original}_$frame'});}
}
DedaOwnedFrameReader reader(Io io,{Duration deadline=const Duration(seconds:12)}) =>
  DedaOwnedFrameReader(io,frameIds:DedaLabFrameSecureCheckout.paidFrameIds,deadline:deadline);
void main() {
  test('same original account on a new UID recovers all thirteen receipt-backed frames',() async {
    final io=Io();for(final id in DedaLabFrameSecureCheckout.paidFrameIds){io.own(id);}
    expect(io.registeredUid,(isNot((io.principal as (String,int)).$1)));
    expect(await reader(io).owned(original),DedaLabFrameSecureCheckout.paidFrameIds);
    expect(io.proofs,1);expect(io.reads,13);
  });
  test('successful missing receipt pairs prove empty inventory without writing',() async {
    final io=Io();expect(await reader(io).owned(original),isEmpty);expect(io.reads,13);
  });
  test('one transport failure rejects the scan instead of returning empty or partial success',() async {
    final io=Io()..own('FRAME_03');io.beforePair=() async {throw StateError('network');};
    await expectLater(reader(io).owned(original),throwsStateError);
  });
  test('an original account proof failure starts no frame reads',() async {
    final io=Io()..deny=true;await expectLater(reader(io).owned(original),throwsStateError);expect(io.reads,0);
  });
  for(final phase in ['proof','pair']) {
    for(final change in ['uid','epoch-aba']) {
      test('$phase result cannot cross $change',() async {
        final io=Io()..own('FRAME_03');Future<void> changeIdentity() async {
          io.principal=change=='uid'?('foreign-uid',2):('new-uid',3);
        }
        if(phase=='proof'){io.beforeProof=changeIdentity;}else{io.beforePair=changeIdentity;}
        await expectLater(reader(io).owned(original),throwsStateError);
      });
    }
  }
  for(final metadata in ['cache','pending']) {
    test('$metadata metadata cannot prove ownership',() async {
      final io=Io()..own('FRAME_03');final p=io.receipts['FRAME_03']!;
      io.receipts['FRAME_03']=DedaOwnedFramePair(p.receipt,p.ownership,fromCache:metadata=='cache',pendingWrites:metadata=='pending');
      await expectLater(reader(io).owned(original),throwsStateError);
      await expectLater(reader(io).isOwned(original,'FRAME_03'),throwsStateError);
    });
  }
  for(final defect in ['missing-receipt','missing-owned','price','account','frame','receipt-id']) {
    test('partial or forged $defect fails recovery visibly instead of hiding a paid item',() async {
      final io=Io()..own('FRAME_03');final p=io.receipts['FRAME_03']!;
      final r=Map<String,dynamic>.of(p.receipt!),o=Map<String,dynamic>.of(p.ownership!);
      if(defect=='price')r['cost']=1;
      if(defect=='account')r['publicId']='@DEDA-OTHER1';
      if(defect=='frame')o['frameId']='FRAME_99';
      if(defect=='receipt-id')o['receiptId']='foreign';
      io.receipts['FRAME_03']=DedaOwnedFramePair(defect=='missing-receipt'?null:r,defect=='missing-owned'?null:o);
      await expectLater(reader(io).owned(original),throwsStateError);
      await expectLater(reader(io).isOwned(original,'FRAME_03'),throwsStateError);
    });
  }
  test('an incomplete record rejects the entire scan even when another frame is verified',() async {
    final io=Io()..own('FRAME_03')..own('FRAME_05');
    final p=io.receipts['FRAME_05']!;
    io.receipts['FRAME_05']=DedaOwnedFramePair(p.receipt,null);
    await expectLater(reader(io).owned(original),throwsStateError);
    // A later explicit recovery can succeed after the server record is fixed.
    io.own('FRAME_05');
    expect(await reader(io).owned(original),{'FRAME_03','FRAME_05'});
  });
  test('approved single frame ownership and absence preserve existing results',() async {
    final io=Io()..own('FRAME_03');expect(await reader(io).isOwned(original,'FRAME_03'),isTrue);
    expect(await reader(io).isOwned(original,'FRAME_05'),isFalse);
  });
  test('permission/read timeout is bounded and a late read cannot publish a result',() async {
    final hold=Completer<void>(),io=Io()..own('FRAME_03');io.beforePair=()=>hold.future;
    await expectLater(reader(io,deadline:const Duration(milliseconds:10)).isOwned(original,'FRAME_03'),throwsA(isA<TimeoutException>()));
    io.principal=('other-uid',2);hold.complete();await Future<void>.delayed(Duration.zero);
  });
  test('invalid alias and unapproved frame cannot request ownership',() async {
    final io=Io();await expectLater(reader(io).owned('@DEDA-2020'),throwsArgumentError);
    await expectLater(reader(io).isOwned(original,'FRAME_00'),throwsArgumentError);
    expect(io.proofs,0);expect(io.reads,0);
  });
}
