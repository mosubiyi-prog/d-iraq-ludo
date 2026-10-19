import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_admin_compact_card.dart';
import 'package:d_iraq_ludo/deda_exclusive_ids_admin_page.dart';

void main() {
  testWidgets('exclusive manager tile uses same compact grid size and only custom palette',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var opened = false;
    await tester.pumpWidget(MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: GridView.count(
            crossAxisCount: 3,
            mainAxisExtent: 126,
            crossAxisSpacing: 8,
            padding: const EdgeInsets.all(16),
            children: [
              DedaAdminCompactCard(
                icon: Icons.verified_user_outlined,
                title: 'إدارة المعرّفات الحصرية',
                subtitle: 'حصرية للمدير العام',
                onTap: () => opened = true,
                exclusiveNavyTurquoise: true,
              ),
              DedaAdminCompactCard(
                icon: Icons.groups,
                title: 'إدارة الفريق',
                subtitle: 'الموظفون',
                onTap: () {},
              ),
            ],
          ),
        ),
      ),
    ));
    expect(tester.takeException(), isNull);
    final tiles = find.byType(DedaAdminCompactCard);
    expect(tiles, findsNWidgets(2));
    expect(tester.getSize(tiles.at(0)).height, tester.getSize(tiles.at(1)).height);
    expect(tester.getSize(tiles.at(0)).width, tester.getSize(tiles.at(1)).width);
    final inkList = tester.widgetList<Ink>(find.byType(Ink)).toList();
    final exclusive = inkList.first.decoration! as BoxDecoration;
    final standard = inkList.last.decoration! as BoxDecoration;
    final managerGradient = exclusive.gradient! as LinearGradient;
    final standardGradient = standard.gradient! as LinearGradient;
    expect(managerGradient.colors.first, const Color(0xFF169EA9));
    expect(managerGradient.colors.last, const Color(0xFF071D31));
    expect(standardGradient.colors.first, isNot(const Color(0xFF169EA9)));
    await tester.tap(tiles.first);
    expect(opened, isTrue);
  });

  test('exclusive catalog is an empty server bridge by default, never public APK data', () {
    expect(DedaExclusiveAdminBridge.readRemote, isNull);
    expect(DedaExclusiveAdminBridge.grantToUserRemote, isNull);
    expect(DedaExclusiveAdminBridge.useForManagerRemote, isNull);
  });
}
