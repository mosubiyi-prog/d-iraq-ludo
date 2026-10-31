import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_weekly_prize_plan.dart';

void main() {
  const reason = 'زيادة جوائز المتصدرين لهذا الأسبوع';
  test('never sends an empty or short reason to Firebase', () {
    final saved = List<int>.from(DedaWeeklyPrizePlan.minimum);
    final edited = List<int>.from(saved)..[4] = 100;
    expect(DedaPrizeDraftGuard100412.validate(edited, saved, ''),
        contains('8'));
    expect(DedaPrizeDraftGuard100412.validate(edited, saved, 'قصير'),
        contains('8'));
    expect(DedaPrizeDraftGuard100412.validate(edited, saved, reason), isNull);
  });

  test('rejects no-change, decreases and unconfirmed balances locally', () {
    final saved = List<int>.from(DedaWeeklyPrizePlan.minimum);
    expect(DedaPrizeDraftGuard100412.validate(saved, saved, reason),
        contains('ارفع'));
    final lowered = List<int>.from(saved)..[0] = 149;
    expect(DedaPrizeDraftGuard100412.validate(lowered, saved, reason),
        contains('الحدود'));
    final older = List<int>.from(saved)..[4] = 100;
    expect(DedaPrizeDraftGuard100412.validate(saved, older, reason),
        contains('تخفيض'));
    expect(DedaPrizeDraftGuard100412.validate(saved, null, reason),
        contains('الخادم'));
  });

  test('specific errors do not mislabel network as missing permission', () {
    expect(DedaPrizeDraftGuard100412.errorMessage(
        StateError('league-must-be-paused-by-manager')),
        contains('موقوف'));
    expect(DedaPrizeDraftGuard100412.errorMessage(
        FirebaseException(plugin:'cloud_firestore',code:'permission-denied')),
        contains('صلاحية'));
    expect(DedaPrizeDraftGuard100412.errorMessage(
        FirebaseException(plugin:'cloud_firestore',code:'unavailable')),
        contains('الاتصال'));
  });

  test('no automatic write retry and source still validates on server', () {
    // Backend authorization and transaction logic remain unchanged.
    expect(DedaWeeklyPrizePlan.minimum.length, 10);
    expect(DedaWeeklyPrizePlan.minimum.fold(0,(a,b)=>a+b), 370);
    expect(DedaPrizeDraftGuard100412.validate(
      List<int>.from(DedaWeeklyPrizePlan.minimum)..[0]=200,
      List<int>.from(DedaWeeklyPrizePlan.minimum),reason), isNull);
  });
}
