import 'package:flutter/material.dart';

import 'deda_admin_league_live_data.dart';

/// Only mounted after the current GENERAL MANAGER has passed the original
/// DEDA admin profile/active-status gate. Uses original shared score docs.
class DedaAdminLeagueLiveStandings extends StatefulWidget {
  const DedaAdminLeagueLiveStandings({
    super.key,
    required this.isArabic,
    this.injectedRows,
  });
  final bool isArabic;
  final Stream<List<DedaAdminLeagueRow>>? injectedRows;

  @override
  State<DedaAdminLeagueLiveStandings> createState() =>
      _DedaAdminLeagueLiveStandingsState();
}

class _DedaAdminLeagueLiveStandingsState
    extends State<DedaAdminLeagueLiveStandings> {
  Stream<List<DedaAdminLeagueRow>>? _rows;

  @override
  void initState() {
    super.initState();
    _rows = widget.injectedRows ??
        DedaAdminLeagueLiveData().currentWeek(DateTime.now().toUtc());
  }

  @override
  void didUpdateWidget(covariant DedaAdminLeagueLiveStandings oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.injectedRows != widget.injectedRows) {
      _rows = widget.injectedRows ??
          DedaAdminLeagueLiveData().currentWeek(DateTime.now().toUtc());
    }
  }

  String t(String ar, String en) => widget.isArabic ? ar : en;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<DedaAdminLeagueRow>>(
      stream: _rows,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Text(t(
            'تعذر الاتصال بترتيب Firebase. لا توجد نتائج تجريبية.',
            'Unable to read shared Firebase standings. No mock data.',
          ));
        }
        if (!snapshot.hasData) {
          return const Center(child: Padding(
            padding: EdgeInsets.all(8), child: CircularProgressIndicator(),
          ));
        }
        final rows = snapshot.data!;
        if (rows.isEmpty) {
          return Text(t('لا توجد نقاط دوري مسجلة لهذا الأسبوع بعد.',
              'No league XP claimed in this week yet.'));
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final person in rows.take(10))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    SizedBox(width: 32, child: Text('${person.place}.',
                        style: const TextStyle(fontWeight: FontWeight.bold))),
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(person.name, maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                        Text(person.publicId,
                            textDirection: TextDirection.ltr,
                            style: const TextStyle(fontSize: 11)),
                      ],
                    )),
                    Text('${person.xp} XP',
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class DedaAdminLeagueLivePodium extends StatefulWidget {
  const DedaAdminLeagueLivePodium({
    super.key,
    required this.isArabic,
    this.injectedRows,
  });
  final bool isArabic;
  final Stream<List<DedaAdminLeagueRow>>? injectedRows;
  @override
  State<DedaAdminLeagueLivePodium> createState() =>
      _DedaAdminLeagueLivePodiumState();
}

class _DedaAdminLeagueLivePodiumState extends State<DedaAdminLeagueLivePodium> {
  late Stream<List<DedaAdminLeagueRow>> _rows;
  @override
  void initState() {
    super.initState();
    _rows = widget.injectedRows ??
        DedaAdminLeagueLiveData().currentWeek(DateTime.now().toUtc());
  }
  @override
  void didUpdateWidget(covariant DedaAdminLeagueLivePodium oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.injectedRows != widget.injectedRows) {
      _rows = widget.injectedRows ??
        DedaAdminLeagueLiveData().currentWeek(DateTime.now().toUtc());
    }
  }
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<DedaAdminLeagueRow>>(
      stream: _rows,
      builder: (context, snap) {
        if (snap.hasError) {
          return Text(widget.isArabic
              ? 'تعذر قراءة النتائج الحقيقية.' : 'Live ranks unavailable.');
        }
        if (!snap.hasData) {
          return const LinearProgressIndicator();
        }
        final top = snap.data!.take(3).toList();
        if (top.isEmpty) {
          return Text(widget.isArabic
              ? 'لا يوجد متصدرون حتى الآن.' : 'No leaders yet.');
        }
        const icons = [Icons.emoji_events, Icons.workspace_premium,
          Icons.military_tech];
        const colors = [Color(0xFFD7A828), Color(0xFF9BA9B4), Color(0xFFB87846)];
        return Column(
          children: [
            for (final person in top)
              Padding(padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(children: [
                  Icon(icons[person.place - 1],
                      color: colors[person.place - 1]),
                  const SizedBox(width: 8),
                  Expanded(child: Text(person.name,
                      maxLines: 1, overflow: TextOverflow.ellipsis)),
                  Text('${person.xp} XP',
                      textDirection: TextDirection.ltr),
                ]),
              ),
          ],
        );
      },
    );
  }
}

class DedaAdminLeagueLiveArchive extends StatefulWidget {
  const DedaAdminLeagueLiveArchive({
    super.key,
    required this.isArabic,
    this.injectedWeeks,
  });
  final bool isArabic;
  final Future<List<DedaAdminLeagueWeek>>? injectedWeeks;
  @override
  State<DedaAdminLeagueLiveArchive> createState() =>
      _DedaAdminLeagueLiveArchiveState();
}

class _DedaAdminLeagueLiveArchiveState
    extends State<DedaAdminLeagueLiveArchive> {
  late Future<List<DedaAdminLeagueWeek>> _weeks;
  @override
  void initState() {
    super.initState();
    _load();
  }
  void _load() {
    _weeks = widget.injectedWeeks ??
        DedaAdminLeagueLiveData().completedWeeks(DateTime.now().toUtc());
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: TextButton.icon(
            onPressed: () => setState(_load),
            icon: const Icon(Icons.refresh),
            label: Text(widget.isArabic ? 'تحديث الأرشيف' : 'Refresh history'),
          ),
        ),
        FutureBuilder<List<DedaAdminLeagueWeek>>(
          future: _weeks,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Text(widget.isArabic
                  ? 'تعذر قراءة سجل الأسابيع.' : 'Week history unavailable.');
            }
            if (!snapshot.hasData) {
              return const LinearProgressIndicator();
            }
            final weeks = snapshot.data!;
            if (weeks.isEmpty) {
              return Text(widget.isArabic
                  ? 'لا توجد أسابيع مكتملة بعد.'
                  : 'No completed league weeks yet.');
            }
            return Column(children: [
              for (final week in weeks)
                ExpansionTile(
                  key: Key('deda-admin-league-archive-${week.id}'),
                  title: Text(widget.isArabic
                      ? 'الأسبوع ${week.id}' : 'Week ${week.id}'),
                  subtitle: Text(widget.isArabic
                      ? '${week.rows.length} متصدرين'
                      : '${week.rows.length} ranked competitors'),
                  children: [
                    for (final player in week.rows)
                      ListTile(
                        dense: true,
                        title: Text('${player.place}. ${player.name}'),
                        subtitle: Text(player.publicId),
                        trailing: Text('${player.xp} XP'),
                      ),
                  ],
                ),
            ]);
          },
        ),
      ],
    );
  }
}
