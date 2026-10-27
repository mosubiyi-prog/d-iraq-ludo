import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// PRIVATE QA ONLY: local evidence from actual task claims and independently
/// persisted +20 LEVEL XP. NOT server authorized, no other users, no payouts.
class DedaWeeklyPrivateTrialLocalXp {
  const DedaWeeklyPrivateTrialLocalXp._();
  static DateTime iraqDay(DateTime instant) =>
      instant.toUtc().add(const Duration(hours: 3));
  static String dayKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// Monday Iraq 00:00 is TEMPORARY QA, not final owner production calendar.
  static String testWeekKey(DateTime instant) {
    final today=iraqDay(instant);
    final monday=DateTime.utc(today.year,today.month,today.day)
        .subtract(Duration(days:today.weekday-DateTime.monday));
    return dayKey(monday);
  }

  static int countIntersection({
    required String weekKey,
    required Object? taskLedgerJson,
    required Object? socialWalletJson,
  }) {
    if (!RegExp(r'^\d{4}-\d\d-\d\d$').hasMatch(weekKey)) return 0;
    Map<String,dynamic> tasks,wallet;
    try {
      tasks=Map<String,dynamic>.from(jsonDecode(taskLedgerJson as String) as Map);
      wallet=Map<String,dynamic>.from(jsonDecode(socialWalletJson as String) as Map);
    } catch (_) {return 0;}
    final rawClaims=wallet['taskClaims'];
    final rawAwards=tasks['awards'];
    final lifetimeXp=wallet['xp'];
    if (rawClaims is! List || rawAwards is! Map ||
        lifetimeXp is! int || lifetimeXp<0) return 0;
    final receipts=<String>{};
    for (final item in rawClaims) {
      if (item is! String || !RegExp(r'^\d{4}-\d\d-\d\d\|[a-zA-Z0-9_]+$')
          .hasMatch(item)) continue;
      final cycle=item.substring(0,10);
      final end=DateTime.tryParse(cycle);
      final start=DateTime.tryParse(weekKey);
      if(end==null||start==null||end.isBefore(start)||
          !end.isBefore(start.add(const Duration(days:7))))continue;
      final source=rawAwards['task|$item'];
      if (source is! Map || source['id']!='task|$item' ||
          source['type']!='task' || source['points']!=5 ||
          source['cycleId']!=cycle ||
          source['taskId']!=item.substring(11))continue;
      receipts.add(item);
    }
    return (receipts.length*20).clamp(0,lifetimeXp).toInt();
  }

  static Future<int?> read(String canonicalAccountKey,
      {DateTime? instant}) async {
    if (!RegExp(r'^\d{10,16}$').hasMatch(canonicalAccountKey))return null;
    final prefs=await SharedPreferences.getInstance();
    final task=prefs.getString(
        'deda_task_points_state_v1_$canonicalAccountKey');
    final xp=prefs.getString(
        'deda_social_progress_v1_$canonicalAccountKey');
    if(task==null||xp==null)return 0;
    return countIntersection(
      weekKey:testWeekKey(instant??DateTime.now()),
      taskLedgerJson:task,socialWalletJson:xp);
  }
}
