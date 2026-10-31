import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'deda_weekly_league_clock.dart';

/// The weekly leaderboard's existing footer becomes an official notice
/// while THIS week's GM pause is confirmed from Firestore.
class DedaWeeklyMaintenanceStatus extends StatelessWidget {
  const DedaWeeklyMaintenanceStatus({super.key, required this.normal});
  final Widget normal;

  static String currentWeekId() {
    final start = DedaWeeklyLeagueClock.at(DateTime.now().toUtc())
        .weekStart.toUtc().add(const Duration(hours: 3));
    return '${start.year.toString().padLeft(4, '0')}-'
        '${start.month.toString().padLeft(2, '0')}-'
        '${start.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (Firebase.apps.isEmpty ||
        FirebaseAuth.instance.currentUser == null) return normal;
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('deda_weekly_direct_control')
          .doc('active').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const FittedBox(
            fit: BoxFit.scaleDown,
            child: Text('جارِ التحقق من حالة الدوري...',
                style: TextStyle(color: Color(0xFFAAC8EA))),
          );
        }
        final data = snapshot.data!.data();
        final paused = data?['paused'] == true &&
            data?['weekId'] == currentWeekId();
        if (!paused) return normal;
        // A pause may be for review, not necessarily planned maintenance.
        // Never broadcast the manager's full private reason.
        final reason = (data?['reason'] ?? '').toString();
        final maintenance = reason.contains('صيانة') ||
            reason.toLowerCase().contains('maintenance');
        final headline = maintenance
            ? '🛠️ الدوري تحت الصيانة • غالباً من 30 إلى 90 دقيقة'
            : '⏸️ الدوري موقوف مؤقتاً من الإدارة';
        const details = 'نقاط المستوى والماسات محفوظة';
        return Semantics(
          liveRegion: true,
          label: '$headline. $details',
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(headline, textDirection: TextDirection.rtl,
                  maxLines: 1,
                  style: const TextStyle(fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFFFD16A))),
              ),
              const Text(details, maxLines: 1,
                style: TextStyle(fontSize: 10,
                  color: Color(0xFFAAC8EA))),
            ],
          ),
        );
      },
    );
  }
}
