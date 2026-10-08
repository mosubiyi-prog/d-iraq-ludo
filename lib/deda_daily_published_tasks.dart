import 'package:cloud_firestore/cloud_firestore.dart';

import 'deda_daily_task_slots.dart';

/// Stage 5: read-only, display-only interpretation of SERVER-published tasks.
///
/// This is NOT connected to DedaDailyTasksPage or the reward engine. In
/// particular, a published rewardAmount is never evidence of an entitlement.
/// No device time is consulted here: [trustedNowUtc] must be supplied by a
/// separately reviewed time source when the UI is eventually integrated.
class DedaPublishedDailyTask {
  const DedaPublishedDailyTask._({
    required this.slotId,
    required this.action,
    required this.titleAr,
    required this.targetCount,
    required this.rewardUnit,
    required this.rewardAmount,
    required this.url,
    required this.effectiveDay,
    required this.sourcePreviewRevision,
  });

  final String slotId;
  final String action;
  final String titleAr;
  final int targetCount;
  final String rewardUnit;
  final int rewardAmount;
  final String url;
  final String effectiveDay;
  final int sourcePreviewRevision;

  /// The existing client has no verified server-side reward ledger yet.
  bool get canGrantRewards => false;

  /// Opening Telegram is NOT evidence of joining or following its channel.
  bool get isExternalVisit => action == 'visit_telegram';

  static final RegExp _telegramUrl = RegExp(
    r'^https://(?:t\.me|telegram\.me)/[A-Za-z0-9_/-]{1,180}$',
  );
  static final RegExp _dayPattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');

  static DateTime? _startUtc(String day) {
    if (!_dayPattern.hasMatch(day)) return null;
    final parsed = DateTime.tryParse('${day}T00:00:00.000Z');
    if (parsed == null ||
        '${parsed.year.toString().padLeft(4, '0')}-'
                '${parsed.month.toString().padLeft(2, '0')}-'
                '${parsed.day.toString().padLeft(2, '0')}' !=
            day) {
      return null;
    }
    return parsed.subtract(DedaIraqDay.utcOffset);
  }

  /// Fail closed on a malformed, future-dated or reward-enabled public record.
  ///
  /// [documentId] is the Firestore document ID, never a user-supplied slot.
  /// This only trusts records fetched from deda_daily_published_task_slots.
  static DedaPublishedDailyTask? parse({
    required String documentId,
    required Map<String, dynamic> data,
    required DateTime trustedNowUtc,
  }) {
    if (DedaDailyTaskSlot.byId(documentId) == null ||
        data['slotId'] != documentId ||
        data['titleAr'] is! String ||
        data['action'] is! String ||
        data['url'] is! String ||
        data['targetCount'] is! int ||
        data['rewardAmount'] is! int ||
        data['sourcePreviewRevision'] is! int ||
        data['rewardUnit'] is! String ||
        data['effectiveDay'] is! String ||
        data['effectiveAt'] is! Timestamp ||
        data['publishedAt'] is! Timestamp ||
        data['rewardsEnabled'] != false ||
        data['rewardClaimMode'] != 'disabled_until_verified_server_ledger') {
      return null;
    }
    final action = data['action'] as String;
    final titleAr = data['titleAr'] as String;
    final url = data['url'] as String;
    final targetCount = data['targetCount'] as int;
    final rewardAmount = data['rewardAmount'] as int;
    final revision = data['sourcePreviewRevision'] as int;
    final unit = data['rewardUnit'] as String;
    final day = data['effectiveDay'] as String;
    final startUtc = _startUtc(day);
    final effectiveAt = (data['effectiveAt'] as Timestamp).toDate().toUtc();

    if (startUtc == null ||
        effectiveAt != startUtc ||
        trustedNowUtc.toUtc().isBefore(startUtc) ||
        data['publicationId'] != '${day.replaceAll('-', '')}__$documentId' ||
        data['titleEn'] != titleAr ||
        titleAr != titleAr.trim() ||
        titleAr.length < 3 ||
        titleAr.length > 80 ||
        !<String>{
          ...DedaDailyTaskSlot.slots.map((slot) => slot.action),
          'visit_telegram',
        }.contains(action) ||
        targetCount < 1 ||
        targetCount > 100 ||
        rewardAmount < 1 ||
        rewardAmount > 5000 ||
        revision < 1 ||
        !<String>{'points', 'diamonds'}.contains(unit) ||
        (action == 'visit_telegram'
            ? !_telegramUrl.hasMatch(url)
            : url.isNotEmpty)) {
      return null;
    }
    return DedaPublishedDailyTask._(
      slotId: documentId,
      action: action,
      titleAr: titleAr,
      targetCount: targetCount,
      rewardUnit: unit,
      rewardAmount: rewardAmount,
      url: url,
      effectiveDay: day,
      sourcePreviewRevision: revision,
    );
  }
}

/// A single stable user-card slot. The login card remains outside this list.
class DedaDailyTaskPresentation {
  const DedaDailyTaskPresentation({
    required this.slot,
    required this.published,
  });

  final DedaDailyTaskSlot slot;
  final DedaPublishedDailyTask? published;

  String get slotId => slot.id;
  String get titleAr => published?.titleAr ?? slot.titleAr;
  String get action => published?.action ?? slot.action;
  String get subtitleAr => slot.subtitleAr;
  bool get hasPublishedOverride => published != null;
  bool get isExternalVisit => published?.isExternalVisit ?? false;
  String? get externalUrl => isExternalVisit ? published!.url : null;

  /// Deliberately never changes progress/completion or issues currency.
  bool get canGrantRewards => false;
}

class DedaDailyPublishedCatalog {
  const DedaDailyPublishedCatalog._();

  /// Always return the same eight user cards, in the same order.
  ///
  /// [lastKnownGood] is an optional in-memory cache of previously validated
  /// public records, never the manager's drafts or private schedule previews.
  /// Persistent offline storage and trusted server time are separate stages.
  static List<DedaDailyTaskPresentation> resolve({
    required Map<String, Map<String, dynamic>> publicDocuments,
    required DateTime trustedNowUtc,
    Map<String, DedaPublishedDailyTask> lastKnownGood = const {},
  }) {
    return List<DedaDailyTaskPresentation>.unmodifiable(
      DedaDailyTaskSlot.slots.map((slot) {
        final raw = publicDocuments[slot.id];
        final verified = raw == null
            ? null
            : DedaPublishedDailyTask.parse(
                documentId: slot.id,
                data: raw,
                trustedNowUtc: trustedNowUtc,
              );
        final fallback = lastKnownGood[slot.id];
        final published = verified ??
            (fallback != null &&
                    fallback.slotId == slot.id &&
                    _notFuture(fallback.effectiveDay, trustedNowUtc)
                ? fallback
                : null);
        return DedaDailyTaskPresentation(slot: slot, published: published);
      }),
    );
  }

  static bool _notFuture(String day, DateTime now) {
    final midnight = DedaPublishedDailyTask._startUtc(day);
    return midnight != null && !now.toUtc().isBefore(midnight);
  }

  /// Only validated PUBLIC overrides can enter this memory cache.
  static Map<String, DedaPublishedDailyTask> verifiedOverrides(
      List<DedaDailyTaskPresentation> cards) {
    return Map<String, DedaPublishedDailyTask>.unmodifiable({
      for (final card in cards)
        if (card.published != null) card.slotId: card.published!,
    });
  }
}

/// Unwired read adapter. No setters, no reads from admin previews or drafts.
///
/// Firestore's snapshot stream may include an offline cached public snapshot;
/// the caller must supply an appropriate trusted date when resolving it.
class DedaDailyPublishedTaskReader {
  DedaDailyPublishedTaskReader(this.firestore);

  final FirebaseFirestore firestore;

  Stream<Map<String, Map<String, dynamic>>> watchPublicDocuments() =>
      firestore.collection('deda_daily_published_task_slots').snapshots().map(
            (snapshot) => Map<String, Map<String, dynamic>>.unmodifiable({
              for (final document in snapshot.docs)
                if (DedaDailyTaskSlot.byId(document.id) != null)
                  document.id: Map<String, dynamic>.unmodifiable(
                    document.data(),
                  ),
            }),
          );
}
