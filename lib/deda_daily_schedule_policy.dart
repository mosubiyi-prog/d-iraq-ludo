import 'deda_daily_task_slots.dart';

/// Private manager scheduling policy, with Baghdad midnight as the boundary.
///
/// This policy only prepares ADMIN-ONLY previews. It never publishes tasks,
/// verifies completions or modifies a user's points, coins or diamonds.
/// A trusted server publisher must independently validate the civil day.
class DedaDailySchedulePolicy {
  static const String pending = 'pending';
  static const String cancelled = 'cancelled';

  static DateTime nextActivationUtc(DateTime now) =>
      DedaIraqDay.nextMidnightUtc(now);

  static bool canCancel({
    required String status,
    required DateTime effectiveAt,
    required DateTime trustedNow,
  }) =>
      status == pending &&
      trustedNow.toUtc().isBefore(effectiveAt.toUtc());

  static String previewId(String slotId) {
    if (DedaDailyTaskSlot.byId(slotId) == null) {
      throw ArgumentError.value(slotId, 'slotId', 'Unknown daily task slot');
    }
    return 'preview_$slotId';
  }

  static void validatePreview({
    required String slotId,
    required String status,
    required DateTime effectiveAt,
    required DateTime trustedNow,
  }) {
    previewId(slotId);
    if (status != pending && status != cancelled) {
      throw ArgumentError.value(status, 'status', 'Preview only');
    }
    if (status == pending &&
        effectiveAt.toUtc() != nextActivationUtc(trustedNow)) {
      throw ArgumentError(
          'Task preview must target the next Baghdad midnight');
    }
  }
}
