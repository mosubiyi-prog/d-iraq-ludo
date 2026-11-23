import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'deda_stage2_isolated_admin_identity_2026_11_21.dart';
import 'deda_admin_task_drafts.dart' show DedaAdminTaskDraft;
import 'deda_daily_task_slots.dart';
import 'deda_daily_login_offer_preview_page.dart';
import 'deda_daily_schedule_policy.dart';

/// Same original admin task categories, entirely on secondary Auth.
/// Private task previews do not activate user tasks or spend rewards.
class DedaStage2IsolatedTasksAdminPage extends StatefulWidget {
  const DedaStage2IsolatedTasksAdminPage({
    super.key,required this.admin,required this.dedaPhone,
    required this.isArabic});
  final DedaIsolatedAdminIdentity admin;
  final String dedaPhone;
  final bool isArabic;
  @override
  State<DedaStage2IsolatedTasksAdminPage> createState() =>
      _DedaStage2IsolatedTasksAdminPageState();
}

class _DedaStage2IsolatedTasksAdminPageState
    extends State<DedaStage2IsolatedTasksAdminPage> {
  late Future<Map<String,dynamic>> _data;
  bool _busy=false;
  String t(String ar,String en)=>widget.isArabic?ar:en;
  @override void initState(){super.initState();_refresh();}
  void _refresh()=>_data=widget.admin.readScopedTaskManagement(
    dedaPhone:widget.dedaPhone);
  Future<void> _run(Future<void> Function() action) async {
    if(_busy)return;
    setState(()=>_busy=true);
    try {
      await action();
      if(!mounted)return;
      setState(_refresh);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(t(
        'تم حفظ التغيير الإداري فقط. مهام المستخدمين ومكافآتهم لم تتغير.',
        'Admin-only change saved. User tasks and rewards unchanged.'))));
    }catch(_){
      if(mounted){
        setState(_refresh);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(t(
          'تعذر الإجراء؛ تحقق من صلاحية المدير أو تغيّر البيانات على الخادم.',
          'Denied: verify manager rights and current server records.'))));
      }
    }finally{if(mounted)setState(()=>_busy=false);}
  }
  Future<void> _edit(DedaDailyTaskSlot slot,Map<String,dynamic>? old) async {
    final draft=await showDialog<DedaAdminTaskDraft>(
      context:context,builder:(_)=>_DedaStage2DailyDraftDialog(
        isArabic:widget.isArabic,slot:slot,previous:old));
    if(draft==null)return;
    await _run(()=>widget.admin.saveScopedDailyTaskDraft(
      dedaPhone:widget.dedaPhone,dailySlotId:slot.id,draft:draft));
  }
  Widget _taskCard(DedaDailyTaskSlot slot,
      Map<String,dynamic>? draft,Map<String,dynamic>? preview) {
    final status=(preview?['status']??'').toString();
    final pending=status==DedaDailySchedulePolicy.pending;
    final title=(draft?['titleAr']??slot.titleAr).toString();
    return Card(
      color:Colors.white,
      margin:const EdgeInsets.only(bottom:9),
      shape:RoundedRectangleBorder(
        borderRadius:BorderRadius.circular(17),
        side:BorderSide(color:draft==null
          ?const Color(0xFFE0E4DC):const Color(0xFFAEC6B3))),
      child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        ListTile(
          leading:const Icon(Icons.edit_note_rounded,
            color:Color(0xFF1B6A44),size:28),
          title:Text(title,style:const TextStyle(fontWeight:FontWeight.w900)),
          subtitle:Text(slot.subtitleAr+'\n'+(pending
            ?t('موعد تجريبي محفوظ — غير منشور','Private preview — not published')
            :draft!=null?t('مسودة إدارية — غير منشورة','Private draft — not published')
             :t('المهمة الأصلية كما هي','Original task unchanged'))),
          trailing:const Icon(Icons.edit_outlined),
          onTap:_busy?null:()=>_edit(slot,draft),
        ),
        Padding(padding:const EdgeInsetsDirectional.fromSTEB(12,0,12,10),
          child:Wrap(spacing:8,runSpacing:5,children:[
            if(draft!=null) OutlinedButton.icon(
              onPressed:_busy?null:()=>_run(()=>widget.admin
                .prepareScopedDailyTaskPreview(
                  dedaPhone:widget.dedaPhone,dailySlotId:slot.id)),
              icon:const Icon(Icons.schedule,size:17),
              label:Text(t('جدولة تجريبية','Preview schedule'))),
            if(pending) TextButton.icon(
              onPressed:_busy?null:()=>_run(()=>widget.admin
                .cancelScopedDailyTaskPreview(
                  dedaPhone:widget.dedaPhone,dailySlotId:slot.id)),
              icon:const Icon(Icons.undo,size:17),
              label:Text(t('إلغاء الموعد','Cancel preview'))),
          ])),
      ]));
  }

  @override Widget build(BuildContext context) {
    if(!dedaIsolatedAdminIdentityEnabled) {
      return const Scaffold(body:Center(child:Text('Tasks stage disabled')));
    }
    return Scaffold(
      backgroundColor:const Color(0xFFF8FAF2),
      appBar:AppBar(
        title:Text(t('إدارة المهام والمكافآت','Tasks and rewards')),
        actions:[IconButton(
          onPressed:_busy?null:()=>setState(_refresh),
          icon:const Icon(Icons.refresh))]),
      body:FutureBuilder<Map<String,dynamic>>(
        future:_data,builder:(context,snap){
          if(snap.hasError)return Center(child:Text(t(
            'تعذرت قراءة المسودات من الحساب الإداري المعزول.',
            'Cannot verify isolated administrator task data.')));
          if(!snap.hasData){
            return const Center(child:CircularProgressIndicator());
          }
          final data=snap.data!;
          final drafts=<String,Map<String,dynamic>>{
            for(final raw in data['drafts'] as List)
              if(raw is Map && raw['id'] is String)
                raw['id'] as String:Map<String,dynamic>.from(raw),
          };
          final previews=<String,Map<String,dynamic>>{
            for(final raw in data['previews'] as List)
              if(raw is Map && raw['slotId'] is String)
                raw['slotId'] as String:Map<String,dynamic>.from(raw),
          };
          final legacyCount=drafts.keys.where(
            (id)=>!DedaDailyTaskSlot.slots.any((s)=>s.draftId==id)).length;
          final social=Map<String,dynamic>.from(
            data['social'] as Map<String,dynamic>);
          return ListView(padding:const EdgeInsets.all(12),children:[
            Container(
              padding:const EdgeInsets.all(13),
              decoration:BoxDecoration(color:const Color(0xFFE8F0E7),
                borderRadius:BorderRadius.circular(15)),
              child:Text(t(
                'نفس المهام الثمانية. التعديلات مسودات خاصة بالإدارة فقط، مو نشر أو صرف مكافآت.',
                'Same eight tasks. Changes are private drafts, never payout or publication.'),
                style:const TextStyle(fontWeight:FontWeight.w700,height:1.5))),
            const SizedBox(height:10),
            Card(color:const Color(0xFF0B3156),child:ListTile(
              leading:const Icon(Icons.calendar_month,
                color:Color(0xFFFFD76A)),
              title:const Text(DedaDailyTaskSlot.loginTitleAr,
                style:TextStyle(color:Colors.white,fontWeight:FontWeight.bold)),
              subtitle:Text(t('10 نقاط ثابتة — معاينة عروض المناسبات فقط',
                'Fixed 10 points — local offer preview only'),
                style:const TextStyle(color:Color(0xFFE2EAF4))),
              trailing:const Icon(Icons.visibility_outlined,
                color:Color(0xFFFFD76A)),
              onTap:()=>Navigator.of(context).push(MaterialPageRoute(
                builder:(_)=>DedaDailyLoginOfferPreviewPage(
                  isArabic:widget.isArabic))),
            )),
            Card(color:const Color(0xFF0B3156),child:ListTile(
              leading:const Icon(Icons.people_alt_rounded,
                color:Color(0xFFFFD76A)),
              title:Text(t('مهام التواصل الاجتماعي','Social tasks'),
                style:const TextStyle(color:Color(0xFFFFD76A),
                  fontWeight:FontWeight.w900)),
              subtitle:Text(t('تيليجرام: مسودة وجدولة بلا مكافآت؛ بقية المنصات معاينة فقط',
                  'Telegram draft and schedule without payouts; others preview only'),
                style:const TextStyle(color:Colors.white)),
              trailing:const Icon(Icons.chevron_left,
                color:Color(0xFFFFD76A)),
              onTap:_busy?null:()=>Navigator.of(context).push(MaterialPageRoute(
                builder:(_)=>DedaStage2IsolatedSocialTasksPage(
                  admin:widget.admin,dedaPhone:widget.dedaPhone,
                  isArabic:widget.isArabic,initial:social,
                ))).then((_)=>setState(_refresh)),
            )),
            const SizedBox(height:10),
            Text(t('المهام اليومية','Daily tasks'),
              style:const TextStyle(fontSize:19,fontWeight:FontWeight.w900)),
            const SizedBox(height:9),
            for(final slot in DedaDailyTaskSlot.slots)
              _taskCard(slot,drafts[slot.draftId],previews[slot.id]),
            if(legacyCount>0)Padding(
              padding:const EdgeInsets.all(8),
              child:Text(t('المسودات القديمة محفوظة ولم تُحذف.',
                'Old draft records are preserved.'))),
            const SizedBox(height:12),
            Text(t('لا نشر تلقائي ولا إضافة نقاط أو ماسات من هذه البطاقة.',
              'No automatic publication or points/diamonds granted here.'),
              style:const TextStyle(color:Color(0xFF6A542D))),
          ]);
        }),
    );
  }
}

class _DedaStage2DailyDraftDialog extends StatefulWidget {
  const _DedaStage2DailyDraftDialog({required this.isArabic,
    required this.slot,this.previous});
  final bool isArabic;
  final DedaDailyTaskSlot slot;
  final Map<String,dynamic>? previous;
  @override State<_DedaStage2DailyDraftDialog> createState()=>
    _DedaStage2DailyDraftDialogState();
}
class _DedaStage2DailyDraftDialogState
    extends State<_DedaStage2DailyDraftDialog> {
  final form=GlobalKey<FormState>();
  late final TextEditingController title,count,amount,url;
  late String action,unit;
  String t(String ar,String en)=>widget.isArabic?ar:en;
  @override void initState(){
    super.initState();
    final p=widget.previous;
    action=(p?['action']??widget.slot.action).toString();
    unit=(p?['rewardUnit']??'points').toString();
    title=TextEditingController(text:(p?['titleAr']??widget.slot.titleAr).toString());
    count=TextEditingController(text:(p?['targetCount']??1).toString());
    amount=TextEditingController(text:(p?['rewardAmount']??5).toString());
    url=TextEditingController(text:(p?['url']??'').toString());
  }
  @override void dispose(){title.dispose();count.dispose();amount.dispose();url.dispose();super.dispose();}
  InputDecoration deco(String name)=>InputDecoration(
    labelText:name,border:const OutlineInputBorder());
  Widget numeric(TextEditingController c,String name,int max)=>
    TextFormField(controller:c,decoration:deco(name),
      keyboardType:TextInputType.number,
      validator:(v){final n=int.tryParse((v??'').trim());
        return n==null||n<1||n>max?t('عدد غير صحيح','Invalid number'):null;});
  @override Widget build(BuildContext context)=>AlertDialog(
    title:Text(t('تعديل المهمة','Edit task')),
    content:SizedBox(width:420,child:SingleChildScrollView(child:Form(
      key:form,child:Column(mainAxisSize:MainAxisSize.min,children:[
        DropdownButtonFormField<String>(initialValue:action,
          isExpanded:true,decoration:deco(t('نوع المهمة','Task action')),
          items:[for(final key in DedaAdminTaskDraft.actions)
            DropdownMenuItem(value:key,child:Text(
              DedaAdminTaskDraft.actionTitle(key,widget.isArabic)))],
          onChanged:(v)=>setState(()=>action=v??action)),
        TextFormField(controller:title,
          decoration:deco(t('عنوان المهمة','Task title')),maxLength:80,
          validator:(v)=>(v?.trim().length??0)<3?t('عنوان غير صحيح','Invalid title'):null),
        numeric(count,t('عدد المرات','Target count'),100),
        DropdownButtonFormField<String>(initialValue:unit,
          decoration:deco(t('نوع المكافأة','Reward type')),
          items:[DropdownMenuItem(value:'points',child:Text(t('نقاط','Points'))),
            DropdownMenuItem(value:'diamonds',child:Text(t('ماسات','Diamonds')))],
          onChanged:(v)=>setState(()=>unit=v??unit)),
        numeric(amount,t('قيمة المكافأة','Reward amount'),5000),
        if(action=='visit_telegram')TextFormField(controller:url,
          decoration:deco(t('رابط تليجرام','Telegram URL'))),
        Text(t('مسودة فقط — لن تُصرف مكافآت للمستخدمين.',
          'Draft only; no rewards will be paid.')),
      ])))),
    actions:[
      TextButton(onPressed:()=>Navigator.pop(context),
        child:Text(t('إلغاء','Cancel'))),
      FilledButton(onPressed:(){
        if(!(form.currentState?.validate()??false))return;
        final p=widget.previous;
        final draft=DedaAdminTaskDraft(
          id:(p?['id']??'').toString(),
          revision:(p?['revision'] as int?)??0,
          cycle:'daily',action:action,
          titleAr:title.text,titleEn:title.text.trim(),
          targetCount:int.parse(count.text.trim()),
          rewardUnit:unit,rewardAmount:int.parse(amount.text.trim()),
          url:action=='visit_telegram'?url.text.trim():'',
        );
        try{draft.validate();Navigator.pop(context,draft);}
        catch(_){ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:Text(t('راجع بيانات المهمة','Check draft fields'))));}
      },child:Text(t('حفظ المسودة','Save draft'))),
    ],
  );
}

/// Social manager page: same approved Telegram-only live backend contract,
/// always uses the named secondary app via the isolation service.
class DedaStage2IsolatedSocialTasksPage extends StatefulWidget {
  const DedaStage2IsolatedSocialTasksPage({
    super.key,required this.admin,required this.dedaPhone,
    required this.isArabic,required this.initial});
  final DedaIsolatedAdminIdentity admin;
  final String dedaPhone;
  final bool isArabic;
  final Map<String,dynamic> initial;
  @override State<DedaStage2IsolatedSocialTasksPage> createState()=>
    _DedaStage2IsolatedSocialTasksPageState();
}
class _DedaStage2IsolatedSocialTasksPageState
    extends State<DedaStage2IsolatedSocialTasksPage> {
  late final TextEditingController title,url,amount;
  late String unit;
  late bool doubleWithAd;
  late int revision;
  late String status;
  DateTime? date;
  bool busy=false;
  String t(String ar,String en)=>widget.isArabic?ar:en;
  @override void initState(){
    super.initState();
    title=TextEditingController(text:(widget.initial['title']??'').toString());
    url=TextEditingController(text:(widget.initial['url']??'').toString());
    amount=TextEditingController(text:(widget.initial['rewardAmount']??5).toString());
    unit=(widget.initial['rewardUnit']??'points').toString();
    if(!const {'points','coins','diamonds'}.contains(unit))unit='points';
    doubleWithAd=widget.initial['doubleWithRewardedAd']==true;
    revision=(widget.initial['revision'] as int?)??0;
    status=(widget.initial['status']??'new').toString();
  }
  @override void dispose(){title.dispose();url.dispose();amount.dispose();super.dispose();}
  Future<void> run(Future<void> Function() f) async {
    if(busy)return;
    setState(()=>busy=true);
    try {
      await f();
      final snap=await widget.admin.readScopedTaskManagement(
        dedaPhone:widget.dedaPhone);
      final social=Map<String,dynamic>.from(
        snap['social'] as Map<String,dynamic>);
      if(!mounted)return;
      setState((){
        revision=(social['revision'] as int?)??revision;
        status=(social['status']??status).toString();
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(t(
        'حُفظت العملية بدون صرف مكافآت.',
        'Saved without reward payout.'))));
    }catch(_){
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content:Text(t('رفض الخادم الإجراء أو تغيّرت الصلاحية.',
          'Server denied operation or session changed.'))));
    }finally{if(mounted)setState(()=>busy=false);}
  }
  Future<void> chooseDate() async {
    final now=DateTime.now().toUtc().add(const Duration(hours:3));
    final tomorrow=DateTime(now.year,now.month,now.day+1);
    final selected=await showDatePicker(
      context:context,initialDate:date??tomorrow,
      firstDate:tomorrow,lastDate:tomorrow.add(const Duration(days:30)));
    if(selected!=null && mounted)setState(()=>date=selected);
  }
  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:Text(t('مهام التواصل الاجتماعي','Social tasks'))),
    body:ListView(padding:const EdgeInsets.all(14),children:[
      Card(color:const Color(0xFF0B3156),
        child:Padding(padding:const EdgeInsets.all(14),
          child:Text(t(
            'فيسبوك • تليجرام • يوتيوب • إنستغرام • تيك توك • أخرى\n'
            'المعاينة تشمل جميع المنصات، والحفظ والجدولة الفعليان لتليجرام فقط.',
            'Facebook • Telegram • YouTube • Instagram • TikTok • Other\n'
            'Preview all platforms; only Telegram may be drafted/scheduled.'),
            style:const TextStyle(color:Colors.white,height:1.5)))),
      const SizedBox(height:12),
      Text(t('الحالة الحالية: ','Current status: ')+status),
      const SizedBox(height:8),
      TextField(controller:title,decoration:InputDecoration(
        labelText:t('عنوان المهمة','Task title'),
        border:const OutlineInputBorder())),
      const SizedBox(height:8),
      TextField(controller:url,decoration:InputDecoration(
        labelText:t('رابط قناة تيليجرام','Telegram channel URL'),
        border:const OutlineInputBorder())),
      const SizedBox(height:8),
      DropdownButtonFormField<String>(initialValue:unit,
        decoration:InputDecoration(labelText:t('نوع المكافأة','Reward unit')),
        items:[
          DropdownMenuItem(value:'points',child:Text(t('نقاط','Points'))),
          DropdownMenuItem(value:'coins',child:Text(t('عملات','Coins'))),
          DropdownMenuItem(value:'diamonds',child:Text(t('ماسات','Diamonds'))),
        ],onChanged:(v)=>setState(()=>unit=v??unit)),
      TextField(controller:amount,keyboardType:TextInputType.number,
        decoration:InputDecoration(
          labelText:t('القيمة المعروضة (لا تُصرف)','Preview amount (not granted)'),
          border:const OutlineInputBorder())),
      CheckboxListTile(value:doubleWithAd,
        onChanged:(v)=>setState(()=>doubleWithAd=v==true),
        title:Text(t('مضاعفة شكلية بإعلان — بلا منح','Simulate ad doubling — no grant'))),
      const SizedBox(height:8),
      Wrap(spacing:8,runSpacing:8,children:[
        FilledButton(
          onPressed:busy?null:()=>run(()=>widget.admin.saveScopedSocialTaskDraft(
            dedaPhone:widget.dedaPhone,expectedRevision:revision,
            title:title.text,url:url.text,rewardUnit:unit,
            rewardAmount:int.tryParse(amount.text.trim())??0,
            doubleWithAd:doubleWithAd)),
          child:Text(t('حفظ مسودة','Save draft'))),
        OutlinedButton(onPressed:busy||status!='draft'?null:chooseDate,
          child:Text(date==null?t('اختيار يوم','Select day'):
            date!.year.toString()+'-'+date!.month.toString()+'-'+date!.day.toString())),
        OutlinedButton(
          onPressed:busy||status!='draft'||date==null?null:()=>run(()=>
            widget.admin.scheduleScopedSocialTask(
              dedaPhone:widget.dedaPhone,
              expectedRevision:revision,calendarDay:date!)),
          child:Text(t('جدولة بلا مكافآت','Schedule without payouts'))),
        OutlinedButton(
          onPressed:busy||status!='scheduled'?null:()=>run(()=>
            widget.admin.cancelScopedSocialTask(
              dedaPhone:widget.dedaPhone,expectedRevision:revision)),
          child:Text(t('إلغاء الجدولة','Cancel schedule'))),
      ]),
      const SizedBox(height:12),
      Text(t(
        'الجوائز الموثوقة وتفعيل بوت تيليجرام ليسا جزءاً من هذه الخطوة. '
        'هذه العمليات محجوبة عن حساب المستخدم الأصلي.',
        'Trusted rewards and Telegram bot activation are excluded. '
        'The public user account is never used for these operations.')),
    ]),
  );
}
