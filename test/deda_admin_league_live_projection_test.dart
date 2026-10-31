import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../lib/deda_admin_league_live_data.dart';

void main() {
  final older = Timestamp.fromDate(DateTime.utc(2026, 10, 31, 4));
  final newer = Timestamp.fromDate(DateTime.utc(2026, 10, 31, 5));

  test('real weekly XP only, stable ranks and tie ordering', () {
    final list = DedaAdminLeagueProjection.fromRecords([
      MapEntry('@DEDA-AABB12', <String, dynamic>{
        'publicId':'@DEDA-AABB12', 'displayName':'محمد',
        'weeklyXp':40,'completedTasks':2,'updatedAt':newer,
      }),
      MapEntry('@DEDA-BBCC23', <String, dynamic>{
        'publicId':'@DEDA-BBCC23','displayName':'علي',
        'weeklyXp':60,'completedTasks':3,'updatedAt':newer,
      }),
      MapEntry('@DEDA-CCDD34', <String, dynamic>{
        'publicId':'@DEDA-CCDD34','displayName':'أحمد',
        'weeklyXp':40,'completedTasks':2,'updatedAt':older,
      }),
    ]);
    expect(list.length, 3);
    expect(list.map((e)=>e.publicId).toList(),
      ['@DEDA-BBCC23','@DEDA-CCDD34','@DEDA-AABB12']);
    expect(list.map((e)=>e.place).toList(), [1,2,3]);
    expect(list.map((e)=>e.xp).toList(), [60,40,40]);
  });

  test('rejects manipulated XP, incomplete IDs, duplicate scores', () {
    final rows = DedaAdminLeagueProjection.fromRecords([
      MapEntry('@DEDA-TEST11', <String, dynamic>{
        'publicId':'@DEDA-TEST11','displayName':'صالح',
        'weeklyXp':20000,'completedTasks':2,'updatedAt':older,
      }),
      MapEntry('@DEDA-TEST22', <String, dynamic>{
        'publicId':'@DEDA-TEST22','displayName':'صالح',
        'weeklyXp':20,'completedTasks':1,'updatedAt':older,
      }),
      MapEntry('@DEDA-TEST22', <String, dynamic>{
        'publicId':'@DEDA-TEST22','displayName':'صالح',
        'weeklyXp':20,'completedTasks':1,'updatedAt':older,
      }),
      MapEntry('fake-id', <String, dynamic>{
        'publicId':'fake-id','displayName':'لاعب',
        'weeklyXp':20,'completedTasks':1,'updatedAt':older,
      }),
    ]);
    expect(rows.length, 1);
    expect(rows.single.publicId, '@DEDA-TEST22');
    expect(rows.single.xp, 20);
  });

  test('live 100404 week document IDs always use Baghdad 06 calendar', () {
    expect(DedaAdminLeagueLiveData.weekId(DateTime.utc(2026, 10, 31, 3)),
        '2026-10-31');
    expect(DedaAdminLeagueLiveData.weekId(DateTime.utc(2026, 11, 7, 3)),
        '2026-11-07');
  });

  test('prizes exactly match owner approved ranks; no automatic credit', () {
    expect([for(var i=1;i<=10;i++) DedaAdminLeagueProjection.prizeForPlace(i)],
        [150,100,50,10,10,10,10,10,10,10]);
    expect(DedaAdminLeagueProjection.prizeForPlace(11),0);
  });
}
