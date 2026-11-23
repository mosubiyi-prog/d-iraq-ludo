import 'dart:async';
import 'package:flutter/material.dart';
import 'deda_exclusive_ids_admin_page.dart' show DedaExclusiveAdminBridge,
    DedaExclusiveAdminId, DedaExclusiveAdminSnapshot,
    DedaExclusiveAdminSnapshotVerifier;
import 'deda_verified_identifier_ink.dart';
import 'deda_stage2_isolated_admin_identity_2026_11_21.dart';

/// Stage2 private 100 exclusive IDs. Same owner-only catalog semantics,
/// but never uses public Firebase Auth or the default Functions client.
class DedaStage2IsolatedExclusiveIdsAdminPage extends StatefulWidget {
  final DedaIsolatedAdminIdentity admin;
  final String dedaPhone;
  final bool isArabic;
  const DedaStage2IsolatedExclusiveIdsAdminPage({
    super.key,required this.admin,required this.dedaPhone,
    required this.isArabic,
  });
  @override
  State<DedaStage2IsolatedExclusiveIdsAdminPage> createState() =>
      _DedaStage2IsolatedExclusiveIdsAdminPageState();
}
class _DedaStage2IsolatedExclusiveIdsAdminPageState
    extends State<DedaStage2IsolatedExclusiveIdsAdminPage> {
  static const _navy=Color(0xFF092B40), _turquoise=Color(0xFF1ED0C4),
      _background=Color(0xFFE7F2F3);
  static const _colors=<String>['gold','diamond','royal','pink'];
  final _draft=<String,String>{};
  final ValueNotifier<bool> _historyAccess=ValueNotifier<bool>(true);
  StreamSubscription<String?>? _adminSub, _publicSub;
  DedaExclusiveAdminSnapshot? _catalog;
  String? _adminUid, _publicUid, _message;
  bool _busy=false, _loading=false;
  int _generation=0;
  String t(String ar,String en) => widget.isArabic?ar:en;
  String colorName(String value) => switch(value) {
    'gold'=>t('ذهبي','Gold'), 'diamond'=>t('ماسي','Diamond'),
    'royal'=>t('ملكي','Royal'), 'pink'=>t('وردي','Pink'),
    _=>t('غير معروف','Unknown'),
  };
  Color ink(String value) => switch(value) {
    'gold'=>const Color(0xFF5A3510),
    'diamond'=>const Color(0xFF315775),
    'royal'=>const Color(0xFF542B73),
    'pink'=>const Color(0xFFB96387),
    _=>_navy,
  };
  String selected(DedaExclusiveAdminId item) =>
      item.permanentColor ?? _draft[item.identifier] ?? 'gold';

  void _checkUid() {
    if (!mounted || _catalog == null) return;
    if (widget.admin.scopedExclusiveAdminUid != _adminUid ||
        widget.admin.scopedExclusivePublicUid != _publicUid) {
      ++_generation;
      _historyAccess.value=false;
      setState(() {
        _catalog=null; _adminUid=null; _publicUid=null; _draft.clear();
        _message=t('تغيّرت الجلسة؛ يجب إعادة التحقق من الخادم.',
            'Session changed; fresh server proof required.');
      });
    }
  }
  @override
  void initState() {
    super.initState();
    _adminSub=widget.admin.watchScopedExclusiveAdminUid().listen(
        (_) => _checkUid());
    _publicSub=widget.admin.watchScopedExclusivePublicUid().listen(
        (_) => _checkUid());
    _refresh();
  }
  @override
  void dispose() {
    ++_generation;
    _adminSub?.cancel(); _publicSub?.cancel();
    _historyAccess.dispose();
    super.dispose();
  }
  Future<void> _refresh() async {
    if (_busy) return;
    final generation=++_generation;
    final adminUid=widget.admin.scopedExclusiveAdminUid;
    final publicUid=widget.admin.scopedExclusivePublicUid;
    _historyAccess.value=false;
    setState(() {
      _catalog=null; _adminUid=null; _publicUid=null;
      _draft.clear(); _loading=true; _message=null;
    });
    try {
      if (!dedaIsolatedAdminIdentityEnabled ||
          !DedaExclusiveAdminBridge.serverReadFlag) {
        throw StateError('exclusive100-read-server-not-deployed');
      }
      final result=await widget.admin.readScopedExclusive100(
          dedaPhone:widget.dedaPhone);
      if (!mounted || generation != _generation ||
          widget.admin.scopedExclusiveAdminUid != adminUid ||
          widget.admin.scopedExclusivePublicUid != publicUid ||
          !DedaExclusiveAdminSnapshotVerifier.isSafe(result)) { return; }
      setState(() {
        _catalog=result; _adminUid=adminUid; _publicUid=publicUid;
      });
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _message=t(
          'قائمة الـ100 الحصرية محمية حتى توفر الخادم الموثق '
          'وموافقة المدير العام. لم تُنشأ أسماء أو منح محلية.',
          'The private 100-ID catalog is locked until the verified '
          'server and owner approval. No local IDs or grants.',
        ));
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading=false);
      }
    }
  }
  Future<String?> _recipient() async {
    final controller=TextEditingController();
    try {
      return await showDialog<String>(context:context,
        builder:(ctx)=>AlertDialog(
          title:Text(t('معرّف المستلم الأصلي','Recipient original ID')),
          content:TextField(controller:controller,maxLength:18,
            textCapitalization:TextCapitalization.characters,
            decoration:InputDecoration(hintText:'@DEDA-XXXXXX',
              helperText:t('لا تستخدم رقم الهاتف أو UID',
                'Do not enter phone or Firebase UID'))),
          actions:[
            TextButton(onPressed:()=>Navigator.pop(ctx),
              child:Text(t('إلغاء','Cancel'))),
            TextButton(onPressed:(){
              final original=controller.text.trim().toUpperCase();
              if (DedaExclusiveAdminSnapshotVerifier.originalId
                  .hasMatch(original)) { Navigator.pop(ctx,original); }
            },child:Text(t('التالي','Next'))),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
  }
  Future<void> _act(DedaExclusiveAdminId item,{required bool gift}) async {
    if (_busy || _loading || !item.available || _catalog == null ||
        !DedaExclusiveAdminBridge.serverReadFlag ||
        !DedaExclusiveAdminBridge.serverActionsFlag ||
        widget.admin.scopedExclusiveAdminUid != _adminUid ||
        widget.admin.scopedExclusivePublicUid != _publicUid) { return; }
    final id=item.identifier;
    final color=selected(item);
    final recipient=gift?await _recipient():null;
    if (!mounted || (gift && recipient == null)) { return; }
    final title=t('تثبيت اللون نهائياً','Permanently lock color');
    final role=gift ? t('منح إلى','Gift to') : t('استخدام لنفسي','Self use');
    final chosen=colorName(color);
    final target=recipient ?? '';
    final warning=t('اللون والملكية لا يمكن تغييرهما بعد موافقة الخادم.',
        'Color and ownership cannot change after server confirmation.');
    final yes=await showDialog<bool>(context:context,
      builder:(ctx)=>AlertDialog(
        title:Text(title),
        content:Text('$id\n$chosen\n$role $target\n$warning'),
        actions:[
          TextButton(onPressed:()=>Navigator.pop(ctx,false),
            child:Text(t('إلغاء','Cancel'))),
          FilledButton(onPressed:()=>Navigator.pop(ctx,true),
            child:Text(t('تأكيد نهائي','Confirm permanently'))),
        ],
      ),
    );
    if (!mounted || yes != true || _busy) { return; }
    setState(()=>_busy=true);
    try {
      final fresh=await widget.admin.commitScopedExclusive100(
        dedaPhone:widget.dedaPhone,identifier:id,color:color,
        recipientOriginalId:recipient);
      if (!mounted || widget.admin.scopedExclusiveAdminUid != _adminUid ||
          widget.admin.scopedExclusivePublicUid != _publicUid) { return; }
      setState(()=>_catalog=fresh);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content:Text(t('تأكد المنح واللون والسجل من الخادم.',
            'Grant, color and receipt verified on server.'))));
    } catch (_) {
      if (mounted) { setState(() {
        _catalog=null; _draft.clear();
        _message=t('تعذر إثبات النتيجة. لا نعلن نجاح المنح '
          'أو فشله دون قراءة جديدة من الخادم.',
          'Result unverified. Re-read server state before claiming success.');
      }); }
    } finally {
      if (mounted) { setState(()=>_busy=false); }
    }
  }
  void _history() {
    final snap=_catalog;
    if (snap == null || widget.admin.scopedExclusiveAdminUid != _adminUid ||
        widget.admin.scopedExclusivePublicUid != _publicUid) { return; }
    _historyAccess.value=true;
    showModalBottomSheet<void>(context:context,
      isScrollControlled:true,showDragHandle:true,
      builder:(ctx)=>ValueListenableBuilder<bool>(
        valueListenable:_historyAccess,
        builder:(ctx,allowed,child)=>!allowed
          ? Center(child:Text(t('تغيّرت الجلسة؛ سجل المعرّفات محمي.',
              'Session changed; identifier history is hidden.')))
          : SafeArea(child:SizedBox(
        height:MediaQuery.sizeOf(ctx).height * .7,
        child:Column(children:[
          Text(t('📜 سجل المعرّفات الممنوحة','📜 Dated grant history'),
              style:Theme.of(ctx).textTheme.titleLarge),
          Expanded(child:snap.history.isEmpty
            ? Center(child:Text(t('لا يوجد منح موثق',
                'No verified grants')))
            : ListView.builder(itemCount:snap.history.length,
                itemBuilder:(ctx,i){
                  final row=snap.history[i];
                  final kind=row.kind == 'self_used'
                      ? t('استخدام المدير العام','Manager self-use')
                      : t('مُنح إلى','Gifted to');
                  final target=row.recipientOriginalId;
                  final date=row.grantedAt.toUtc().toIso8601String();
                  final color=colorName(row.color);
                  return ListTile(
                    leading:const Icon(Icons.history_edu),
                    title:DedaVerifiedIdentifierText(
                      identifier:row.identifier,serverConfirmed:true,
                      permanentColor:row.color,
                      style:const TextStyle(fontWeight:FontWeight.w900)),
                    subtitle:Text('$kind $target • $color\n$date'),
                  );
                })),
        ]),
      ))));
  }
  Widget _row(DedaExclusiveAdminId item) {
    final color=selected(item), available=item.available;
    final base=ink(color);
    final allowed=!_busy && !_loading &&
        DedaExclusiveAdminBridge.serverReadFlag &&
        DedaExclusiveAdminBridge.serverActionsFlag;
    final seq=item.sequence.toString().padLeft(3,'0');
    final recipient=item.ownerOriginalId ?? '';
    final chosen=colorName(color);
    return Card(
      key:ValueKey<String>('deda_stage2_exclusive_row_$seq'),
      margin:const EdgeInsets.symmetric(horizontal:12,vertical:5),
      child:Padding(padding:const EdgeInsets.all(12),
        child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
          Row(children:[
            Text('#$seq',style:const TextStyle(fontWeight:FontWeight.bold)),
            const Spacer(),
            Text(available?t('متاح للإدارة','Available'):
                t('🔒 لون مثبت مدى الحياة','🔒 Permanently locked')),
          ]),
          const SizedBox(height:7),
          Container(height:50,width:double.infinity,
            decoration:BoxDecoration(
              gradient:LinearGradient(colors:[
                base.withValues(alpha:.85),base,base.withValues(alpha:.92)]),
              borderRadius:BorderRadius.circular(13),
              border:Border.all(color:const Color(0xFFCFB77A),width:1.5),
            ),
            padding:const EdgeInsets.symmetric(horizontal:12),
            child:Row(children:[
              const Icon(Icons.diamond_outlined,color:Colors.white),
              const SizedBox(width:8),
              Expanded(child:FittedBox(fit:BoxFit.scaleDown,
                alignment:AlignmentDirectional.centerStart,
                child:Text(item.identifier,textDirection:TextDirection.ltr,
                  style:const TextStyle(fontSize:22,color:Colors.white,
                    fontWeight:FontWeight.w900)))),
              const Icon(Icons.workspace_premium,color:Colors.white),
            ])),
          if (available) ...[
            Wrap(spacing:5,children:[
              for (final choice in _colors) ChoiceChip(
                label:Text(colorName(choice)),selected:color == choice,
                onSelected:_busy?null:(_)=>
                    setState(()=>_draft[item.identifier]=choice)),
            ]),
            Wrap(spacing:8,children:[
              OutlinedButton.icon(
                onPressed:allowed?()=>_act(item,gift:false):null,
                icon:const Icon(Icons.person_outline),
                label:Text(t('استخدام لنفسي','Self use'))),
              FilledButton.icon(
                onPressed:allowed?()=>_act(item,gift:true):null,
                icon:const Icon(Icons.card_giftcard),
                label:Text(t('منح هدية','Gift ID'))),
            ]),
          ] else Text('${t('مثبت','Locked')}: $chosen • $recipient',
            style:const TextStyle(fontWeight:FontWeight.bold)),
        ])),
    );
  }
  @override
  Widget build(BuildContext context) {
    final snap=_catalog;
    final available=snap?.identifiers.where((row)=>row.available).length ?? 0;
    final availableLabel=t('المتاحة','Available');
    return ColoredBox(color:_background,child:Column(children:[
      Container(margin:const EdgeInsets.all(12),
        padding:const EdgeInsets.all(12),
        decoration:BoxDecoration(
          gradient:const LinearGradient(colors:[
            _navy,Color(0xFF125D67),_turquoise]),
          borderRadius:BorderRadius.circular(20)),
        child:Column(children:[
          Align(alignment:Alignment.topLeft,child:IconButton(
            key:const Key('deda_stage2_exclusive_grant_log_top_left'),
            onPressed:snap==null?null:_history,
            icon:const Icon(Icons.history_edu,color:Colors.white))),
          Text(t('الـ100 معرّف الحصرية','100 exclusive identifiers'),
            style:const TextStyle(color:Colors.white,
                fontWeight:FontWeight.bold,fontSize:18)),
          Text(snap==null
            ? t('لا تُعرض أسماء دون إثبات الخادم',
              'No catalog without verified server proof')
            : '100 / 100',
            style:const TextStyle(color:Colors.white)),
          if (snap != null)
            Text('$availableLabel: $available',
              style:const TextStyle(color:Colors.white)),
        ])),
      if (_loading) const LinearProgressIndicator(),
      Expanded(child:snap==null
        ? Center(child:Padding(padding:const EdgeInsets.all(20),
          child:Column(mainAxisSize:MainAxisSize.min,children:[
            const Icon(Icons.lock_outline,size:38,color:_navy),
            const SizedBox(height:10),
            Text(_message ?? t('جارٍ التحقق','Verifying server catalog'),
                textAlign:TextAlign.center),
            OutlinedButton(onPressed:_busy?null:_refresh,
                child:Text(t('إعادة المحاولة','Retry'))),
          ])))
        : RefreshIndicator(onRefresh:_refresh,child:ListView.builder(
          itemCount:snap.identifiers.length,
          itemBuilder:(ctx,i)=>_row(snap.identifiers[i])))),
    ]));
  }
}
