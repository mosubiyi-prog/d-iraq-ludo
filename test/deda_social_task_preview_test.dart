import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:deda_guide/deda_social_task_preview.dart';
import 'package:deda_guide/deda_admin_social_task_preview_page.dart';

void main() {
  test('platform selection is the six user-approved options in order', () {
    expect(DedaSocialTaskCatalog.platforms, <String>[
      'facebook', 'telegram', 'youtube',
      'instagram', 'tiktok', 'other',
    ]);
    expect(DedaSocialTaskCatalog.platformLabel('facebook', true),
        'صفحة فيس بوك');
    expect(DedaSocialTaskCatalog.platformLabel('other', true), 'أخرى');
  });

  test('social interaction includes post likes and video likes', () {
    expect(DedaSocialTaskCatalog.actions, containsAll(<String>[
      'follow', 'like_post', 'watch_video', 'like_video', 'other',
    ]));
    expect(DedaSocialTaskCatalog.actionLabel('like_post', true),
        'إعجاب بمنشور');
    expect(DedaSocialTaskCatalog.actionLabel('like_video', true),
        'إعجاب بفيديو');
  });

  test('social card hidden unless internal build enables preview', () {
    expect(DedaSocialTaskPreview.visible, isFalse);
  });

  testWidgets('compact card is below 94dp and responds to view tap',
      (tester) async {
    var opened = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 350,
            child: DedaSocialTaskCompactCard(
              isArabic: true, onTap: () => opened++,
            ),
          ),
        ),
      ),
    ));
    expect(find.byKey(const Key('socialTaskCardTitle')), findsOneWidget);
    final rect = tester.getRect(find.byKey(const Key('socialTaskCompactCard')));
    expect(rect.height, lessThan(94));
    await tester.tap(find.byKey(const Key('socialTaskCardOpen')));
    expect(opened, 1);
  });

  testWidgets('manager editor begins with platform selector', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: DedaAdminSocialTaskPreviewPage(isArabic: true),
    ));
    expect(find.byKey(const Key('socialPlatformDropdown')), findsOneWidget);
    expect(find.text('صفحة فيس بوك'), findsOneWidget);
    expect(find.byKey(const Key('socialActionDropdown')), findsOneWidget);
    expect(find.byKey(const Key('socialAdminPreviewOnly')), findsOneWidget);
  });
}
