import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'deda_weekly_leaderboard_policy.dart';
import 'deda_weekly_competitor_public_card.dart';
import 'deda_weekly_leaderboard_tap_surface.dart';

/// Display-only verified leaderboard identity.
//// Users and scores must come from the approved server, never test/mock data.
/// This intentionally cannot read, create or transfer XP and diamonds.
class DedaLeaderboardProfile {
  const DedaLeaderboardProfile({
    required this.accountUid,
    required this.displayName,
    required this.activePublicId,
    this.avatarImage,
    this.verifiedCompetitor,
  });

  final String accountUid;
  final String displayName;
  final String activePublicId;
  final ImageProvider? avatarImage;
  /// Only a validated server-owned public equipment proof, never local viewer style.
  final DedaWeeklyPublicCompetitor? verifiedCompetitor;
}

/// Server-supplied standings and privacy-filtered account profile data.
/// Unconfirmed results MUST NOT be presented as live winners.
class DedaLeaderboardViewData {
  const DedaLeaderboardViewData({
    required this.verified,
    required this.rows,
    required this.profilesByUid,
    this.viewerUid,
    this.remainingUntilWeekEnd,
  });
  final bool verified;
  final List<DedaWeeklyLeaderboardRow> rows;
  final Map<String, DedaLeaderboardProfile> profilesByUid;
  final String? viewerUid;
  final Duration? remainingUntilWeekEnd;

  DedaWeeklyLeaderboardRow? get viewerRow {
    final uid = viewerUid;
    if (!verified || uid == null) return null;
    for (final row in rows) {
      if (row.accountUid == uid) return row;
    }
    return null;
  }
}

/// Fixed one-viewport rendition of the owner's reference image.
/// NO ListView, SingleChildScrollView, GridView, or scroll controller.
/// Maintains current/previous tabs, top-three podium, seven compact ranks,
/// viewer rank, and disclaimer. Empty data is explicitly shown as pending.
class DedaWeeklyLeaderboardPage extends StatefulWidget {
  const DedaWeeklyLeaderboardPage({
    super.key,
    this.previewOnly = false,
    this.current = const DedaLeaderboardViewData(
      verified: false,
      rows: [],
      profilesByUid: {},
    ),
    this.onOpenDailyTasks,
    this.onOpenExistingPublicProfile,
    this.onSendExistingFriendRequest,
    this.friendRelationFor,
    this.drawOriginalEquippedAvatar,
    this.previous = const DedaLeaderboardViewData(
      verified: false,
      rows: [],
      profilesByUid: {},
    ),
  });

  /// Only for an entirely separate UI-only preview APK; never score real users.
  final bool previewOnly;
  final DedaLeaderboardViewData current;
  final DedaLeaderboardViewData previous;

  /// Navigate to the EXISTING official daily tasks page; a navigation-only
  /// action. This must not claim XP, modify a task or grant any diamonds.
  /// The original home screen supplies this callback in both layouts.
  final VoidCallback? onOpenDailyTasks;

  /// Connected only by authenticated original DEDA profile/social coordinator.
  final Future<void> Function(DedaWeeklyPublicCompetitor)?
      onOpenExistingPublicProfile;
  final Future<void> Function(DedaWeeklyPublicCompetitor)?
      onSendExistingFriendRequest;
  final DedaWeeklyFriendRelation Function(DedaWeeklyPublicCompetitor)?
      friendRelationFor;
  final Widget Function(BuildContext,int,int,double)?
      drawOriginalEquippedAvatar;

  @override
  State<DedaWeeklyLeaderboardPage> createState() =>
      _DedaWeeklyLeaderboardPageState();
}

class _DedaWeeklyLeaderboardPageState
    extends State<DedaWeeklyLeaderboardPage> {
  bool previousWeek = false;

  static const navy = Color(0xFF051B35);
  static const blue = Color(0xFF0E3964);
  static const gold = Color(0xFFFFCC53);
  static const pale = Color(0xFFF7E7C0);
  static const silver = Color(0xFFAAC8EA);
  static const bronze = Color(0xFFF5A96F);

  DedaLeaderboardViewData get view =>
      previousWeek ? widget.previous : widget.current;

  static Widget fitted(
    String value, {
    double size = 14,
    Color color = Colors.white,
    FontWeight weight = FontWeight.w700,
    TextAlign align = TextAlign.center,
    bool ltr = false,
  }) =>
      FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          value,
          maxLines: 1,
          textAlign: align,
          textDirection: ltr ? TextDirection.ltr : TextDirection.rtl,
          style: TextStyle(
            color: color,
            fontSize: size,
            fontWeight: weight,
            height: 1.12,
          ),
        ),
      );

  DedaWeeklyLeaderboardRow? rowAt(int position) {
    if (!view.verified) return null;
    for (final row in view.rows) {
      if (row.place == position) return row;
    }
    return null;
  }

  DedaLeaderboardProfile? profile(DedaWeeklyLeaderboardRow? row) {
    if (row == null) return null;
    return view.profilesByUid[row.accountUid];
  }

  Widget identity(DedaWeeklyLeaderboardRow? row,
      {double avatarSize = 33, bool compact = false,
       bool interactive = true}) {
    final details = profile(row);
    final player = details?.verifiedCompetitor;
    final original = Row(
      mainAxisSize: MainAxisSize.min,
      textDirection: TextDirection.rtl,
      children: [
        Container(
          height: avatarSize,
          width: avatarSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(colors: [gold, Color(0xFFA9701C), gold]),
            boxShadow: [BoxShadow(color: gold.withValues(alpha: .25),
                blurRadius: avatarSize * .25)],
          ),
          padding: EdgeInsets.all(math.max(1.5, avatarSize * .065)),
          child: player != null && player.canShowEquippedFrame &&
                  widget.drawOriginalEquippedAvatar != null
              ? widget.drawOriginalEquippedAvatar!(
                  context, player.avatarStyle!, player.equippedFrameStyle!,
                  avatarSize)
              : CircleAvatar(
                  backgroundColor: blue,
                  backgroundImage: details?.avatarImage,
                  child: details?.avatarImage == null
                      ? Icon(Icons.person, size: avatarSize * .6, color: pale)
                      : null,
                ),
        ),
        SizedBox(width: compact ? 4 : 7),
        Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: fitted(
                  details?.displayName ?? (row == null ? '—' : 'مستخدم DEDA'),
                  size: compact ? 12 : 16,
                ),
              ),
              if (!compact)
                Expanded(
                  child: fitted(details?.activePublicId ?? '—',
                      size: 11, color: silver, weight: FontWeight.w500,
                      ltr: true),
                ),
            ],
          ),
        ),
      ],
    );
    if (!interactive) return original;
    return rankTapSurface(row?.place, original);
  }

  /// ONE consistent hit target for a rank: the entire podium or row.
  /// Missing verified identity and authenticated actions stay non-clickable.
  /// Never infer a Firebase UID from an opaque participant identifier.
  Widget rankTapSurface(int? place, Widget child) {
    final score = place == null ? null : rowAt(place);
    final player = profile(score)?.verifiedCompetitor;
    return DedaWeeklyLeaderboardTapSurface(
      surfaceKey: place == null ? null :
          ValueKey<String>('deda_weekly_rank_${place}_tap'),
      competitor: player,
      viewerParticipantId: view.viewerUid,
      friendRelation: player == null
          ? DedaWeeklyFriendRelation.unknown
          : widget.friendRelationFor?.call(player) ??
              DedaWeeklyFriendRelation.unknown,
      onOpenExistingPublicProfile: widget.onOpenExistingPublicProfile,
      onSendExistingFriendRequest: widget.onSendExistingFriendRequest,
      child: child,
    );
  }

  BoxDecoration panel(
    Color start, {
    Color? end,
    double radius = 18,
    Color outline = const Color(0xAA3C76A3),
  }) =>
      BoxDecoration(
        gradient: LinearGradient(
          colors: [start, end ?? navy],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: outline, width: 1),
      );

  Widget pill(String text, Color fill, Color ink) => Container(
        constraints: const BoxConstraints(minWidth: 2),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(28),
        ),
        child: fitted(text, size: 14, color: ink),
      );

  String prize(int position) =>
      '${DedaWeeklyLeaderboardPolicy.diamondsForFinalPlace(position)} ماسة';

  Widget podium(int place, double scale) {
    final row = rowAt(place);
    final isFirst = place == 1;
    final accent = isFirst ? gold : (place == 2 ? silver : bronze);
    final name = profile(row)?.displayName ?? '—';
    final player = profile(row)?.verifiedCompetitor;
    return Expanded(
      child: rankTapSurface(place, Padding(
        padding: EdgeInsets.only(
          left: 3 * scale,
          right: 3 * scale,
          top: isFirst ? 0 : 18 * scale,
        ),
        child: Column(
          children: [
            Expanded(
              flex: isFirst ? 12 : 11,
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: double.infinity,
                    margin: EdgeInsets.only(top: 7 * scale),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(colors: [
                        accent.withValues(alpha: .45),
                        accent.withValues(alpha: .10),
                        Colors.transparent,
                      ]),
                    ),
                  ),
                  if (isFirst)
                    Positioned.fill(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('❧', style: TextStyle(
                            color: gold.withValues(alpha: .70),
                            fontSize: 35 * scale)),
                          Text('❧', textDirection: TextDirection.rtl,
                            style: TextStyle(
                              color: gold.withValues(alpha: .70),
                              fontSize: 35 * scale)),
                        ],
                      ),
                    ),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(isFirst ? '👑' : place == 2 ? '♛' : '♕',
                          style: TextStyle(
                            fontSize: (isFirst ? 27 : 25) * scale,
                            color: accent, height: 1)),
                      Container(
                        width: (isFirst ? 72 : 65) * scale,
                        height: (isFirst ? 72 : 65) * scale,
                        padding: EdgeInsets.all(3 * scale),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(colors: [
                            accent, accent.withValues(alpha: .55), accent]),
                          boxShadow: [BoxShadow(
                            color: accent.withValues(alpha: .50),
                            blurRadius: 13 * scale)],
                        ),
                        child: player != null && player.canShowEquippedFrame &&
                                widget.drawOriginalEquippedAvatar != null
                            ? widget.drawOriginalEquippedAvatar!(
                                context, player.avatarStyle!,
                                player.equippedFrameStyle!,
                                (isFirst ? 72 : 65) * scale)
                            : CircleAvatar(
                                backgroundColor: blue,
                                backgroundImage: profile(row)?.avatarImage,
                                child: profile(row)?.avatarImage == null
                                    ? Icon(Icons.person, color: pale,
                                        size: 34 * scale)
                                    : null,
                              ),
                      ),
                    ],
                  ),
                  Positioned(
                    bottom: 0,
                    child: Container(
                      padding: EdgeInsets.symmetric(
                          horizontal: 10 * scale, vertical: 2 * scale),
                      decoration: BoxDecoration(
                        color: accent,
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: Text('$place',
                          style: TextStyle(
                              color: navy,
                              fontSize: 20 * scale,
                              fontWeight: FontWeight.w900)),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 12,
              child: Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(
                    horizontal: 5 * scale, vertical: 7 * scale),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isFirst
                        ? const [Color(0xFF775015), Color(0xFF261B13)]
                        : place == 2
                            ? const [Color(0xFF174B80), Color(0xFF0B1C36)]
                            : const [Color(0xFF67413A), Color(0xFF1C1B31)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter),
                  borderRadius: BorderRadius.circular(16 * scale),
                  border: Border.all(color: accent, width: 1.1 * scale),
                  boxShadow: [BoxShadow(
                    color: accent.withValues(alpha: .16),
                    blurRadius: 12 * scale)],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    fitted(name,
                        size: (isFirst ? 17 : 14) * scale),
                    fitted(profile(row)?.activePublicId ?? '—',
                        size: 11 * scale, color: silver, ltr: true),
                    fitted(row == null ? '— نقطة' :
                        '${row.weeklyPoints} نقطة',
                        size: 17 * scale, color: pale),
                    pill('💎 ${prize(place)}',
                        accent, navy),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  Widget rankingTable(double scale) {
    return Container(
      padding: EdgeInsets.all(8 * scale),
      decoration: panel(navy,
          outline: gold.withValues(alpha: .85), radius: 20 * scale),
      child: Column(
        children: [
          SizedBox(
            height: 32 * scale,
            child: Row(
              textDirection: TextDirection.rtl,
              children: [
                SizedBox(width: 23 * scale,
                    child: fitted('#', size: 15 * scale, color: gold)),
                Expanded(flex: 5,
                    child: fitted('المستخدم', size: 12 * scale)),
                Expanded(flex: 2,
                    child: fitted('النقاط المكتسبة', size: 11 * scale, color: gold)),
                Expanded(flex: 3,
                    child: fitted('الجائزة الأسبوعية',
                        size: 11 * scale)),
              ],
            ),
          ),
          ...List.generate(7, (index) {
            final rank = index + 4;
            final score = rowAt(rank);
            return Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 2 * scale),
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 5 * scale),
                  decoration: panel(const Color(0xFF16375B),
                      end: const Color(0xFF0A2749),
                      radius: 10 * scale,
                      outline: const Color(0x44366B98)),
                  child: rankTapSurface(rank, Row(
                    textDirection: TextDirection.rtl,
                    children: [
                      SizedBox(width: 24 * scale,
                          child: fitted('$rank', size: 15 * scale)),
                      Expanded(flex: 5,
                          child: identity(score,
                              avatarSize: 30 * scale,
                              compact: false, interactive: false)),
                      Expanded(flex: 2,
                          child: fitted(score == null ? '—' :
                              '${score.weeklyPoints}',
                              size: 14 * scale, color: gold)),
                      Expanded(flex: 3,
                          child: fitted('💎 10 ماسات',
                              size: 11 * scale, color: silver)),
                    ],
                  )),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget viewerPanel(double scale) {
    final viewer = view.viewerRow;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10 * scale),
      decoration: panel(navy,
          outline: const Color(0xFF2B80C9), radius: 17 * scale),
      child: Row(
        textDirection: TextDirection.rtl,
        children: [
          Expanded(flex: 4,
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  key: const Key('deda_weekly_continue_daily_tasks'),
                  onTap: widget.onOpenDailyTasks,
                  borderRadius: BorderRadius.circular(15 * scale),
                  splashColor: gold.withValues(alpha: .15),
                  child: Container(
                    padding: EdgeInsets.symmetric(
                        horizontal: 3 * scale, vertical: 6 * scale),
                    decoration: BoxDecoration(
                      border: Border.all(color: gold, width: 1.5),
                      borderRadius: BorderRadius.circular(15 * scale),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.trending_up_rounded,
                            color: gold, size: 13 * scale),
                        SizedBox(width: 2 * scale),
                        Flexible(child: fitted('تابع إنجاز المهام',
                            color: gold, size: 11 * scale)),
                      ],
                    ),
                  ),
                ),
              )),
          SizedBox(width: 8 * scale),
          Expanded(flex: 2,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Expanded(child: fitted('النقاط المكتسبة',
                      color: pale, size: 9 * scale)),
                  Expanded(child: fitted(viewer == null ? '— نقطة' :
                      '${viewer.weeklyPoints} نقطة',
                      color: gold, size: 15 * scale)),
                ],
              )),
          Expanded(flex: 4,
              // This is the signed-in player's OWN status, never a social
              // action or a duplicate rank hit target.
              child: identity(viewer,
                  avatarSize: 35 * scale, compact: false,
                  interactive: false)),
          SizedBox(width: 6 * scale),
          Expanded(flex: 2,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  fitted('مركزي', size: 11 * scale, color: silver),
                  fitted(viewer == null ? '—' : '${viewer.place}',
                      size: 22 * scale, color: gold),
                ],
              )),
        ],
      ),
    );
  }

  Widget header(double scale) {
    final remaining = view.remainingUntilWeekEnd;
    String timeLabel = 'بانتظار وقت الأسبوع';
    if (view.verified && remaining != null) {
      final safe = remaining.isNegative ? Duration.zero : remaining;
      timeLabel =
          '${safe.inDays} يوم ${safe.inHours.remainder(24)} س';
    }
    return Column(
      children: [
        Expanded(
          flex: 6,
          child: Row(
            textDirection: TextDirection.ltr,
            children: [
              IconButton(
                tooltip: 'رجوع',
                icon: Icon(Icons.arrow_back,
                    color: Colors.white, size: 22 * scale),
                onPressed: () => Navigator.of(context).pop(),
              ),
              Icon(Icons.emoji_events, color: gold, size: 29 * scale),
              SizedBox(width: 6 * scale),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    fitted('متصدرين المهام',
                        size: 26 * scale),
                    fitted(widget.previewOnly
                        ? 'معاينة تجريبية — بيانات توضيحية فقط'
                        : 'أفضل المستخدمين هذا الأسبوع',
                        size: 12 * scale, color: pale),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'معلومات المنافسة',
                icon: Icon(Icons.info_outline,
                    color: gold, size: 22 * scale),
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('المتصدرون الأسبوعيون'),
                    content: const Text(
                      'شلون تحصل على نقاط الدوري؟\n'
                      'أكمل المهمة اليومية واضغط استلام المكافأة: '
                      'تحصل على 20 نقطة خبرة (XP) ترفع بيها مستواك، '
                      'إضافة إلى 5 نقاط عادية منفصلة.\n'
                      'الدوري يحسب نقاط المستوى المكتسبة من المهام '
                      'خلال الأسبوع فقط، بعد التحقق منها بالخادم. '
                      'أما 10 نقاط لتسجيل الدخول اليومي، و5 نقاط لكل '
                      'إجابة مرورية صحيحة، فهي نقاط عادية وليست '
                      'XP إضافية مباشرة.\n'
                      'مستواك ورصيدك السابق ما يتصفران. '
                      'المراكز تتغير حسب XP المكتسبة من المهام. '
                      'الجوائز: 150 و100 و50 ماسة للمراكز الثلاثة '
                      'الأولى، و10 ماسات للمراكز 4–10. '
                      'لا تُضاف الماسات إلا بعد اعتماد النتائج من الخادم.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context),
                          child: const Text('حسناً')),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          flex: 5,
          child: Row(
            children: [
              Expanded(
                flex: 5,
                child: Row(
                  children: [
                    Expanded(child: GestureDetector(
                      onTap: () => setState(() => previousWeek = false),
                      child: Container(
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: previousWeek ? Colors.transparent : gold,
                          border: Border.all(color: gold),
                          borderRadius: BorderRadius.circular(28),
                        ),
                        child: fitted('الأسبوع الحالي',
                            size: 13 * scale,
                            color: previousWeek ? Colors.white : navy),
                      ),
                    )),
                    Expanded(child: GestureDetector(
                      onTap: () => setState(() => previousWeek = true),
                      child: Container(
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: previousWeek ? gold : Colors.transparent,
                          border: Border.all(color: blue),
                          borderRadius: BorderRadius.circular(28),
                        ),
                        child: fitted('الأسبوع السابق',
                            size: 13 * scale,
                            color: previousWeek ? navy : Colors.white),
                      ),
                    )),
                  ],
                ),
              ),
              SizedBox(width: 10 * scale),
              Expanded(
                flex: 3,
                child: Container(
                  alignment: Alignment.center,
                  decoration: panel(blue, radius: 13 * scale),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      fitted('الوقت المتبقي',
                          size: 10 * scale, color: silver),
                      fitted(timeLabel,
                          size: 12 * scale, color: gold),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Status is the same for portrait and landscape; never present local
  /// device XP or fake winners as verified league standing.
  Widget statusPanel(double scale) => Container(
        alignment: Alignment.center,
        decoration: panel(blue, radius: 13 * scale),
        padding: EdgeInsets.symmetric(horizontal: 8 * scale),
        child: fitted(widget.previewOnly
            ? 'معاينة تصميم فقط؛ الأسماء والنقاط والجوائز وهمية.'
            : view.verified
                ? 'XP المكتسبة من المهام هذا الأسبوع؛ '
                    'رصيد حسابك ومستواك محفوظان.'
                : 'الترتيب قيد التحقق من الخادم؛ '
                    'لن تُعرض نتائج وهمية أو تُصرف جوائز.',
            size: 11 * scale, color: silver),
      );

  Widget podiumRow(double scale) => Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        textDirection: TextDirection.ltr,
        children: [
          podium(2, scale),
          podium(1, scale),
          podium(3, scale),
        ],
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: navy,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, box) {
            // Real landscape must USE the width: the old 2:3 portrait canvas
            // shrank the entire league to a tiny central strip on tablets and
            // landscape phones. Keep portrait EXACTLY as owner accepted.
            final landscape = box.maxWidth >= 580 &&
                box.maxWidth > box.maxHeight * 1.18;
            final stageWidth = landscape
                ? math.min(box.maxWidth, 1280.0)
                : math.min(box.maxWidth, box.maxHeight * (2.0 / 3.0));
            final scale = landscape
                ? math.min(stageWidth / 950, box.maxHeight / 580)
                    .clamp(.55, 1.45).toDouble()
                : math.min(stageWidth / 390, box.maxHeight / 780)
                    .clamp(.50, 2.10).toDouble();
            final gap = (landscape ? 5.0 : 7.0) * scale;
            return Center(
              child: SizedBox(
                key: const ValueKey<String>('deda-weekly-leaderboard-stage'),
                width: stageWidth,
                height: box.maxHeight,
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xFF083363), navy, Color(0xFF061D3A)],
                    ),
                  ),
                  padding: EdgeInsets.symmetric(
                      horizontal: 9 * scale, vertical: 5 * scale),
                  child: landscape
                      ? Column(
                          key: const ValueKey<String>(
                              'deda-weekly-landscape-layout'),
                          children: [
                            Expanded(flex: 24, child: header(scale)),
                            SizedBox(height: gap),
                            Expanded(
                              flex: 60,
                              child: Row(
                                textDirection: TextDirection.ltr,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(flex: 46, child: podiumRow(scale)),
                                  SizedBox(width: 9 * scale),
                                  Expanded(flex: 54, child: rankingTable(scale)),
                                ],
                              ),
                            ),
                            SizedBox(height: gap),
                            Expanded(
                              flex: 16,
                              child: Row(
                                textDirection: TextDirection.rtl,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(flex: 55, child: viewerPanel(scale)),
                                  SizedBox(width: 9 * scale),
                                  Expanded(flex: 45, child: statusPanel(scale)),
                                ],
                              ),
                            ),
                          ],
                        )
                      : Column(
                          key: const ValueKey<String>(
                              'deda-weekly-portrait-layout'),
                          children: [
                            Expanded(flex: 14, child: header(scale)),
                            SizedBox(height: gap),
                            Expanded(flex: 29, child: podiumRow(scale)),
                            SizedBox(height: gap),
                            Expanded(flex: 40, child: rankingTable(scale)),
                            SizedBox(height: gap),
                            Expanded(flex: 9, child: viewerPanel(scale)),
                            SizedBox(height: gap),
                            Expanded(flex: 7, child: statusPanel(scale)),
                          ],
                        ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Small home-screen hero tile, same slot as the retired Restaurants tile.
class DedaLeaderboardHomeCard extends StatelessWidget {
  const DedaLeaderboardHomeCard({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF081C35), Color(0xFF144573),
                  Color(0xFF805114)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFFFCF67), width: 1.5),
          ),
          child: LayoutBuilder(
            builder: (context, box) => Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Icon(Icons.emoji_events_rounded,
                    color: const Color(0xFFFFD369),
                    size: math.min(43, box.maxHeight * .35)),
                const FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text('المتصدرين',
                    style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w900,
                      fontSize: 23),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
