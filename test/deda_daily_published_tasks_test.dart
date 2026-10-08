import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:d_iraq_ludo/deda_daily_published_tasks.dart';
import 'package:d_iraq_ludo/deda_daily_task_slots.dart';
import 'package:flutter_test/flutter_test.dart';

final _start = DateTime.utc(2026, 10, 9, 21);
final _now = DateTime.utc(2026, 10, 9, 21, 5);

Map<String, dynamic> published(String slot, {Map<String, dynamic> changes = const {}}) {
  return <String, dynamic>{
    'slotId': slot,
    'action': slot,
    'titleAr': 'مهمة مخصصة آمنة',
    'titleEn': 'مهمة مخصصة آمنة',
    'targetCount': 1,
    'rewardUnit': 'points',
    'rewardAmount': 5,
    'url': '',
    'effectiveDay': '2026-10-10',
    'effectiveAt': Timestamp.fromDate(_start),
    'sourcePreviewRevision': 1,
    'publicationId': '20261010__$slot',
    'publishedAt': Timestamp.fromDate(_start.add(const Duration(minutes: 1))),
    'rewardsEnabled': false,
    'rewardClaimMode': 'disabled_until_verified_server_ledger',
    ...changes,
  };
}

List<DedaDailyTaskPresentation> resolve(Map<String, Map<String, dynamic>> documents,
    {DateTime? now, Map<String, DedaPublishedDailyTask> cache = const {}}) {
  return DedaDailyPublishedCatalog.resolve(
    publicDocuments: documents,
    trustedNowUtc: now ?? _now,
    lastKnownGood: cache,
  );
}

void main() {
  test('Eight stable cards remain in order; daily login is not replaceable', () {
    final cards = resolve({});
    expect(cards.map((card) => card.slotId).toList(),
        DedaDailyTaskSlot.slots.map((slot) => slot.id).toList());
    expect(cards, hasLength(8));
    expect(cards.every((card) => !card.hasPublishedOverride), isTrue);
    expect(cards.every((card) => !card.canGrantRewards), isTrue);
    expect(cards.any((card) => card.slotId == 'daily_login'), isFalse);
    expect(DedaDailyTaskSlot.regularLoginPoints, 10);
  });

  test('One valid public override replaces the presentation of one slot only', () {
    final cards = resolve({'open_map': published('open_map')});
    final map = cards.singleWhere((card) => card.slotId == 'open_map');
    expect(map.hasPublishedOverride, isTrue);
    expect(map.titleAr, 'مهمة مخصصة آمنة');
    expect(map.action, 'open_map');
    expect(map.canGrantRewards, isFalse);
    expect(cards.where((card) => card.hasPublishedOverride), hasLength(1));
    expect(cards.singleWhere((card) =>
        card.slotId == 'long_trip').titleAr, 'استفد من رحلتك الطويلة إن وجدت');
  });

  test('Published record waits for Iraq midnight even when present in a cache', () {
    final documents = {'open_map': published('open_map')};
    expect(resolve(documents, now: DateTime.utc(2026, 10, 9, 20, 59))
        .every((card) => !card.hasPublishedOverride), isTrue);
    expect(resolve(documents, now: _start)
        .singleWhere((card) => card.slotId == 'open_map')
        .hasPublishedOverride, isTrue);
  });

  test('A yesterday-published record persists until the next actual change', () {
    final cards = resolve({
      'open_map': published('open_map'),
    }, now: DateTime.utc(2026, 10, 11, 12));
    expect(cards.singleWhere((card) =>
        card.slotId == 'open_map').hasPublishedOverride, isTrue);
  });

  test('Rejects forged entitlement fields, mismatched identity and title', () {
    for (final changes in <Map<String, dynamic>>[
      {'rewardsEnabled': true},
      {'rewardClaimMode': 'automatic'},
      {'publicationId': 'spoofed'},
      {'slotId': 'daily_login'},
      {'titleEn': 'Foreign name'},
      {'titleAr': '  عنوان غير مضبوط  '},
      {'effectiveDay': '2026-10-11'},
      {'effectiveAt': Timestamp.fromDate(_start.add(const Duration(minutes: 1)))},
      {'sourcePreviewRevision': 0},
      {'rewardUnit': 'coins'},
      {'rewardAmount': 100000},
      {'targetCount': 0},
      {'action': 'arbitrary_script'},
    ]) {
      expect(DedaPublishedDailyTask.parse(
        documentId: 'open_map',
        data: published('open_map', changes: changes),
        trustedNowUtc: _now,
      ), isNull, reason: 'Rejected invalid override: $changes');
    }
    expect(DedaPublishedDailyTask.parse(
      documentId: 'daily_login',
      data: published('daily_login'),
      trustedNowUtc: _now,
    ), isNull);
  });

  test('Telegram action accepts only strict official HTTPS channel paths', () {
    const title = 'زيارة صفحة تليجرام';
    final valid = published('open_map', changes: {
      'action': 'visit_telegram',
      'titleAr': title,
      'titleEn': title,
      'url': 'https://t.me/DEDA_Iraq',
    });
    final link = resolve({'open_map': valid}).firstWhere(
        (card) => card.slotId == 'open_map');
    expect(link.isExternalVisit, isTrue);
    expect(link.externalUrl, 'https://t.me/DEDA_Iraq');
    expect(link.published!.canGrantRewards, isFalse);
    for (final url in [
      'http://t.me/DEDA_Iraq',
      'https://t.me.evil.com/DEDA_Iraq',
      'https://t.me/DEDA_Iraq?follow=true',
      'https://t.me/%2Fjoin',
      'javascript:alert(1)',
      'https://t.me/DEDA_Iraq#fragment',
    ]) {
      expect(DedaPublishedDailyTask.parse(
        documentId: 'open_map',
        data: {...valid, 'url': url},
        trustedNowUtc: _now,
      ), isNull, reason: 'Unsafe URL: $url');
    }
    expect(DedaPublishedDailyTask.parse(
      documentId: 'open_map',
      data: published('open_map', changes: {'url': 'https://t.me/DEDA_Iraq'}),
      trustedNowUtc: _now,
    ), isNull, reason: 'Non-external actions must have an empty URL');
  });

  test('Only previously validated public records can act as offline fallback', () {
    final first = resolve({'open_map': published('open_map')});
    final cache = DedaDailyPublishedCatalog.verifiedOverrides(first);
    expect(cache.keys, ['open_map']);
    final offline = resolve({}, cache: cache);
    expect(offline.singleWhere((card) =>
        card.slotId == 'open_map').titleAr, 'مهمة مخصصة آمنة');
    expect(offline.where((card) => card.hasPublishedOverride), hasLength(1));
    final beforeMidnight = resolve({}, cache: cache,
        now: DateTime.utc(2026, 10, 9, 20, 59));
    expect(beforeMidnight.every((card) => !card.hasPublishedOverride), isTrue);
  });

  test('Bad public data does not overwrite a valid previous in-memory config', () {
    final cache = DedaDailyPublishedCatalog.verifiedOverrides(
        resolve({'open_map': published('open_map')}));
    final broken = resolve({
      'open_map': published('open_map', changes: {'rewardsEnabled': true}),
    }, cache: cache);
    expect(broken.singleWhere((card) =>
        card.slotId == 'open_map').titleAr, 'مهمة مخصصة آمنة');
    expect(DedaDailyPublishedCatalog.verifiedOverrides(
        resolve({'open_map': published('open_map', changes: {'rewardsEnabled': true})})),
        isEmpty);
  });

  test('Invalid day strings cannot trick the Iraq publication boundary', () {
    for (final day in ['2026-02-30', '2026-13-01', 'wrong', '2026-10-09']) {
      expect(DedaPublishedDailyTask.parse(
        documentId: 'open_map',
        data: published('open_map', changes: {'effectiveDay': day}),
        trustedNowUtc: _now,
      ), isNull, reason: day);
    }
  });
}
