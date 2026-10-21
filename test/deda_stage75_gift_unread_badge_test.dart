import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_stage75_unread_gift_badge.dart';

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
}
