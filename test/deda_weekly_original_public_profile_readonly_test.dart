import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/deda_social_service.dart';
import '../lib/deda_weekly_competitor_public_card.dart';
import '../lib/deda_weekly_original_public_profile_readonly.dart';

void main() {
  const competitor = DedaWeeklyPublicCompetitor(
    participantId: 'verified-participant-0012',
    originalPublicId: '@DEDA-ABC123',
    activePublicId: '@DEDA-AAAA',
    displayName: 'المتصدر الثاني',
    rankVerified: true,
    publicOwnerVerified: true,
    equippedAppearanceVerified: true,
    avatarStyle: 2,
    equippedFrameStyle: 3,
  );
  const public = DedaSocialProfile(
    publicId: '@DEDA-ABC123',
    ownerUid: 'target-real-public-profile-owner',
    displayName: 'المتصدر الثاني',
    avatarStyle: 2,
    frameStyle: 3,
    backgroundStyle: 0,
    level: 6,
    badges: <String>[],
  );
  Future<DedaSocialProfile?> valid(String id) async {
    expect(id, '@DEDA-ABC123'); // never query alias or league participant.
    return public;
  }

  test('original canonical public profile is read-only and does not use active alias', () async {
    final profile = await DedaWeeklyOriginalPublicProfileResolver.resolve(
      competitor: competitor, stillSameViewer: () => true,
      currentAuthUid: () => 'viewer-current-auth',
      findOriginalProfile: valid);
    expect(profile?.ownerUid, 'target-real-public-profile-owner');
    expect(profile?.publicId, '@DEDA-ABC123');
  });

  test('late lookup after logout or switching UID must fail closed', () async {
    final waiting = Completer<DedaSocialProfile?>();
    var uid = 'viewer-current-auth';
    final future = DedaWeeklyOriginalPublicProfileResolver.resolve(
      competitor: competitor, stillSameViewer: () => true,
      currentAuthUid: () => uid,
      findOriginalProfile: (_) => waiting.future);
    uid = 'switched-to-another-account';
    waiting.complete(public);
    expect(await future, isNull);
  });

  test('account gate revokes a pending original public lookup', () async {
    final waiting = Completer<DedaSocialProfile?>();
    var active = true;
    final future = DedaWeeklyOriginalPublicProfileResolver.resolve(
      competitor: competitor, stillSameViewer: () => active,
      currentAuthUid: () => 'viewer-current-auth',
      findOriginalProfile: (_) => waiting.future);
    active = false;
    waiting.complete(public);
    expect(await future, isNull);
  });

  test('refuses wrong canonical alias, owner/self and changed display identity', () async {
    final samples = [
      const DedaSocialProfile(
        publicId: '@DEDA-BBB222', ownerUid: 'real-target',
        displayName: 'المتصدر الثاني',
        avatarStyle: 2, frameStyle: 3, backgroundStyle: 0, level: 6, badges: []),
      const DedaSocialProfile(
        publicId: '@DEDA-ABC123', ownerUid: 'viewer-current-auth',
        displayName: 'المتصدر الثاني',
        avatarStyle: 2, frameStyle: 3, backgroundStyle: 0, level: 6, badges: []),
      const DedaSocialProfile(
        publicId: '@DEDA-ABC123', ownerUid: '',
        displayName: 'المتصدر الثاني',
        avatarStyle: 2, frameStyle: 3, backgroundStyle: 0, level: 6, badges: []),
      const DedaSocialProfile(
        publicId: '@DEDA-ABC123', ownerUid: 'real-target',
        displayName: 'شخص آخر',
        avatarStyle: 2, frameStyle: 3, backgroundStyle: 0, level: 6, badges: []),
    ];
    for (final sample in samples) {
      final result = await DedaWeeklyOriginalPublicProfileResolver.resolve(
        competitor: competitor, stillSameViewer: () => true,
        currentAuthUid: () => 'viewer-current-auth',
        findOriginalProfile: (_) async => sample);
      expect(result, isNull);
    }
  });

  test('unverified competitor and missing UID never query public directory', () async {
    var reads = 0;
    final fake = DedaWeeklyPublicCompetitor(
      participantId: competitor.participantId,
      originalPublicId: competitor.originalPublicId,
      activePublicId: competitor.activePublicId,
      displayName: competitor.displayName,
      rankVerified: false,
      publicOwnerVerified: true,
      equippedAppearanceVerified: true);
    for (final person in [fake, competitor]) {
      final result = await DedaWeeklyOriginalPublicProfileResolver.resolve(
        competitor: person, stillSameViewer: () => true,
        currentAuthUid: () => person == fake ? 'viewer-current-auth' : null,
        findOriginalProfile: (_) async {reads++; return public;});
      expect(result, isNull);
    }
    expect(reads, 0);
  });

  testWidgets('real social profile route displays verified original data, no friend write',
      (tester) async {
    var lookedUp = 0, frames = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: Builder(builder: (context) => ElevatedButton(
        onPressed: () => DedaWeeklyOriginalPublicProfileViewer.open(
          context: context,
          competitor: competitor,
          stillSameViewer: () => true,
          currentAuthUid: () => 'viewer-current-auth',
          authEvents: const Stream<Object?>.empty(),
          drawOriginalEquippedAvatar: (_, a, f, size) {
            frames++;
            expect(a, 2); expect(f, 3);
            return const Icon(Icons.verified);
          },
          findOriginalProfile: (id) async {
            lookedUp++;
            expect(id, '@DEDA-ABC123');
            return public;
          },
        ),
        child: const Text('افتح الملف'),
      )),
    )));
    await tester.tap(find.text('افتح الملف'));
    await tester.pumpAndSettle();
    expect(lookedUp, 1);
    expect(frames, greaterThan(0));
    expect(find.text('الملف الشخصي العام'), findsOneWidget);
    expect(find.text('@DEDA-AAAA'), findsOneWidget);
    expect(find.text('المستوى 6'), findsOneWidget);
    expect(find.text('إرسال طلب صداقة'), findsNothing);
  });

  testWidgets('read-only profile route never opens after account revoked during read',
      (tester) async {
    final pending = Completer<DedaSocialProfile?>();
    var active = true;
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: Builder(builder: (context) => ElevatedButton(
        onPressed: () => DedaWeeklyOriginalPublicProfileViewer.open(
          context: context,
          competitor: competitor,
          stillSameViewer: () => active,
          currentAuthUid: () => 'viewer-current-auth',
          authEvents: const Stream<Object?>.empty(),
          drawOriginalEquippedAvatar: (_, a, f, s) => const Icon(Icons.person),
          findOriginalProfile: (_) => pending.future,
        ),
        child: const Text('افتح الملف'),
      )),
    )));
    await tester.tap(find.text('افتح الملف'));
    active = false;
    pending.complete(public);
    await tester.pumpAndSettle();
    expect(find.text('الملف الشخصي العام'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
