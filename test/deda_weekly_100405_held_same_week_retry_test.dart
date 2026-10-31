import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:d_iraq_ludo/deda_weekly_community_outbox.dart';

const account='07701234567';
const uid='anonymousDedaAccountA00001';
final sat=DateTime.utc(2026,10,31,20,55); // Sat 23:55 Baghdad
final sun=DateTime.utc(2026,10,31,21,5); // Sun 00:05 Baghdad
final friday=DateTime.utc(2026,11,6,20,55); // Fri 23:55 Baghdad
final frozen=DateTime.utc(2026,11,6,21,5); // Sat 00:05 Baghdad
final nextSat=DateTime.utc(2026,11,7,3,5); // Sat 06:05 Baghdad

void main() {
  setUp(()=>SharedPreferences.setMockInitialValues({}));

  test('GM review across midnight does not lose previously earned level XP signal',() async {
    final sent=<String>[];
    expect(await DedaWeeklyCommunityOutbox.recordAndSend(
      accountKey:account,uid:uid,taskId:'open_map',now:sat,
      send:(_,__)async=>false,
    ),false);
    expect(DedaWeeklyCommunityOutbox.dayAllowedInCurrentWeek('2026-10-31',sun),
      isTrue);
    final recovered=await DedaWeeklyCommunityOutbox.retry(
      accountKey:account,uid:uid,now:sun,limit:8,
      send:(task,day)async{
        sent.add('$day|$task');
        return true;
      });
    expect(recovered,1);
    expect(sent,['2026-10-31|open_map']);
  });

  test('hold across many days remains in same week, but NEVER into next week',() async {
    await DedaWeeklyCommunityOutbox.recordAndSend(
      accountKey:account,uid:uid,taskId:'share_personal_location',now:sat,
      send:(_,__)async=>false,
    );
    final accepted=<String>[];
    expect(await DedaWeeklyCommunityOutbox.retry(
      accountKey:account,uid:uid,now:friday,limit:8,
      send:(task,day)async{accepted.add(day);return true;},
    ),1);
    expect(accepted,['2026-10-31']);
    expect(DedaWeeklyCommunityOutbox.dayAllowedInCurrentWeek('2026-10-31',frozen),
      isFalse);
    expect(DedaWeeklyCommunityOutbox.dayAllowedInCurrentWeek('2026-10-31',nextSat),
      isFalse);
    expect(DedaWeeklyCommunityOutbox.dayAllowedInCurrentWeek('2026-11-07',nextSat),
      isTrue);
  });

  test('frozen last Saturday midnight-6 and prestart NEVER sends',() async {
    expect(DedaWeeklyCommunityOutbox.dayAllowedInCurrentWeek('2026-10-31',
       DateTime.utc(2026,10,31,2,59)),isFalse);
    expect(DedaWeeklyCommunityOutbox.dayAllowedInCurrentWeek('2026-11-06',
       frozen),isFalse);
    await DedaWeeklyCommunityOutbox.recordAndSend(
      accountKey:account,uid:uid,taskId:'open_map',now:sat,
      send:(_,__)async=>false,
    );
    var count=0;
    expect(await DedaWeeklyCommunityOutbox.retry(
      accountKey:account,uid:uid,now:frozen,
      send:(_,__)async{count++;return true;},
    ),0);
    expect(count,0);
  });

  test('UID and account isolation for review queue remains mandatory',() async {
    await DedaWeeklyCommunityOutbox.recordAndSend(
      accountKey:account,uid:uid,taskId:'open_map',now:sat,
      send:(_,__)async=>false,
    );
    final o=await DedaWeeklyCommunityOutbox.retry(
      accountKey:'07707654321',uid:uid,now:sun,
      send:(_,__)async=>true,
    );
    expect(o,0);
  });
}
