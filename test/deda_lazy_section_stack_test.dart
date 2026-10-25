import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/deda_lazy_section_stack.dart';

class Probe extends StatefulWidget {
  const Probe(this.id, this.started, this.disposed, {super.key, this.label = ''});
  final int id;
  final List<int> started, disposed;
  final String label;
  @override
  State<Probe> createState() => ProbeState();
}
class ProbeState extends State<Probe> {
  int count = 0;
  @override
  void initState() { super.initState(); widget.started.add(widget.id); }
  @override
  void dispose() { widget.disposed.add(widget.id); super.dispose(); }
  @override
  Widget build(BuildContext context) => TextButton(
    key: ValueKey('button-${widget.id}'),
    onPressed: () => setState(() => count++),
    child: Text('${widget.id}:${widget.label}:$count'),
  );
}
Widget shell(int index, List<int> started, List<int> disposed,
    {bool enabled = true, String label = ''}) => MaterialApp(
  home: Scaffold(body: DedaLazySectionStack(
    index: index, enabled: enabled,
    children: List<Widget>.generate(5, (id) => Probe(id, started, disposed, label: label)),
  )),
);
void main() {
  testWidgets('entry mounts only the visible one of five sections', (tester) async {
    final started = <int>[], disposed = <int>[];
    await tester.pumpWidget(shell(0, started, disposed));
    expect(started, [0]); expect(disposed, isEmpty);
    expect(find.byType(Probe, skipOffstage: false), findsOneWidget);
  });
  testWidgets('disabled review path mounts all five as the original stack did', (tester) async {
    final started = <int>[], disposed = <int>[];
    await tester.pumpWidget(shell(0, started, disposed, enabled: false));
    expect(started, [0, 1, 2, 3, 4]);
    expect(find.byType(Probe, skipOffstage: false), findsNWidgets(5));
  });
  testWidgets('first visit starts exactly that section and a second visit preserves its state', (tester) async {
    final started = <int>[], disposed = <int>[];
    await tester.pumpWidget(shell(0, started, disposed));
    await tester.pumpWidget(shell(3, started, disposed));
    await tester.tap(find.byKey(const ValueKey('button-3'))); await tester.pump();
    expect(find.text('3::1'), findsOneWidget);
    await tester.pumpWidget(shell(0, started, disposed));
    await tester.pumpWidget(shell(3, started, disposed));
    expect(started, [0, 3]); expect(disposed, isEmpty);
    expect(find.text('3::1'), findsOneWidget);
  });
  testWidgets('parent rebuild updates visited child inputs without starting unseen sections', (tester) async {
    final started = <int>[], disposed = <int>[];
    await tester.pumpWidget(shell(0, started, disposed, label: 'old'));
    await tester.pumpWidget(shell(0, started, disposed, label: 'new'));
    expect(find.text('0:new:0'), findsOneWidget); expect(started, [0]);
  });
  testWidgets('direct jump to requests does not mount friends, add-friend or style', (tester) async {
    final started = <int>[], disposed = <int>[];
    await tester.pumpWidget(shell(0, started, disposed));
    await tester.pumpWidget(shell(2, started, disposed));
    expect(started, [0, 2]); expect(find.text('2::0'), findsOneWidget);
  });
  testWidgets('dispose tears down visited sections and never starts hidden work', (tester) async {
    final started = <int>[], disposed = <int>[];
    await tester.pumpWidget(shell(0, started, disposed));
    await tester.pumpWidget(shell(4, started, disposed));
    await tester.pumpWidget(const SizedBox.shrink());
    expect(started, [0, 4]); expect(disposed.toSet(), {0, 4});
  });
  testWidgets('switching the review flag preserves already mounted sections', (tester) async {
    final started = <int>[], disposed = <int>[];
    await tester.pumpWidget(shell(0, started, disposed));
    await tester.pumpWidget(shell(1, started, disposed, enabled: false));
    await tester.pumpWidget(shell(0, started, disposed));
    expect(started.toSet(), {0, 1, 2, 3, 4}); expect(started.length, 5); expect(disposed, isEmpty);
  });
  testWidgets('fresh section host starts fresh state after it was closed', (tester) async {
    final started = <int>[], disposed = <int>[];
    await tester.pumpWidget(shell(0, started, disposed));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(shell(0, started, disposed));
    expect(started, [0, 0]); expect(disposed, [0]);
  });
}
