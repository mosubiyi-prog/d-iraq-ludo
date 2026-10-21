import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_stage75_unread_gift_badge.dart';
import 'package:d_iraq_ludo/deda_stage74_id_gift_service.dart';

void main() {
  test('first unseen identifier gift produces one red badge', () {
    expect(DedaStage75UnreadGiftBadge.unreadCount(
        ['@DEDA-IRAQI'], <String>{}), 1);
  });

  test('opening inbox makes an already viewed gift non-unread', () {
    expect(DedaStage75UnreadGiftBadge.unreadCount(
        ['@DEDA-IRAQI'], {'@DEDA-IRAQI'}), 0);
  });

  test('subsequent new gift restores badge without rereading old gift', () {
    expect(DedaStage75UnreadGiftBadge.unreadCount(
        ['@DEDA-IRAQI', '@DEDA-AMJAD'], {'@DEDA-IRAQI'}), 1);
  });

  test('duplicate gift snapshot cannot double the badge', () {
    expect(DedaStage75UnreadGiftBadge.unreadCount(
        ['@DEDA-IRAQI', '@DEDA-IRAQI'], <String>{}), 1);
  });

  test('legacy diamond badge count remains a separate input', () {
    final diamondPending = 2;
    final identifierPending = DedaStage75UnreadGiftBadge.unreadCount(
        ['@DEDA-IRAQI'], <String>{});
    expect(diamondPending + identifierPending, 3);
  });
  test('received gift never returns as unread on a new device', () {
    const received = DedaStage74IdGift(
      identifier: '@DEDA-IRAQI', originalId: '@DEDA-ABC123',
      group: '001', baseColor: 'gold', received: true,
    );
    final pending = DedaStage75UnreadGiftBadge.awaitingIdentifiers(
        '@DEDA-ABC123', [received]);
    expect(DedaStage75UnreadGiftBadge.unreadCount(pending, <String>{}), 0);
  });

  test('only unreceived grants for same account raise the badge', () {
    const current = DedaStage74IdGift(
      identifier: '@DEDA-NEW123', originalId: '@DEDA-ABC123',
      group: '002', baseColor: 'gold', received: false,
    );
    const foreign = DedaStage74IdGift(
      identifier: '@DEDA-OTHER1', originalId: '@DEDA-DEF456',
      group: '002', baseColor: 'gold', received: false,
    );
    final ids = DedaStage75UnreadGiftBadge.awaitingIdentifiers(
        '@DEDA-ABC123', [current, foreign]);
    expect(ids.toList(), ['@DEDA-NEW123']);
    expect(DedaStage75UnreadGiftBadge.unreadCount(ids, <String>{}), 1);
  });

}
