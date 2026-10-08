import 'package:d_iraq_ludo/deda_admin_task_drafts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const daily = DedaAdminTaskDraft(
    cycle: 'daily',
    action: 'open_map',
    titleAr: 'افتح الخارطة',
    titleEn: 'Open map',
    targetCount: 1,
    rewardUnit: 'points',
    rewardAmount: 5,
  );

  test('Daily draft is never published, and keeps core metadata', () {
    final values = daily.toEditableMap();
    expect(values['status'], 'draft');
    expect(values['cycle'], 'daily');
    expect(values['action'], 'open_map');
    expect(values['rewardAmount'], 5);
    expect(values['rewardUnit'], 'points');
    expect(values.keys, isNot(contains('published')));
    expect(values.keys, isNot(contains('claimable')));
    expect(values.keys, isNot(contains('userBalance')));
  });

  test('Weekly draft with diamonds can be staged but not paid out', () {
    const weekly = DedaAdminTaskDraft(
      cycle: 'weekly',
      action: 'long_trip',
      titleAr: 'أكمل رحلة أسبوعية',
      titleEn: 'Complete a weekly trip',
      targetCount: 3,
      rewardUnit: 'diamonds',
      rewardAmount: 50,
    );
    expect(weekly.toEditableMap()['status'], 'draft');
    expect(weekly.toEditableMap()['rewardAmount'], 50);
  });

  test('No unknown task event or period can be added silently', () {
    final badPeriod = DedaAdminTaskDraft(
      cycle: 'monthly',
      action: daily.action,
      titleAr: daily.titleAr,
      titleEn: daily.titleEn,
      targetCount: daily.targetCount,
      rewardUnit: daily.rewardUnit,
      rewardAmount: daily.rewardAmount,
    );
    expect(() => badPeriod.validate(), throwsArgumentError);
    const inventedAction = DedaAdminTaskDraft(
      cycle: 'daily',
      action: 'magically_verify_social_subscription',
      titleAr: 'مهمة غير مدعومة',
      titleEn: 'Unsupported task',
      targetCount: 1,
      rewardUnit: 'points',
      rewardAmount: 10,
    );
    expect(() => inventedAction.validate(), throwsArgumentError);
  });

  test('Reject zero, negative or outrageous counts and reward values', () {
    for (final reward in [-10, 0, 5001]) {
      expect(
        () => DedaAdminTaskDraft(
          cycle: 'daily',
          action: 'open_map',
          titleAr: 'افتح الخارطة',
          titleEn: 'Open map',
          targetCount: 1,
          rewardUnit: 'points',
          rewardAmount: reward,
        ).validate(),
        throwsArgumentError,
      );
    }
    for (final count in [-1, 0, 101]) {
      expect(
        () => DedaAdminTaskDraft(
          cycle: 'weekly',
          action: 'traffic_skills',
          titleAr: 'اختبر مهارتك',
          titleEn: 'Test skills',
          targetCount: count,
          rewardUnit: 'points',
          rewardAmount: 5,
        ).validate(),
        throwsArgumentError,
      );
    }
  });

  test('Telegram visit URL is only a task draft, never subscription proof', () {
    const visit = DedaAdminTaskDraft(
      cycle: 'daily',
      action: 'visit_telegram',
      titleAr: 'زور قناة ديدا',
      titleEn: 'Visit DEDA channel',
      targetCount: 1,
      rewardUnit: 'diamonds',
      rewardAmount: 50,
      url: 'https://t.me/DEDA_Iraq',
    );
    expect(visit.toEditableMap()['url'], 'https://t.me/DEDA_Iraq');
    expect(visit.toEditableMap()['status'], 'draft');
    for (final link in [
      'http://t.me/DEDA',
      'https://t.me.evil.com/DEDA',
      'https://evil.com/t.me/DEDA',
      'https://t.me/',
      'https://user@t.me/DEDA',
    ]) {
      final invalid = DedaAdminTaskDraft(
        cycle: visit.cycle,
        action: visit.action,
        titleAr: visit.titleAr,
        titleEn: visit.titleEn,
        targetCount: 1,
        rewardUnit: visit.rewardUnit,
        rewardAmount: visit.rewardAmount,
        url: link,
      );
      expect(() => invalid.validate(), throwsArgumentError, reason: link);
    }
  });

  test('Long untrusted link on unrelated task is forbidden', () {
    const invalid = DedaAdminTaskDraft(
      cycle: 'daily',
      action: 'open_map',
      titleAr: 'افتح الخارطة',
      titleEn: 'Open map',
      targetCount: 1,
      rewardUnit: 'points',
      rewardAmount: 5,
      url: 'https://t.me/channel',
    );
    expect(() => invalid.validate(), throwsArgumentError);
  });

  test('Admin-only permitted actions and reward types are fixed', () {
    expect(DedaAdminTaskDraft.actions, contains('visit_telegram'));
    expect(DedaAdminTaskDraft.actions, contains('open_map'));
    expect(DedaAdminTaskDraft.actions, isNot(contains('subscribe_verified')));
    expect(DedaAdminTaskDraft.rewards, {'points', 'diamonds'});
    expect(DedaAdminTaskDraft.cycles, {'daily', 'weekly'});
  });
}
