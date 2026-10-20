import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_exclusive_ids_admin_page.dart';

// Synthetic identifiers only. Never import or print the owner's private 100.
void main() {
  final timestamp = DateTime.utc(2026, 10, 20, 12);
  List<DedaExclusiveAdminId> available() => List.generate(100, (i) =>
      DedaExclusiveAdminId(
        sequence: i + 1,
        identifier: '@DEDA-T${(i + 1).toString().padLeft(3, '0')}',
        status: 'available',
      ));
  DedaExclusiveAdminSnapshot make(List<DedaExclusiveAdminId> ids,
          {List<DedaExclusiveAdminGrant> history = const [],
          bool confirmed = true, int total = 100}) =>
      DedaExclusiveAdminSnapshot(
        serverConfirmed: confirmed, total: total,
        identifiers: ids, history: history,
      );
  DedaExclusiveAdminId granted(DedaExclusiveAdminId base,
          {String color = 'royal', String status = 'gifted',
          String original = '@DEDA-A1B2C3'}) =>
      DedaExclusiveAdminId(
        sequence: base.sequence, identifier: base.identifier,
        status: status, permanentColor: color, ownerOriginalId: original,
      );
  DedaExclusiveAdminGrant audit(DedaExclusiveAdminId item,
          {String color = 'royal', String kind = 'gifted',
          String original = '@DEDA-A1B2C3', DateTime? when}) =>
      DedaExclusiveAdminGrant(
        identifier: item.identifier, recipientOriginalId: original,
        color: color, kind: kind, grantedAt: when ?? timestamp,
      );

  test('exactly 100 server-confirmed consecutive available IDs is valid', () {
    expect(DedaExclusiveAdminSnapshotVerifier.isSafe(make(available())), isTrue);
    expect(DedaExclusiveAdminSnapshotVerifier.isSafe(
        make(available(), confirmed: false)), isFalse);
    expect(DedaExclusiveAdminSnapshotVerifier.isSafe(
        make(available(), total: 99)), isFalse);
  });

  test('duplicate, reordered and malformed catalog entries fail closed', () {
    final reversed = available()..swap(0, 1);
    expect(DedaExclusiveAdminSnapshotVerifier.isSafe(make(reversed)), isFalse);
    final dup = available();
    dup[1] = DedaExclusiveAdminId(
      sequence: 2, identifier: dup[0].identifier, status: 'available');
    expect(DedaExclusiveAdminSnapshotVerifier.isSafe(make(dup)), isFalse);
    final invalid = available();
    invalid[0] = const DedaExclusiveAdminId(
      sequence: 1, identifier: '@DEDA-?BAD', status: 'available');
    expect(DedaExclusiveAdminSnapshotVerifier.isSafe(make(invalid)), isFalse);
  });

  test('available cannot masquerade as a permanently assigned color', () {
    final ids = available();
    ids[0] = DedaExclusiveAdminId(
      sequence: 1, identifier: ids[0].identifier,
      status: 'available', permanentColor: 'gold');
    expect(DedaExclusiveAdminSnapshotVerifier.isSafe(make(ids)), isFalse);
  });

  test('manager fixed-color gift requires matching server audit record', () {
    final ids = available();
    ids[0] = granted(ids[0]);
    expect(DedaExclusiveAdminSnapshotVerifier.isSafe(
        make(ids, history: [audit(ids[0])])), isTrue);
    expect(DedaExclusiveAdminSnapshotVerifier.isSafe(make(ids)), isFalse);
    expect(DedaExclusiveAdminSnapshotVerifier.isSafe(
        make(ids, history: [audit(ids[0], color: 'pink')])), isFalse);
    expect(DedaExclusiveAdminSnapshotVerifier.isSafe(
        make(ids, history: [audit(ids[0], original: '@DEDA-Z1Z2Z3')])),
        isFalse);
    expect(DedaExclusiveAdminSnapshotVerifier.isSafe(
        make(ids, history: [audit(ids[0], kind: 'self_used')])), isFalse);
  });

  test('self-use and gift history must be complete, unique and newest first', () {
    final ids = available();
    ids[0] = granted(ids[0], status: 'self_used');
    ids[1] = granted(ids[1], color: 'pink', original: '@DEDA-Z1Z2Z3');
    final history = [
      audit(ids[1], color: 'pink', original: '@DEDA-Z1Z2Z3',
          when: timestamp.add(const Duration(minutes: 1))),
      audit(ids[0], kind: 'self_used'),
    ];
    expect(DedaExclusiveAdminSnapshotVerifier.isSafe(
        make(ids, history: history)), isTrue);
    expect(DedaExclusiveAdminSnapshotVerifier.isSafe(
        make(ids, history: history.reversed.toList())), isFalse);
    expect(DedaExclusiveAdminSnapshotVerifier.isSafe(
        make(ids, history: [history.first, history.first])), isFalse);
  });
}

// List does not expose swap, keep the tests independent of collection packages.
extension _SafeSwap<T> on List<T> {
  void swap(int a, int b) {
    final tmp = this[a];
    this[a] = this[b];
    this[b] = tmp;
  }
}
