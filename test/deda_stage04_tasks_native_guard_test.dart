import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lib/main.dart' as app;
import '../lib/deda_stage03_lab_uid_storage_2026_11_25.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('assembled native task callbacks refuse phone-only rewards without the approved UID', () async {
    app.DedaPreferences.phone='000000000000';app.DedaPreferences.isLoggedIn=true;
    final day=app.DedaTaskEngine.currentLocalCycleId();
    final journal=jsonEncode({'version':1,'completions':{'$day|open_map':{}},'awards':{},'ledger':[]});
    SharedPreferences.setMockInitialValues({'deda_task_points_state_v1_000000000000':journal});
    expect(Firebase.apps,isEmpty);
    for(final result in [
      await app.DedaTaskEngine.recordSuccessfulEvent(app.DedaTaskEvent.mapOpened),
      await app.DedaTaskEngine.claimTaskReward('open_map'),
      await app.DedaTaskEngine.claimDailyLoginReward(),
    ]) {
      expect(result.accepted,isFalse);expect(result.pointsAwarded,isFalse);expect(result.pointsDelta,0);
    }
    expect(Firebase.apps,isEmpty);
    final prefs=await SharedPreferences.getInstance();
    expect(prefs.getString('deda_task_points_state_v1_000000000000'),journal);
    expect(prefs.getKeys(),{'deda_task_points_state_v1_000000000000'});
    app.DedaPreferences.phone='';app.DedaPreferences.isLoggedIn=false;
  },skip:!DedaStage03LabStorage.tasksLabMode);
}
