import 'package:cloud_firestore/cloud_firestore.dart';

import 'deda_daily_published_tasks.dart';
import 'deda_daily_task_slots.dart';

/// Stage 6: compatibility gate for the EXISTING local daily-task UI.
///
/// A new title may be shown only when it describes the exact original event,
/// completion threshold and local reward (one completion, five points).
/// A future server-side ledger is required before user-visible configuration
/// changes can modify task actions, target counts or reward balances.
class DedaDailyUserTaskDisplay {
  const DedaDailyUserTaskDisplay._();

  /// Deliberately OFF in regular APK builds, including the signed-off 100319.
  /// Staging builds must opt in with:
  /// --dart-define=DEDA_DAILY_TASK_DISPLAY_PREVIEW=true
  static const bool previewEnabled = bool.fromEnvironment(
    'DEDA_DAILY_TASK_DISPLAY_PREVIEW',
    defaultValue: false,
  );

  static const int existingLocalTaskPoints = 5;
  static const Duration publicationGrace = Duration(minutes: 15);

  /// Uses only the Firestore document's trusted server publication timestamp
  /// as evidence of a past effective boundary. It is NOT a current clock,
  /// and can NEVER be used to decide completion, payouts or entitlement.
  static String titleForExistingCard({
    required String slotId,
    required String originalTitle,
    required bool isArabic,
    required Map<String, Map<String, dynamic>> publicDocuments,
  }) {
    if (!isArabic || DedaDailyTaskSlot.byId(slotId) == null) {
      return originalTitle;
    }
    final data = publicDocuments[slotId];
    if (data == null) return originalTitle;

    final publishedAt = data['publishedAt'];
    final effectiveAt = data['effectiveAt'];
    if (publishedAt is! Timestamp || effectiveAt is! Timestamp) {
      return originalTitle;
    }
    final publicationTime = publishedAt.toDate().toUtc();
    final startTime = effectiveAt.toDate().toUtc();
    if (publicationTime.isBefore(startTime) ||
        !publicationTime.isBefore(startTime.add(publicationGrace))) {
      return originalTitle;
    }

    final config = DedaPublishedDailyTask.parse(
      documentId: slotId,
      data: data,
      // The SERVER publication timestamp proves the config is not scheduled
      // in the future at the moment it is published to the public collection.
      trustedNowUtc: publicationTime,
    );
    if (config == null ||
        config.isExternalVisit ||
        config.action != slotId ||
        config.targetCount != 1 ||
        config.rewardUnit != 'points' ||
        config.rewardAmount != existingLocalTaskPoints) {
      return originalTitle;
    }
    return config.titleAr;
  }
}
