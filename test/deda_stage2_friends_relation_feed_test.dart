import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_social_service.dart';

const original = '@DEDA-ABC123';
const friend = '@DEDA-ZZZ999';

DedaSocialProfile profile(String id, String owner) => DedaSocialProfile(
  publicId: id, ownerUid: owner, displayName: 'User',
  avatarStyle: 0, frameStyle: 0, backgroundStyle: 0, level: 1, badges: const [],
);
DedaFriendshipRecord row(String id, String from, String to) => DedaFriendshipRecord(
  id: id, members: [from,to], requesterUid: from, recipientUid: to,
  requesterPublicId: from, recipientPublicId: to,
  requesterName: from, recipientName: to, status: 'accepted',
);
Future<void> tick() => Future<void>.delayed(Duration.zero);

void main() {
  test('original social key is not the real Firebase UID', () {
    final session = DedaSocialSession(uid: original, publicId: original,
        profile: profile(original, 'firebase-owner'));
    expect(session.belongsToFirebaseOwner('firebase-owner'), isTrue);
    expect(session.belongsToFirebaseOwner(original), isFalse);
    expect(session.belongsToFirebaseOwner('other'), isFalse);
    expect(session.belongsToFirebaseOwner(null), isFalse);
    expect(session.isSelfProfile(profile(original, 'other')), isTrue);
    expect(session.isSelfProfile(profile('@DEDA-PREMIUM', 'firebase-owner')), isTrue);
    expect(session.isSelfProfile(profile(friend, 'other')), isFalse);
  });

  test('first relation result waits for both directions; deduplicates and filters', () async {
    final sent = StreamController<List<DedaFriendshipRecord>>();
    final incoming = StreamController<List<DedaFriendshipRecord>>();
    final results = <List<DedaFriendshipRecord>>[];
    final subscription = DedaSocialService.mergeRelationFeeds(
        original, sent.stream, incoming.stream, isCurrent: () => true).listen(results.add);
    sent.add([]);
    await tick();
    expect(results, isEmpty);
    incoming.add([row('one', friend, original), row('foreign', 'X', 'Y')]);
    await tick();
    expect(results.single.map((r) => r.id), ['one']);
    sent.add([row('one', friend, original), row('two', original, friend)]);
    await tick();
    expect(results.last.map((r) => r.id).toSet(), {'one','two'});
    await subscription.cancel();
    await sent.close();
    await incoming.close();
  });

  test('failed side never produces an incomplete or false empty count', () async {
    final sent = StreamController<List<DedaFriendshipRecord>>();
    final incoming = StreamController<List<DedaFriendshipRecord>>();
    final results = <List<DedaFriendshipRecord>>[];
    final errors = <Object>[];
    final subscription = DedaSocialService.mergeRelationFeeds(
        original, sent.stream, incoming.stream, isCurrent: () => true)
        .listen(results.add, onError: (Object e) => errors.add(e));
    sent.add([]);
    incoming.addError(StateError('network'));
    await tick();
    expect(errors, hasLength(1));
    expect(results, isEmpty);
    incoming.add([row('one', friend, original)]);
    await tick();
    expect(results.single, hasLength(1));
    await subscription.cancel();
    await sent.close();
    await incoming.close();
  });

  test('stale authenticated session never publishes a new list', () async {
    final sent = StreamController<List<DedaFriendshipRecord>>();
    final incoming = StreamController<List<DedaFriendshipRecord>>();
    var current = true;
    final results = <List<DedaFriendshipRecord>>[];
    final errors = <Object>[];
    final subscription = DedaSocialService.mergeRelationFeeds(
        original, sent.stream, incoming.stream, isCurrent: () => current)
        .listen(results.add, onError: (Object e) => errors.add(e));
    sent.add([]);
    await tick();
    current = false;
    incoming.add([row('one', friend, original)]);
    await tick();
    expect(results, isEmpty);
    expect(errors, hasLength(1));
    await subscription.cancel();
    await sent.close();
    await incoming.close();
  });
}
