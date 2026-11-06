import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'deda_admin_league_active_id.dart';
import 'deda_admin_league_live_data.dart';
import 'deda_weekly_league_clock.dart';

/// Read-only report. Mounted only after the app verified GENERAL MANAGER role.
/// Score ranks, held-user reviews, approved amounts and Hadaya receipts remain
/// four independent server sources. Absence of a gift NEVER means paid.
enum DedaWeeklyGiftStatus { notCreated, pending, received, frozen, review }

class DedaWeeklyPrizeWinner {
  const DedaWeeklyPrizeWinner(this.place,this.name,this.originalId,this.amount,this.status);
  final int place;
  final String name,originalId;
  final int amount;
  final DedaWeeklyGiftStatus status;
}
class DedaWeeklyPrizeReport {
  const DedaWeeklyPrizeReport(this.weekId,this.rows);
  final String weekId;
  final List<DedaWeeklyPrizeWinner> rows;
}
class DedaWeeklyPrizeProjection {
  static const minimum=[250,200,150,100,100,100,100,100,100,100];
  static String giftId(String week,String id) =>
      'deda-weekly-$week-${id.substring(1)}';
  static List<int> amounts(List<dynamic>? saved) {
    if(saved==null) return minimum;
    if(saved.length!=10) throw StateError('invalid-week-prize-plan');
    final result=<int>[];
    for(var i=0;i<10;i++){
      final v=saved[i];
      if(v is! int || v<minimum[i] || v>1000000){
        throw StateError('invalid-week-prize-value');
      }
      result.add(v);
    }
    return List<int>.unmodifiable(result);
  }
  static DedaWeeklyPrizeReport merge({
    required String week,
    required Iterable<MapEntry<String,Map<String,dynamic>>> scores,
    required Map<String,Map<String,dynamic>> gifts,
    required Set<String> frozen,
    List<dynamic>? plan,
  }){
    if(!RegExp(r'^20[0-9]{2}-[0-9]{2}-[0-9]{2}$').hasMatch(week)){
      throw ArgumentError.value(week);
    }
    final prizes=amounts(plan);
    final winners=<DedaWeeklyPrizeWinner>[];
    for(final player in DedaAdminLeagueProjection.fromRecords(scores).take(10)){
      final gid=giftId(week,player.publicId);
      final gift=gifts[gid];
      var status=frozen.contains(player.publicId)
          ? DedaWeeklyGiftStatus.frozen : DedaWeeklyGiftStatus.notCreated;
      final amount=prizes[player.place-1];
      if(gift!=null){
        final valid=gift['giftId']==gid &&
            gift['sourceType']=='weekly_league' &&
            gift['targetPublicId']==player.publicId &&
            gift['amount']==amount &&
            gift['reason'] is String &&
            (gift['reason'] as String).contains(week) &&
            (gift['reason'] as String).contains('المركز ${player.place}');
        if(!valid || frozen.contains(player.publicId)){
          status=DedaWeeklyGiftStatus.review;
        }else if(gift['status']=='pending'){
          status=DedaWeeklyGiftStatus.pending;
        }else if(gift['status']=='received'){
          status=DedaWeeklyGiftStatus.received;
        }else{
          status=DedaWeeklyGiftStatus.review;
        }
      }
      winners.add(DedaWeeklyPrizeWinner(
        player.place,player.name,player.publicId,amount,status));
    }
    return DedaWeeklyPrizeReport(week,List.unmodifiable(winners));
  }
}
class DedaWeeklyPrizeReader {
  DedaWeeklyPrizeReader({FirebaseFirestore? firestore}):
      _db=firestore??FirebaseFirestore.instance;
  final FirebaseFirestore _db;
  Future<DedaWeeklyPrizeReport> load(String week) async{
    const options=GetOptions(source:Source.server);
    final scoreFuture=_db.collection('deda_weekly_direct_weeks')
      .doc(week).collection('scores').limit(100).get(options);
    final prefix='deda-weekly-$week-';
    final giftFuture=_db.collection('deda_diamond_gifts')
      .orderBy(FieldPath.documentId)
      .startAt([prefix]).endAt(['$prefix\uf8ff'])
      .limit(100).get(options);
    final reviewFuture=_db.collection('deda_weekly_direct_reviews')
      .doc(week).collection('users').limit(100).get(options);
    final planFuture=_db.collection('deda_weekly_direct_prize_plans')
      .doc(week).get(options);
    final scores=await scoreFuture;
    final gifts=await giftFuture;
    final reviews=await reviewFuture;
    final prize=await planFuture;
    if(scores.docs.length>=100 || gifts.docs.length>=100 ||
       reviews.docs.length>=100){
      throw StateError('league-report-limit-review');
    }
    return DedaWeeklyPrizeProjection.merge(
      week:week,
      scores:[for(final d in scores.docs) MapEntry(d.id,d.data())],
      gifts:{for(final d in gifts.docs) d.id:d.data()},
      frozen:{
        for(final d in reviews.docs) if(d.data()['frozen']==true) d.id
      },
      plan: prize.exists ? prize.data()?['amounts'] as List<dynamic>? : null,
    );
  }
}

/// One compact report in the existing admin card; same four-column order as
/// the owner reference; no duplicate prize panel or client-side writes.
class DedaAdminLeagueWinnersPrizes extends StatefulWidget{
  const DedaAdminLeagueWinnersPrizes({
    super.key,required this.isArabic,this.testLoad,this.testNow});
  final bool isArabic;
  final Future<DedaWeeklyPrizeReport> Function(String)? testLoad;
  final DateTime? testNow;
  @override
  State<DedaAdminLeagueWinnersPrizes> createState()=>_DedaAdminLeagueWinnersPrizesState();
}
class _DedaAdminLeagueWinnersPrizesState extends State<DedaAdminLeagueWinnersPrizes>{
  List<String> _weeks=const [];
  String? _week;
  Future<DedaWeeklyPrizeReport>? _result;
  String t(String ar,String en)=>widget.isArabic?ar:en;
  List<String> _completed(){
    final utc=(widget.testNow??DateTime.now()).toUtc();
    final ms=utc.difference(DedaWeeklyLeagueClock.origin).inMilliseconds;
    final length=DedaWeeklyLeagueClock.weekLength.inMilliseconds;
    if(ms<length) return const [];
    final count=ms~/length;
    return [
      for(var n=count-1;n>=0 && n>=count-12;n--)
        DedaAdminLeagueLiveData.weekId(
          DedaWeeklyLeagueClock.origin.add(Duration(milliseconds:n*length)))
    ];
  }
  @override
  void initState(){super.initState();_refresh();}
  void _refresh(){
    final weeks=_completed();
    final selected=weeks.contains(_week)?_week:(weeks.isEmpty?null:weeks.first);
    setState((){
      _weeks=weeks;_week=selected;
      _result=selected==null?null:
        (widget.testLoad?.call(selected)??DedaWeeklyPrizeReader().load(selected));
    });
  }
  String _label(DedaWeeklyGiftStatus value){
    switch(value){
      case DedaWeeklyGiftStatus.notCreated:return t('لم تُنشأ','Not issued');
      case DedaWeeklyGiftStatus.pending:return t('بانتظار الاستلام','Pending claim');
      case DedaWeeklyGiftStatus.received:return t('تم الاستلام','Claimed');
      case DedaWeeklyGiftStatus.frozen:return t('قيد المراجعة','Held');
      case DedaWeeklyGiftStatus.review:return t('تحتاج مراجعة','Review');
    }
  }
  TextStyle _font({bool head=false,Color? color})=>TextStyle(
    fontSize:head?12:11,fontWeight:head?FontWeight.w800:FontWeight.w600,
    color:color??const Color(0xFF1B2940),height:1.3);
  Widget _cell(Widget child)=>Padding(
    padding:const EdgeInsets.symmetric(vertical:12,horizontal:3),child:child);
  Widget _table(DedaWeeklyPrizeReport data){
    if(data.rows.isEmpty){
      return Text(t('لا يوجد فائزون مثبتون لهذا الأسبوع.',
        'No verified winners for this week.'));
    }
    return Table(
      key:const Key('deda-admin-winners-prizes-table'),
      textDirection:widget.isArabic?TextDirection.rtl:TextDirection.ltr,
      defaultVerticalAlignment:TableCellVerticalAlignment.middle,
      columnWidths:const{
        0:FlexColumnWidth(1.20),1:FlexColumnWidth(2.5),
        2:FlexColumnWidth(1.55),3:FlexColumnWidth(2.0)
      },
      border:const TableBorder(horizontalInside:
        BorderSide(color:Color(0xFFE5E7EB))),
      children:[
        TableRow(children:[
          _cell(Text(t('المركز','Rank'),style:_font(head:true))),
          _cell(Text(t('المستخدم','Winner'),style:_font(head:true))),
          _cell(Text(t('الجائزة','Prize'),style:_font(head:true))),
          _cell(Text(t('الحالة','Status'),style:_font(head:true))),
        ]),
        for(final row in data.rows)
          TableRow(key:ValueKey('deda-winner-${row.place}'),children:[
            _cell(Text(row.place<=3
              ? '${['🥇','🥈','🥉'][row.place-1]} ${row.place}'
              : '${row.place}',style:_font())),
            _cell(Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              Text(row.name,maxLines:2,overflow:TextOverflow.ellipsis,style:_font()),
              DedaAdminLeagueActiveId(
                originalId:row.originalId,style:const TextStyle(fontSize:9)),
            ])),
            _cell(Text('${row.amount} ${t('ماسة','diamonds')}',style:_font())),
            _cell(Text(_label(row.status),style:_font(
              color:row.status==DedaWeeklyGiftStatus.received
                ? const Color(0xFF19764D):const Color(0xFF626D7B)))),
          ]),
      ]);
  }
  @override
  Widget build(BuildContext context){
    if(_weeks.isEmpty) return Text(t(
      'ينفتح السجل بعد اكتمال الأسبوع يوم السبت الساعة 6 صباحاً.',
      'History appears after Saturday 06:00 at the end of the week.'));
    return Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      Row(children:[
        Expanded(child:DropdownButton<String>(
          key:const Key('deda-admin-winners-prizes-week'),
          isExpanded:true,value:_week,
          items:[
            for(final w in _weeks)
              DropdownMenuItem(value:w,child:Text(t('الأسبوع $w','Week $w'),
                style:_font()))
          ],
          onChanged:(w){
            if(w==null || w==_week)return;
            setState(()=>_week=w);
            _refresh();
          })),
        IconButton(key:const Key('deda-admin-winners-prizes-refresh'),
          tooltip:t('تحديث السجل','Refresh history'),
          onPressed:_refresh,icon:const Icon(Icons.refresh)),
      ]),
      const SizedBox(height:6),
      Text(t('الترتيب من نقاط الدوري وحالة الجائزة من «هداياي».',
        'Ranks from league XP; delivery from Hadaya receipts.'),
        style:const TextStyle(fontSize:11,color:Color(0xFF667085))),
      const SizedBox(height:8),
      FutureBuilder<DedaWeeklyPrizeReport>(future:_result,builder:(context,snap){
        if(snap.hasError) return Text(t(
          'تعذر تأكيد بيانات Firebase. أعد التحديث.',
          'Unable to verify Firebase receipts. Retry.'));
        if(!snap.hasData || snap.data!.weekId!=_week){
          return const LinearProgressIndicator();
        }
        return _table(snap.data!);
      }),
    ]);
  }
}
