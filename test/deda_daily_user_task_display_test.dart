import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:d_iraq_ludo/deda_daily_user_task_display.dart';
import 'package:d_iraq_ludo/deda_daily_task_slots.dart';
import 'package:flutter_test/flutter_test.dart';

final DateTime iraqMidnightUtc = DateTime.utc(2026, 10, 9, 21);
final DateTime publishedUtc = DateTime.utc(2026, 10, 9, 21, 1);

Map<String, dynamic> publicConfig(String slot, {
  Map<String, dynamic> updates = const <String, dynamic>{},
}) {
  return <String, dynamic>{
    'slotId': slot,
    'action': slot,
    'titleAr': 'المهمة المعدلة بأمان',
    'titleEn': 'المهمة المعدلة بأمان',
    'targetCount': 1,
    'rewardUnit': 'points',
    'rewardAmount': 5,
    'url': '',
    'effectiveDay': '2026-10-10',
    'effectiveAt': Timestamp.fromDate(iraqMidnightUtc),
    'sourcePreviewRevision': 1,
    'publicationId': '20261010__$slot',
    'publishedAt': Timestamp.fromDate(publishedUtc),
    'rewardsEnabled': false,
    'rewardClaimMode': 'disabled_until_verified_server_ledger',
    ...updates,
  };
}

String display({
  String slot = 'open_map',
  bool arabic = true,
  Map<String, Map<String, dynamic>> docs = const {},
}) {
  return DedaDailyUserTaskDisplay.titleForExistingCard(
    slotId: slot,
    originalTitle: 'العنوان القديم',
    isArabic: arabic,
    publicDocuments: docs,
  );
}

void main() {
  test('No published documents leaves all eight cards unchanged', () {
    for (final slot in DedaDailyTaskSlot.slots) {
      expect(display(slot: slot.id), 'العنوان القديم');
    }
    expect(DedaDailyTaskSlot.slots, hasLength(8));
    expect(DedaDailyTaskSlot.byId('daily_login'), isNull);
  });

  test('A server-published title-only change affects exactly one card', () {
    final docs = {'open_map': publicConfig('open_map')};
    expect(display(docs: docs), 'المهمة المعدلة بأمان');
    expect(display(slot: 'long_trip', docs: docs), 'العنوان القديم');
    expect(display(slot: 'share_personal_location', docs: docs),
        'العنوان القديم');
  });

  test('Non-Arabic UI preserves existing English titles', () {
    expect(display(arabic: false,
        docs: {'open_map': publicConfig('open_map')}), 'العنوان القديم');
  });

  test('Different points, diamonds, target and action cannot mislead user', () {
    for (final updates in <Map<String, dynamic>>[
      {'rewardAmount': 50},
      {'rewardUnit': 'diamonds'},
      {'rewardUnit': 'coins'},
      {'targetCount': 2},
      {'action': 'long_trip'},
      {'action': 'visit_telegram', 'url': 'https://t.me/DEDA_Iraq'},
      {'rewardsEnabled': true},
      {'rewardClaimMode': 'ready_for_rewards'},
    ]) {
      final docs = {'open_map': publicConfig('open_map', updates: updates)};
      expect(display(docs: docs), 'العنوان القديم',
          reason: 'Prevent inconsistent legacy rewards: $updates');
    }
  });

  test('Server publication proof must fall inside midnight grace window', () {
    for (final when in [
      iraqMidnightUtc.subtract(const Duration(seconds: 1)),
      iraqMidnightUtc.add(const Duration(minutes: 15)),
      iraqMidnightUtc.add(const Duration(days: 1)),
    ]) {
      expect(display(docs: {
        'open_map': publicConfig('open_map', updates: {
          'publishedAt': Timestamp.fromDate(when),
        }),
      }), 'العنوان القديم', reason: '$when');
    }
    expect(display(docs: {
      'open_map': publicConfig('open_map', updates: {
        'publishedAt': Timestamp.fromDate(iraqMidnightUtc),
      }),
    }), 'المهمة المعدلة بأمان');
  });

  test('Malformed dates and mismatched publication identifiers are rejected', () {
    for (final updates in <Map<String, dynamic>>[
      {'effectiveDay': '2026-10-11'},
      {'effectiveDay': '2026-02-30'},
      {'publicationId': '20261010__long_trip'},
      {'slotId': 'long_trip'},
      {'sourcePreviewRevision': -1},
      {'effectiveAt': Timestamp.fromDate(
        iraqMidnightUtc.add(const Duration(minutes: 5)))},
      {'titleEn': 'inconsistent title'},
    ]) {
      expect(display(docs: {
        'open_map': publicConfig('open_map', updates: updates),
      }), 'العنوان القديم', reason: '$updates');
    }
  });

  test('No manager draft or preview collection is required or referenced', () {
    const source = DedaDailyUserTaskDisplay.existingLocalTaskPoints;
    expect(source, 5);
    expect(DedaDailyUserTaskDisplay.publicationGrace.inMinutes, 15);
    expect(display(slot: 'daily_login',
        docs: {'daily_login': publicConfig('daily_login')}), 'العنوان القديم');
  });
}
