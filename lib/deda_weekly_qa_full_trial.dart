import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'deda_weekly_private_trial_local_xp.dart';
import 'deda_weekly_leaderboard_policy.dart';

/// PRIVATE owner QA ONLY. Uses an isolated disposable sandbox ledger.
/// NEVER a canonical leaderboard, cloud operation, actual XP or diamond wallet.
class DedaWeeklyQaSandbox {
  DedaWeeklyQaSandbox(this.accountKey);
  final String accountKey;
  String get key => 'deda_weekly_qa_earned_shadow_v1_$accountKey';
  static int prize(int place) =>
    DedaWeeklyLeaderboardPolicy.diamondsForFinalPlace(place);
  static String week(int offset, DateTime now) {
    if(offset<0||offset>52)throw RangeError('qa-week');
    final base=DateTime.parse(
       DedaWeeklyPrivateTrialLocalXp.testWeekKey(now));
    return DedaWeeklyPrivateTrialLocalXp.dayKey(
       base.add(Duration(days:7*offset)));
  }
  Future<Map<String,dynamic>> read() async {
    if(!RegExp(r'^\d{10,16}$').hasMatch(accountKey)) {
      throw StateError('qa-invalid-account-scope');
    }
    final prefs=await SharedPreferences.getInstance();
    Map<String,dynamic> state={};
    try {
      state=Map<String,dynamic>.from(
          jsonDecode(prefs.getString(key)??'{}') as Map);
    } catch(_) {}
    final offset=state['offset'];
    final rank=state['rank'];
    final paid=state['paid'];
    if(state['version']!=1||offset is! int||offset<0||offset>52||
       rank is! int||rank<1||rank>11||paid is! Map) {
      return {'version':1,'offset':0,'rank':1,
        'paid':<String,dynamic>{}};
    }
    final clean=<String,dynamic>{};
    for(final entry in paid.entries) {
      if(entry.key is! String || !RegExp(r'^\d{4}-\d\d-\d\d$')
          .hasMatch(entry.key) || entry.value is! Map)continue;
      final v=Map<String,dynamic>.from(entry.value as Map);
      if(v['rank'] is int && v['rank']>=1 && v['rank']<=11 &&
         v['diamonds']==prize(v['rank'])) {
        clean[entry.key]={'rank':v['rank'],'diamonds':v['diamonds']};
      }
    }
    return {'version':1,'offset':offset,'rank':rank,'paid':clean};
  }
  Future<Map<String,dynamic>> save(Map<String,dynamic> state) async {
    final prefs=await SharedPreferences.getInstance();
    await prefs.setString(key,jsonEncode(state));
    return state;
  }
  Future<Map<String,dynamic>> choose(int rank, {DateTime? now}) async {
    if(rank<1||rank>11)throw RangeError('rank');
    final state=await read();
    final current=week(state['offset'] as int,now??DateTime.now());
    if((state['paid'] as Map).containsKey(current))return state;
    state['rank']=rank;
    return save(state);
  }
  Future<Map<String,dynamic>> settle(DateTime now) async {
    final state=await read();
    final id=week(state['offset'] as int,now);
    final paid=Map<String,dynamic>.from(state['paid'] as Map);
    // The same week cannot pay twice, even after changing rank or reopening.
    if(paid.containsKey(id))return state;
    final rank=state['rank'] as int;
    paid[id]={'rank':rank,'diamonds':prize(rank)};
    state['paid']=paid;
    return save(state);
  }
  Future<Map<String,dynamic>> next({DateTime? now}) async {
    final state=await read();
    final offset=state['offset'] as int;
    if(offset==52)throw RangeError('week');
    final current=week(offset,now??DateTime.now());
    if(!(state['paid'] as Map).containsKey(current)) {
      throw StateError('settle-first');
    }
    state['offset']=offset+1;
    state['rank']=1;
    return save(state);
  }
  Future<void> reset() async {
    (await SharedPreferences.getInstance()).remove(key);
  }
  static int earned(Map<String,dynamic> state) {
    final entries=state['paid'];
    if(entries is! Map)return 0;
    return entries.values.fold<int>(0,(sum,entry)=>
        sum+(entry is Map && entry['diamonds'] is int
              ? entry['diamonds'] as int:0));
  }
}

/// Tests all rank positions, previous/current week, payout once and mock
/// earned-diamond balance. Deliberately no fictional player names and no
/// spendable balance, Firebase write or production competition claims.
class DedaWeeklyQaFullTrialPage extends StatefulWidget {
  const DedaWeeklyQaFullTrialPage({
    super.key,required this.accountScope,this.initialLocalXp=0});
  final String accountScope;
  final int initialLocalXp;
  @override
  State<DedaWeeklyQaFullTrialPage> createState()=>_DedaWeeklyQaFullTrialPageState();
}
class _DedaWeeklyQaFullTrialPageState extends State<DedaWeeklyQaFullTrialPage> {
  late DedaWeeklyQaSandbox lab;
  Map<String,dynamic> state={};
  int localXp=0;
  bool busy=false,previous=false;
  String? error;
  @override
  void initState(){
    super.initState();
    lab=DedaWeeklyQaSandbox(widget.accountScope);
    localXp=widget.initialLocalXp;
    _reload();
  }
  Future<void> _reload() async {
    try {
      final updated=await lab.read();
      final xp=await DedaWeeklyPrivateTrialLocalXp.read(widget.accountScope);
      if(!mounted)return;
      setState((){state=updated;localXp=xp??0;busy=false;});
    }catch(_){
      if(mounted)setState((){
        busy=false;error='التحقق من حساب المختبر فشل';
      });
    }
  }
  Future<void> _act(Future<void> Function() operation) async {
    if(busy)return;
    setState((){busy=true;error=null;});
    try {
      await operation();
      await _reload();
    }catch(_){
      if(mounted)setState((){
        busy=false;error='فشل اختبار الإجراء؛ أرصدتك الحقيقية محفوظة';
      });
    }
  }
  @override
  Widget build(BuildContext context){
    const navy=Color(0xFF0B2C50),gold=Color(0xFFFFCD65);
    final selected=state['rank'] as int? ?? 1;
    final offset=state['offset'] as int? ?? 0;
    final paid=state['paid'] as Map? ?? {};
    final week=DedaWeeklyQaSandbox.week(
        previous&&offset>0?offset-1:offset,DateTime.now());
    final result=(previous && offset==0) ? null :
        (paid[week] is Map ? paid[week] as Map : null);
    final settled=paid.containsKey(
        DedaWeeklyQaSandbox.week(offset,DateTime.now()));
    return Scaffold(
      backgroundColor:const Color(0xFF061B33),
      appBar:AppBar(backgroundColor:navy,foregroundColor:gold,
        title:const Text('مختبر دوري DEDA',style:TextStyle(color:gold))),
      body:SafeArea(child:ListView(
        padding:const EdgeInsets.all(12),
        children:[
          Card(color:navy,child:Padding(
            padding:const EdgeInsets.all(14),
            child:Column(children:[
              const Text('اختبار كامل — بيانات ومكافآت تجريبية فقط',
                style:TextStyle(color:gold,fontSize:18,
                  fontWeight:FontWeight.bold)),
              const Text('ماكو مستخدمون وهميون في الدوري الحقيقي. '
                'هذه المقاعد لغرض تجربة المراكز والجوائز فقط.',
                style:TextStyle(color:Colors.white),
                textAlign:TextAlign.center),
              Text('نقاط مهامك المحفوظة محلياً: $localXp XP',
                style:const TextStyle(color:Colors.white)),
              Text('رصيد المختبر التجريبي: ${DedaWeeklyQaSandbox.earned(state)} 💎',
                style:const TextStyle(color:gold,fontSize:19)),
            ]),
          )),
          Row(children:[
            Expanded(child:ChoiceChip(
              label:const Text('الأسبوع الحالي'),selected:!previous,
              onSelected:(_)=>setState(()=>previous=false))),
            const SizedBox(width:6),
            Expanded(child:ChoiceChip(
              label:const Text('الأسبوع السابق'),selected:previous,
              onSelected:(_)=>setState(()=>previous=true))),
          ]),
          Text('أسبوع الفحص: $week',
            textAlign:TextAlign.center,
            style:const TextStyle(color:gold)),
          for(var i=1;i<=10;i++)
            Card(color:navy,child:ListTile(
              dense:true,
              leading:Icon(i==1?Icons.workspace_premium:Icons.emoji_events,
                color:gold),
              title:Text('المركز $i — ${DedaWeeklyQaSandbox.prize(i)} ماسة',
                style:const TextStyle(color:Colors.white)),
              subtitle:Text(result!=null&&result['rank']==i
                 ? 'جائزة اختبارك سُجلت للمركز $i'
                 : !previous && selected==i
                   ? 'المركز المختار لفحص حسابك — غير معتمد فعلياً'
                   : 'مقعد اختبار، ليس مستخدمًا حقيقيًا',
                style:const TextStyle(color:Colors.white70)),
              trailing:result!=null&&result['rank']==i
                ? const Icon(Icons.check_circle,color:gold):null,
            )),
          Card(color:navy,child:ListTile(
            title:const Text('المركز 11 — خارج الجوائز',
              style:TextStyle(color:Colors.white)),
            subtitle:Text(result!=null&&result['rank']==11
              ? 'تم اختبار استبعاد المركز 11: صفر ماسة'
              : 'يُختبر عدم صرف ماسة خارج أول عشرة',
              style:const TextStyle(color:Colors.white70)))),
          if(!previous)...[
            DropdownButtonFormField<int>(
              value:selected,
              dropdownColor:navy,
              style:const TextStyle(color:gold),
              decoration:const InputDecoration(
                labelText:'اختيار مركز اختبارك',
                labelStyle:TextStyle(color:gold)),
              items:List.generate(11,(i)=>DropdownMenuItem(
                value:i+1,child:Text('المركز ${i+1}'))),
              onChanged:settled||busy?null:(i){
                if(i!=null)_act(()async{await lab.choose(i);});
              }),
            FilledButton(onPressed:settled||busy?null:
              ()=>_act(()async{await lab.settle(DateTime.now());}),
              child:Text(settled?'تم صرف جائزة هذا الأسبوع التجريبي':
                'إغلاق أسبوع الاختبار وصرف الجائزة')),
            OutlinedButton(
              onPressed:!settled||busy?null:
                ()=>_act(()async{await lab.next();}),
              child:const Text('بدء أسبوع تجريبي جديد (بدون تغيير التاريخ)')),
          ],
          if(result!=null)Text(
            'نتيجة أسبوع الاختبار: المركز ${result['rank']} '
            'مقابل ${result['diamonds']} ماسة تجريبية؛ '
            'إعادة الصرف لا تضيف مرة ثانية.',
            style:const TextStyle(color:gold),
            textAlign:TextAlign.center),
          if(error!=null)Text(error!,
            style:const TextStyle(color:Colors.redAccent)),
          TextButton(
            onPressed:busy?null:()=>_act(()async{await lab.reset();}),
            child:const Text('تصفير نتائج المختبر فقط — دون المساس بحسابك',
              style:TextStyle(color:Colors.white70))),
        ],
      )),
    );
  }
}
