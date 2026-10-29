import 'deda_weekly_leaderboard_page.dart';
import 'deda_weekly_leaderboard_policy.dart';
import 'deda_weekly_competitor_public_card.dart';

/// Server snapshot DATA contract only, not a network client or an XP authority.
///
/// Must only be used with a trusted and App-Check-guarded Cloud Function
/// response AFTER the verified backend exists and the owner approves deploy.
/// Never parse locally saved task points, fabricated standings, or Firestore
/// client-writable documents as authoritative competition results.
class DedaWeeklyServerSnapshotPair {
  const DedaWeeklyServerSnapshotPair({
    required this.current,
    required this.previous,
  });
  final DedaLeaderboardViewData current;
  final DedaLeaderboardViewData previous;

  static Map<String, dynamic> _object(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('invalid weekly data object');
    }
    return value;
  }

  static String _string(Object? value, RegExp pattern, String name) {
    if (value is! String || !pattern.hasMatch(value)) {
      throw FormatException('invalid weekly $name');
    }
    return value;
  }

  static int _whole(Object? value, String name) {
    if (value is! int || value < 0 || value > 9007199254740991) {
      throw FormatException('invalid weekly $name');
    }
    return value;
  }

  static final _participant = RegExp(r'^[A-Za-z0-9_-]{16,90}$');
  static final _activePublicId = RegExp(r'^@DEDA-[A-Z0-9]{4,12}$');
  static final _displayName = RegExp(r'^[^\x00-\x1F\x7F@]{2,60}$');

  static DedaLeaderboardViewData _week(Object? raw, String expectedStatus) {
    final json = _object(raw);
    if (json['verified'] != true ||
        json['status'] != expectedStatus ||
        json['rewardsCredited'] != false ||
        json['weekId'] is! String ||
        (json['weekId'] as String).trim().isEmpty) {
      throw const FormatException('week not verified by server');
    }

    final remainingMs = _whole(json['remainingMs'], 'remaining time');
    if (remainingMs > const Duration(days: 7).inMilliseconds ||
        (expectedStatus == 'closed' && remainingMs != 0)) {
      throw const FormatException('invalid weekly countdown');
    }

    final rawRows = json['rows'];
    if (rawRows is! List || rawRows.length > 11) {
      throw const FormatException('invalid visible participant count');
    }
    final rows = <DedaWeeklyLeaderboardRow>[];
    final profiles = <String, DedaLeaderboardProfile>{};
    final takenPlaces = <int>{};
    final takenPublicIds = <String>{};
    final takenParticipants = <String>{};

    for (final (index, source) in rawRows.indexed) {
      final info = _object(source);
      final position = _whole(info['place'], 'rank');
      if (position < 1 || position > 5000 ||
          (index < 10 && position != index + 1) ||
          (index == 10 && position <= 10) ||
          !takenPlaces.add(position)) {
        throw const FormatException('rank ordering invalid');
      }
      final participant = _string(
        info['participantId'], _participant, 'participant');
      final publicId = _string(
        info['activePublicId'], _activePublicId, 'active public ID');
      if (!takenParticipants.add(participant) ||
          !takenPublicIds.add(publicId)) {
        throw const FormatException('duplicate weekly participant');
      }

      final name = _string(
        info['displayName'], _displayName, 'display name');
      if (RegExp(r'\b0[0-9]{10}\b').hasMatch(name)) {
        throw const FormatException('private phone in display name');
      }
      final points = _whole(info['weeklyPoints'], 'level XP');
      final completed = _whole(
        info['verifiedTaskCompletions'], 'completed tasks');
      final diamonds = _whole(
        info['diamondsIfFinalWinner'], 'prize');
      // Actual approved daily tasks/traffic questions award 5 points each;
      // a login task may award 10. A completed daily quiz can itself contain
      // five independently scored questions (25 XP). Therefore a fixed
      // 20-XP-per-task derivation is incorrect for real DEDA standings.
      // Completion count and XP MUST originate from the same server-signed
      // events; this is a consistency floor, not client-side authorization.
      if (points == 0 || points % 5 != 0 ||
          completed == 0 || completed > points ~/ 5 ||
          diamonds != DedaWeeklyLeaderboardPolicy
              .diamondsForFinalPlace(position)) {
        throw const FormatException('inconsistent weekly XP or prize');
      }
      rows.add(DedaWeeklyLeaderboardRow(
        place: position,
        accountUid: participant,
        weeklyPoints: points,
        verifiedTaskCompletions: completed,
        diamondsIfFinalWinner: diamonds,
      ));
      DedaWeeklyPublicCompetitor? verifiedCompetitor;
      final appearanceRaw = info['publicAppearance'];
      if (appearanceRaw != null) {
        final appearance = _object(appearanceRaw);
        if (appearance.length != 7 ||
            appearance['publicOwnerVerified'] != true ||
            appearance['equippedAppearanceVerified'] != true ||
            appearance['activePublicId'] != publicId ||
            appearance['displayName'] != name) {
          throw const FormatException('invalid server-owned equipped appearance');
        }
        final original = _string(appearance['originalPublicId'],
            RegExp(r'^@DEDA-[A-Z0-9]{6}'), 'canonical original ID');
        if (original.length != 12) {
          throw const FormatException('canonical original ID length');
        }
        final avatar = _whole(appearance['avatarStyle'], 'avatar style');
        final frame = _whole(appearance['equippedFrameStyle'], 'equipped frame');
        if (avatar > 18 || frame > 18) {
          throw const FormatException('invalid equipped appearance styles');
        }
        final candidate = DedaWeeklyPublicCompetitor(
          participantId: participant, originalPublicId: original,
          activePublicId: publicId, displayName: name,
          rankVerified: true, publicOwnerVerified: true,
          equippedAppearanceVerified: true,
          avatarStyle: avatar, equippedFrameStyle: frame,
        );
        if (!candidate.canShowEquippedFrame) {
          throw const FormatException('equipment owner cannot be verified');
        }
        verifiedCompetitor = candidate;
      }
      profiles[participant] = DedaLeaderboardProfile(
        accountUid: participant,
        displayName: name,
        activePublicId: publicId,
        verifiedCompetitor: verifiedCompetitor,
      );
    }

    final viewerIdValue = json['viewerParticipantId'];
    final viewerId = viewerIdValue == null
        ? null
        : _string(viewerIdValue, _participant, 'viewer');
    final viewerRankValue = json['viewerPlace'];
    final viewerRank = viewerRankValue == null
        ? null
        : _whole(viewerRankValue, 'viewer rank');

    if ((viewerId == null) != (viewerRank == null) ||
        (viewerId != null &&
            (rows.where((row) =>
              row.accountUid == viewerId && row.place == viewerRank)
            .length != 1))) {
      throw const FormatException('viewer rank not in verified snapshot');
    }
    return DedaLeaderboardViewData(
      verified: true,
      rows: List.unmodifiable(rows),
      profilesByUid: Map.unmodifiable(profiles),
      viewerUid: viewerId,
      remainingUntilWeekEnd: Duration(milliseconds: remainingMs),
    );
  }

  /// Fails CLOSED if either current or previous period is unavailable.
  static DedaWeeklyServerSnapshotPair parse(Object? source) {
    final response = _object(source);
    if (response['source'] != 'future_server_issued_only' ||
        response['readOnly'] != true ||
        response.containsKey('accountKey') ||
        response.containsKey('phone') ||
        response.containsKey('authUid') ||
        response.containsKey('xpBalance') ||
        response.containsKey('diamondBalance')) {
      throw const FormatException('untrusted weekly leaderboard source');
    }
    return DedaWeeklyServerSnapshotPair(
      current: _week(response['current'], 'live'),
      previous: _week(response['previous'], 'closed'),
    );
  }
}
