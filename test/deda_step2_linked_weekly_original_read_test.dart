import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_weekly_firestore_direct_bridge_100406.dart';

void main() {
  test('original anonymous session preserves current weekly access', () {
    expect(DedaWeeklyFirestoreDirectBridge.mayInspectOriginalWeek(
      anonymous: true, readOnlyLinked: false, linkedOwnerVerified: false),
      isTrue);
  });

  test('same verified original linked UID may VIEW existing week', () {
    expect(DedaWeeklyFirestoreDirectBridge.mayInspectOriginalWeek(
      anonymous: false, readOnlyLinked: true, linkedOwnerVerified: true),
      isTrue);
  });

  test('unverified linked, unrelated and write paths never get access', () {
    for (final linked in [true, false]) {
      expect(DedaWeeklyFirestoreDirectBridge.mayInspectOriginalWeek(
        anonymous: false, readOnlyLinked: linked,
        linkedOwnerVerified: false), isFalse);
    }
    expect(DedaWeeklyFirestoreDirectBridge.mayInspectOriginalWeek(
      anonymous: false, readOnlyLinked: false,
      linkedOwnerVerified: true), isFalse);
  });

  test('league ID remains anchored to the same existing weekly calendar', () {
    final w = DedaWeeklyFirestoreDirectBridge.week(
      DateTime.utc(2026, 11, 2, 10));
    expect(w.id, '2026-10-31');
  });
}
