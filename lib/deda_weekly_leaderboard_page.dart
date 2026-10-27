import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'deda_weekly_leaderboard_policy.dart';

/// Display-only verified leaderboard identity.
//// Users and scores must come from the approved server, never test/mock data.
/// This intentionally cannot read, create or transfer XP and diamonds.
class DedaLeaderboardProfile {
  const DedaLeaderboardProfile({
    required this.accountUid,
    required this.displayName,
    required this.activePublicId,
    this.avatarImage,
  });

  final String accountUid;
  final String displayName;
  final String activePublicId;
  final ImageProvider? avatarImage;
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
    this.current = const DedaLeaderboardViewData(
      verified: false,
      rows: [],
      profilesByUid: {},
    ),
    this.previous = const DedaLeaderboardViewData(
      verified: false,
      rows: [],
      profilesByUid: {},
    ),
  });

  final DedaLeaderboardViewData current;
  final DedaLeaderboardViewData previous;

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
      {double avatarSize = 33, bool compact = false}) {
    final details = profile(row);
    return Row(
      mainAxisSize: MainAxisSize.min,
      textDirection: TextDirection.rtl,
      children: [
        Container(
          height: avatarSize,
          width: avatarSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: gold, width: 1.5),
          ),
          child: CircleAvatar(
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
    return Expanded(
      child: Padding(
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
                        accent.withOpacity(.45),
                        accent.withOpacity(.10),
                        Colors.transparent,
                      ]),
                    ),
                  ),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.workspace_premium_rounded,
                          size: 29 * scale, color: accent),
                      Container(
                        width: 65 * scale,
                        height: 65 * scale,
                        padding: EdgeInsets.all(4 * scale),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: accent, width: 2),
                        ),
                        child: CircleAvatar(
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
                decoration: panel(
                  isFirst ? const Color(0xFF67400B) : blue,
                  end: navy,
                  radius: 16 * scale,
                  outline: accent,
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
    );
  }

  Widget rankingTable(double scale) {
    return Container(
      padding: EdgeInsets.all(8 * scale),
      decoration: panel(navy,
          outline: gold.withOpacity(.85), radius: 20 * scale),
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
                  child: Row(
                    textDirection: TextDirection.rtl,
                    children: [
                      SizedBox(width: 24 * scale,
                          child: fitted('$rank', size: 15 * scale)),
                      Expanded(flex: 5,
                          child: identity(score,
                              avatarSize: 30 * scale,
                              compact: false)),
                      Expanded(flex: 2,
                          child: fitted(score == null ? '—' :
                              '${score.weeklyPoints}',
                              size: 14 * scale, color: gold)),
                      Expanded(flex: 3,
                          child: fitted('💎 10 ماسات',
                              size: 11 * scale, color: silver)),
                    ],
                  ),
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
              child: Container(
                padding: EdgeInsets.symmetric(
                    horizontal: 3 * scale, vertical: 6 * scale),
                decoration: BoxDecoration(
                  border: Border.all(color: gold, width: 1.5),
                  borderRadius: BorderRadius.circular(15 * scale),
                ),
                child: fitted('تابع إنجاز المهام',
                    color: gold, size: 11 * scale),
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
              child: identity(viewer,
                  avatarSize: 35 * scale, compact: true)),
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
                    fitted('أفضل المستخدمين هذا الأسبوع',
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
                      'تنجز المهام اليومية وتستلم نقاطها: 5 نقاط للمهمة، '
                      '10 نقاط لتسجيل الدخول اليومي، و5 نقاط لكل '
                      'إجابة مرورية صحيحة.\n'
                      'العداد هنا يوضح النقاط المكتسبة من المهام '
                      'خلال هذا الأسبوع فقط، بعد التحقق منها. '
                      'نقاط حسابك السابقة ومستواك ما تتصفر.\n'
                      'المراكز تتغير مع كل نقطة مكتسبة. '
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: navy,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, box) {
            // Scale by BOTH dimensions. Never scroll or clip user records.
            final scale = math.min(box.maxWidth / 390, box.maxHeight / 780)
                .clamp(.60, 1.30)
                .toDouble();
            final gap = 7.0 * scale;
            return Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF083363), navy, Color(0xFF061D3A)],
                ),
              ),
              padding: EdgeInsets.symmetric(
                  horizontal: 9 * scale, vertical: 5 * scale),
              child: Column(
                children: [
                  Expanded(flex: 14, child: header(scale)),
                  SizedBox(height: gap),
                  Expanded(
                    flex: 29,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      textDirection: TextDirection.ltr,
                      children: [
                        podium(2, scale),
                        podium(1, scale),
                        podium(3, scale),
                      ],
                    ),
                  ),
                  SizedBox(height: gap),
                  Expanded(flex: 40, child: rankingTable(scale)),
                  SizedBox(height: gap),
                  Expanded(flex: 9, child: viewerPanel(scale)),
                  SizedBox(height: gap),
                  Expanded(
                    flex: 7,
                    child: Container(
                      alignment: Alignment.center,
                      decoration: panel(blue, radius: 13 * scale),
                      padding: EdgeInsets.symmetric(horizontal: 8 * scale),
                      child: fitted(view.verified
                          ? 'النقاط المكتسبة من المهام خلال الأسبوع؛ '
                            'رصيد حسابك ومستواك محفوظان.'
                          : 'الترتيب قيد التحقق من الخادم؛ '
                            'لن تُعرض نتائج وهمية أو تُصرف جوائز.',
                          size: 11 * scale, color: silver),
                    ),
                  ),
                ],
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
              colors: [Color(0xFF09294D), Color(0xFF72511B)],
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
