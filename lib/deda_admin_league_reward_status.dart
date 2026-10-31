import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// Read-only owner audit of actual pending/received prizes in original هداياي.
/// UI does not infer a payout from prize-plan arithmetic or local XP.
class DedaAdminLeagueRewardStatus extends StatelessWidget {
  const DedaAdminLeagueRewardStatus({
    super.key, required this.isArabic, this.testGifts,
  });
  final bool isArabic;
  final Stream<List<Map<String, dynamic>>>? testGifts;

  @override
  Widget build(BuildContext context) {
    final gifts = testGifts ??
        FirebaseFirestore.instance.collection('deda_diamond_gifts')
            .where('sourceType', isEqualTo: 'weekly_league')
            .limit(100).snapshots().map((snapshot) =>
              [for (final doc in snapshot.docs) doc.data()]);
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: gifts,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Text(isArabic
              ? 'تعذر التحقق من جوائز هداياي الحقيقية.'
              : 'Unable to verify actual Hadaya gift receipts.');
        }
        if (!snapshot.hasData) return const LinearProgressIndicator();
        final verified = snapshot.data!.where((d) =>
          d['sourceType'] == 'weekly_league' &&
          d['targetPublicId'] is String &&
          d['amount'] is int &&
          d['giftId'] is String &&
          (d['status'] == 'pending' || d['status'] == 'received')).toList();
        final pending = verified.where((d) => d['status'] == 'pending').length;
        final received = verified.where((d) => d['status'] == 'received').length;
        if (verified.isEmpty) {
          return Text(isArabic
              ? 'لم تظهر جوائز أسبوعية في هداياي بعد؛ الحساب لا يعني الصرف.'
              : 'No weekly Hadaya gifts yet; prize plan is not a payout.');
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(isArabic
                ? 'جوائز هداياي المنشأة: ${verified.length}'
                : 'Created weekly Hadaya gifts: ${verified.length}'),
            Text(isArabic
                ? 'بانتظار الاستلام: $pending'
                : 'Pending owner claim: $pending'),
            Text(isArabic
                ? 'تم استلامها: $received'
                : 'Claimed: $received'),
          ],
        );
      },
    );
  }
}
