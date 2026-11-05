import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_step2_historical_quiz_source_audit.dart';

const account='07712345678',other='07799998888',original='@DEDA-ABC123';
String dayKey(String kind,String id,String day) =>
  'deda_traffic_quiz_' + kind + '_v1_' + id + '_' + day;
String seenKey(String id) => 'deda_traffic_quiz_seen_v1_' + id;

class FakeHistory implements DedaStep2HistoricalQuizLocalIo {
  FakeHistory(this.records,{this.onSecondRead});
  final Map<String,Object?> records;
  final void Function()? onSecondRead;
  int counts=0,reads=0;
  List<String> inspected=[];
  @override
  Future<Set<String>> existingKeys() async {
    counts++;return records.keys.toSet();
  }
  @override
  Future<Map<String,Object?>> readKeys(List<String> keys) async {
    reads++;
    inspected.addAll(keys);
    if (reads == 2) onSecondRead?.call();
    return {for(final key in keys) key:records[key]};
  }
}
Future<DedaStep2HistoricalQuizEvidence> inspect(FakeHistory f,
  {bool Function()? current}) =>
  DedaStep2HistoricalQuizSourceAudit(f).inspectOriginalPhone(
    accountKey:account,originalId:original,
    isCurrent:current??()=>true);

void main() {
  test('old quiz days and seen history read exactly for canonical account',() async {
    final f=FakeHistory({
      seenKey(account):['Q1','Q2'],
      dayKey('daily_ids',account,'2026-10-31'):['Q1','Q2','Q3','Q4','Q5'],
      dayKey('progress',account,'2026-10-31'):'{"correct":4}',
      dayKey('completed',account,'2026-10-31'):true,
      dayKey('daily_ids',account,'2026-11-01'):['Q6','Q7','Q8','Q9','Q10'],
      dayKey('completed',account,'2026-11-01'):false,
      seenKey(other):['OTHER'],
      dayKey('completed',other,'2026-10-31'):true,
      'unrelated_key':'unchanged',
    });
    final out=await inspect(f);
    expect(out.recordedDays,containsAll(['2026-10-31','2026-11-01']));
    expect(out.recordedDays.length,2);
    expect(out.anyHistoricalDay,true);
    expect(out.hasIncompleteDays,true);
    expect(out.containsMalformedValues,false);
    expect(out.rawByKey.keys,contains(seenKey(account)));
    expect(out.rawByKey.keys,isNot(contains(seenKey(other))));
    expect(f.inspected,isNot(contains(seenKey(other))));
    expect(out.canRestoreClaimedQuizRewards,false);
    expect(out.canAwardXpOrDiamonds,false);
    expect(out.canReplaceTheCurrentPhoneState,false);
    expect(out.fullAccountRestored,false);
    expect(f.counts,2);
    expect(f.reads,2);
  });
  test('missing days is UNKNOWN, not proof that user never completed quiz',() async {
    final out=await inspect(FakeHistory({}));
    expect(out.recordedDays,isEmpty);
    expect(out.canInferMissingDaysWereNotPlayed,false);
  });
  test('wrong native completed flag stays marked malformed without rewriting',() async {
    final f=FakeHistory({
      dayKey('completed',account,'2026-10-31'):'true',
      dayKey('progress',account,'2026-10-31'):'{corrupt-json',
    });
    final out=await inspect(f);
    expect(out.containsMalformedValues,true);
    expect(out.rawByKey[dayKey('completed',account,'2026-10-31')],'true');
    expect(f.records[dayKey('completed',account,'2026-10-31')],'true');
  });
  test('invalid account, premium alias or malformed day must not be read',() async {
    final f=FakeHistory({
      dayKey('completed',account,'2026-02-31'):true,
    });
    await expectLater(inspect(f),
        throwsA(isA<DedaStep2HistoricalQuizHold>()));
    expect(f.reads,0);
    final bad=DedaStep2HistoricalQuizSourceAudit(FakeHistory({}));
    await expectLater(bad.inspectOriginalPhone(
      accountKey:'invalid',originalId:original,isCurrent:()=>true),
      throwsA(isA<DedaStep2HistoricalQuizHold>()));
  });
  test('switched account/session halfway through read halts safely',() async {
    var current=true;
    final f=FakeHistory({seenKey(account):['Q1']},
      onSecondRead:(){current=false;});
    await expectLater(inspect(f,current:()=>current),
      throwsA(isA<DedaStep2HistoricalQuizHold>()));
  });
  test('changed quiz evidence during two local reads is not accepted',() async {
    final key=dayKey('progress',account,'2026-10-31');
    final source=<String,Object?>{key:'{"old":1}'};
    final f=FakeHistory(source,onSecondRead:(){
      source[key]='{"new":1}';
    });
    await expectLater(inspect(f),
      throwsA(isA<DedaStep2HistoricalQuizHold>()));
    expect(source[key],'{"new":1}');
  });
  test('mutating a string-list in place between reads is detected',() async {
    final seen=['Q1'];
    final f=FakeHistory({seenKey(account):seen},onSecondRead:(){
      seen.add('Q2');
    });
    await expectLater(inspect(f),
      throwsA(isA<DedaStep2HistoricalQuizHold>()));
  });
  test('freeze lists and maps; archive can never rewrite original quiz',() async {
    final seen=['Q1'];
    final f=FakeHistory({seenKey(account):seen});
    final out=await inspect(f);
    seen.add('Q2');
    expect(out.rawByKey[seenKey(account)],['Q1']);
    expect(()=>out.rawByKey[seenKey(account)]=[],throwsUnsupportedError);
    expect(()=>out.recordedDays.add('2026-11-05'),throwsUnsupportedError);
  });
}
