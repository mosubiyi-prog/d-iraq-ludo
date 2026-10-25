import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lib/main.dart' as app;
import '../lib/deda_section_state.dart';
import '../lib/deda_section_operation_context.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    app.DedaPreferences.phone='07700000000';
    app.DedaPreferences.isLoggedIn=true;
  });
  testWidgets('stateless boundary removes old-account controls and cancels its stream', (tester) async {
    var cancellations=0;
    final source=StreamController<int>();source.onCancel=() {cancellations++;};
    debugPrint('section-boundary: mount');
    await tester.pumpWidget(MaterialApp(home:DedaSectionBoundary(builder:(context) =>
      StreamBuilder<int>(stream:source.stream,builder:(context,snapshot) =>
        FilledButton(onPressed:(){},child:Text('account-a-${snapshot.data ?? 0}'))))));
    debugPrint('section-boundary: mounted');
    source.add(7);await tester.pump();expect(find.text('account-a-7'),findsOneWidget);
    debugPrint('section-boundary: first value');
    app.DedaPreferences.phone='07700000001';DedaSectionAccountChanges.changed();
    await tester.pump();await tester.pump();
    debugPrint('section-boundary: account invalidated');
    expect(find.byType(FilledButton),findsNothing);expect(cancellations,1);
    expect(find.text('تغيّر الحساب. ارجع وافتح هذا القسم من جديد.'),findsOneWidget);
    source.add(9);await tester.pump();expect(find.text('account-a-9'),findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    debugPrint('section-boundary: disposed');
    final closed=source.close();await tester.pump();await closed;
    debugPrint('section-boundary: closed');
    expect(tester.takeException(),isNull);
  });
  testWidgets('expired confirmation cannot perform a stateless administrative action', (tester) async {
    final confirmation=Completer<bool>();var writes=0;
    await tester.pumpWidget(MaterialApp(home:DedaSectionBoundary(builder:(context) =>
      FilledButton(onPressed:() => DedaSectionBoundary.runVoidForContext(context,() async {
        final confirmed=await DedaSectionOperationContext.wait(() => confirmation.future);
        if(confirmed) writes++;
      }),child:const Text('confirm')))));
    await tester.tap(find.text('confirm'));await tester.pump();
    app.DedaPreferences.phone='07700000001';DedaSectionAccountChanges.changed();
    await tester.pump();confirmation.complete(true);await tester.pump();
    expect(writes,0);expect(tester.takeException(),isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('same-account confirmation keeps the original single action', (tester) async {
    var writes=0;
    await tester.pumpWidget(MaterialApp(home:DedaSectionBoundary(builder:(context) =>
      FilledButton(onPressed:() => DedaSectionBoundary.runVoidForContext(context,() async {
        await DedaSectionOperationContext.wait(() async => true);writes++;
      }),child:const Text('confirm')))));
    await tester.tap(find.text('confirm'));await tester.pump();
    expect(writes,1);expect(tester.takeException(),isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('an actual saved-places page is bound to the account that opened it', (tester) async {
    await tester.pumpWidget(const MaterialApp(home:app.SavedPlacesPage(showFavorites:true)));
    await tester.pumpAndSettle();
    app.DedaPreferences.phone='07700000001';DedaSectionAccountChanges.changed();
    await tester.pump();
    expect(find.text('تغيّر الحساب. ارجع وافتح هذا القسم من جديد.'),findsOneWidget);
    expect(tester.takeException(),isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('disposed boundary rejects an old captured callback without writes', (tester) async {
    VoidCallback? saved;var writes=0;
    await tester.pumpWidget(MaterialApp(home:DedaSectionBoundary(builder:(context) {
      saved=() {unawaited(DedaSectionBoundary.runVoidForContext(context,() async {writes++;}));};
      return const Text('old');
    })));
    await tester.pumpWidget(const SizedBox.shrink());saved!();await tester.pump();
    expect(writes,0);expect(tester.takeException(),isNull);
  });
  for(final change in ['none','account','dispose']) {
    testWidgets('reward callback outside the UI zone preserves its owner: $change', (tester) async {
      late void Function(Object,Object) reward;
      final hold=Completer<void>();Future<void>? claim;var writes=0;
      await tester.pumpWidget(MaterialApp(home:_RewardProbe(
        ready:(callback)=>reward=callback,
        claim:() {claim=() async {
          await DedaSectionOperationContext.wait(() => hold.future);writes++;
        }();},
      )));
      reward(Object(),Object());await tester.pump();expect(claim,isNotNull);
      Future<void>? assertion;
      if(change!='none') {
        assertion=expectLater(claim!,throwsA(isA<DedaSectionOperationExpired>()));
        if(change=='account') {
          app.DedaPreferences.phone='07700000001';DedaSectionAccountChanges.changed();
        } else { await tester.pumpWidget(const SizedBox.shrink()); }
      }
      hold.complete();await tester.pump();
      if(assertion!=null) {await assertion;} else {await claim;}
      expect(writes,change=='none'?1:0);expect(tester.takeException(),isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}

class _RewardProbe extends StatefulWidget {
  const _RewardProbe({required this.ready,required this.claim});
  final void Function(void Function(Object,Object)) ready;
  final VoidCallback claim;
  @override
  State<_RewardProbe> createState()=>_RewardProbeState();
}
class _RewardProbeState extends State<_RewardProbe> with DedaSectionState<_RewardProbe> {
  @override
  void initState() {
    super.initState();
    widget.ready(dedaSectionCallback2<Object,Object>((ad,reward) {widget.claim();}));
  }
  @override
  Widget build(BuildContext context)=>dedaSectionCurrent?const Text('reward'):dedaSectionExpiredView();
}
