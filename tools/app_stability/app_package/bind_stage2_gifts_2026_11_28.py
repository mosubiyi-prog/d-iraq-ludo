"""Bind the existing Hadaya routes on the disposable stage 04 app."""
import argparse
from pathlib import Path

from bind_stage2_weekly_league_2026_11_24 import LAB_IMPORT, one
from bind_stage2_bottom_navigation_2026_11_24 import home

ROOT = Path(__file__).resolve().parents[3]
STORAGE = 'DedaStage03LabStorage'


def member(s, marker, patch):
    start, end = home.span(s, marker)
    return s[:start] + patch(s[start:end]) + s[end:]


def patch_main(s):
    if LAB_IMPORT not in s:
        raise ValueError('GIFTS_EXISTING_LEAGUE_BINDING_REQUIRED')
    s = member(s, 'class _DedaMyGiftsPageState ', lambda body: one(
        one(body, STORAGE + '.leagueLabMode', STORAGE + '.giftsInboxLabMode', 'gifts-page'),
        '        await DedaDiamondsWallet.load();\n        balanceRefreshed = true;',
        '        if (!' + STORAGE + '.giftsLabMode) {\n'
        '          await DedaDiamondsWallet.load();\n          balanceRefreshed = true;\n        }',
        'gifts-no-legacy-wallet-refresh'))
    s = member(s, 'class _DedaGiftNavBadgeState ', lambda body: one(
        body, '    unawaited(DedaStage75UnreadGiftBadge.start(',
        '    if (' + STORAGE + '.giftsLabMode) return;\n'
        '    unawaited(DedaStage75UnreadGiftBadge.start(', 'gifts-shared-badge-owner'))

    def badge(body):
        body = one(body, '  static Future<void> start() async {',
            '''  static Future<void> start() async {
    if (DedaStage03LabStorage.giftsLabMode) {
      if (_subscription != null) return;
      final generation = ++_generation;
      try {
        final opening = await DedaStage03LabStorage.openGiftsInbox();
        final id = opening.requireCurrent().originalId;
        if (_generation != generation) return;
        unawaited(DedaStage75UnreadGiftBadge.start(id));
        _subscription = DedaBackend.watchPersonalDiamondGifts(id).listen((gifts) {
          if (_generation != generation) return;
          try {
            opening.requireCurrent();
            pendingNotifier.value = gifts.where((gift) => gift['status'] == 'pending').length;
          } catch (_) {
            unawaited(stop());
          }
        }, onError: (Object _) {
          if (_generation == generation) pendingNotifier.value = 0;
        }, onDone: () {
          if (_generation == generation) unawaited(stop());
        });
      } catch (_) {
        if (_generation == generation) await stop();
      }
      return;
    }''', 'gifts-diamond-badge')
        return body

    return member(s, 'class DedaGiftInbox ', badge)


def patch_backend(s):
    if s.count(STORAGE + '.leagueLabMode') != 2 or LAB_IMPORT not in s:
        raise ValueError('GIFTS_EXISTING_DIAMOND_READER_AND_CLAIM_REQUIRED')
    return s.replace(STORAGE + '.leagueLabMode', STORAGE + '.giftsInboxLabMode')


def patch_identifier_service(s):
    if LAB_IMPORT in s:
        raise ValueError('GIFTS_DUPLICATE_IDENTIFIER_SERVICE')
    s = one(s, 'static bool get enabled => DedaStage71Admin200.enabled;',
        'static bool get enabled => DedaStage03LabStorage.giftsLabMode || '
        'DedaStage71Admin200.enabled;', 'gifts-identifier-gate')
    s = one(s, '  static Future<List<DedaStage74IdGift>> load(String originalId) async {',
        '''  static Future<List<DedaStage74IdGift>> load(String originalId) async {
    if (DedaStage03LabStorage.giftsLabMode) {
      final opening = await DedaStage03LabStorage.openGiftsInbox(originalId);
      final rows = <DedaStage74IdGift>[];
      for (final row in opening.requireCurrent().verifiedIdentifierGifts.values) {
        final grant = row['grant'] as Map;
        final acceptance = row['acceptance'] as Map?;
        rows.add(DedaStage74IdGift(
          identifier: row['identifier'] as String,
          originalId: originalId,
          group: grant['group'] as String,
          baseColor: grant['baseColor'] as String,
          received: acceptance != null,
          receivedAt: acceptance == null ? null :
              DateTime.fromMillisecondsSinceEpoch(acceptance['receivedMs'] as int, isUtc: true),
        ));
      }
      rows.sort((a, b) => a.received != b.received
          ? (a.received ? 1 : -1) : a.identifier.compareTo(b.identifier));
      opening.requireCurrent();
      return rows;
    }''', 'gifts-identifier-protected-read')
    s = one(s, '    final uid = await _verifiedOwner(gift.originalId);',
        '''    final labMode = DedaStage03LabStorage.giftsLabMode;
    if (labMode && !DedaStage03LabStorage.giftsClaimCandidateEnabled) {
      throw StateError('identifier-gift-claim-held');
    }
    final opening = labMode
        ? await DedaStage03LabStorage.openGiftsInbox(gift.originalId) : null;
    final uid = opening?.requireCurrent().uid ?? await _verifiedOwner(gift.originalId);''',
        'gifts-identifier-current-session')
    s = one(s, '      final row = issued.data();',
        '''      if (opening != null) {
        final fresh = await DedaStage03LabStorage.readGiftInventoryInTransaction(
            transaction, db, opening);
        final proof = fresh.verifiedIdentifierGifts[gift.identifier];
        final grantProof = proof?['grant'] as Map?;
        if (grantProof == null || grantProof['group'] != gift.group ||
            grantProof['baseColor'] != gift.baseColor ||
            (proof?['acceptance'] != null && !existing.exists)) {
          throw StateError('identifier-gift-inventory-conflict');
        }
      }
      final row = issued.data();''', 'gifts-identifier-existing-transaction')
    s = one(s, '      transaction.set(receipt, {',
        '      opening?.requireCurrent();\n      transaction.set(receipt, {',
        'gifts-identifier-before-write')
    s = one(s, '    final data = confirmed.data();',
        '    opening?.requireCurrent();\n    final data = confirmed.data();',
        'gifts-identifier-readback')
    s = one(s, "      throw StateError('gift-receipt-readback-unconfirmed');\n    }",
        '''      throw StateError('gift-receipt-readback-unconfirmed');
    }
    if (opening != null) {
      final projected = await DedaStage03LabStorage.openGiftsInbox(gift.originalId);
      final proof = projected.requireCurrent().verifiedIdentifierGifts[gift.identifier];
      final acceptance = proof?['acceptance'] as Map?;
      final receivedAt = data['receivedAt'] as Timestamp;
      opening.requireCurrent();
      if (acceptance?['receivedMs'] != receivedAt.millisecondsSinceEpoch) {
        throw StateError('identifier-gift-projection-unconfirmed');
      }
    }''', 'gifts-identifier-central-confirmation')
    s = one(s, '  static Future<bool> isReceived(String originalId, String identifier) async {',
        '''  static Future<bool> isReceived(String originalId, String identifier) async {
    if (DedaStage03LabStorage.giftsLabMode) {
      final opening = await DedaStage03LabStorage.openGiftsInbox(originalId);
      return opening.requireCurrent().acceptedGiftIds.contains(identifier);
    }''', 'gifts-identifier-protected-acceptance')
    return LAB_IMPORT + s


def patch_badge(s):
    if LAB_IMPORT in s or 'final previous = _listener;' not in s:
        raise ValueError('GIFTS_EXISTING_BADGE_LIFETIME_REQUIRED')
    s = one(s, 'StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _listener;',
        'StreamSubscription<int>? _listener;', 'gifts-badge-invalidation-stream')
    start = s.index('      _listener = FirebaseFirestore.instance')
    end = s.index('\n    } catch (_) {', start)
    s = s[:start] + '''      final Stream<int> changes;
      if (DedaStage03LabStorage.giftsLabMode) {
        final opening = await DedaStage03LabStorage.openGiftsInbox(originalId);
        changes = DedaStage03LabStorage.watchGiftsInventory(opening);
      } else {
        changes = FirebaseFirestore.instance
            .collection(DedaStage71Admin200.registry)
            .where('recipientOriginalId', isEqualTo: originalId)
            .snapshots().where((snapshot) => !snapshot.metadata.isFromCache)
            .map((_) => 0);
      }
      if (!_stillCurrent(generation, uid, originalId)) return;
      _listener = changes.listen((_) {
        unawaited(_refresh(generation, uid, originalId));
      }, onError: (Object _) {
        if (DedaStage03LabStorage.giftsLabMode &&
            _stillCurrent(generation, uid, originalId)) {
          unawaited(stop());
        }
      });''' + s[end:]
    return LAB_IMPORT + s


def bind(project):
    project = project.resolve()
    if project == ROOT or ROOT in project.parents or project in ROOT.parents:
        raise ValueError('GIFTS_DISPOSABLE_PROJECT_REQUIRED')
    transforms = {
        'main.dart': patch_main,
        'deda_backend.dart': patch_backend,
        'deda_stage74_id_gift_service.dart': patch_identifier_service,
        'deda_stage75_unread_gift_badge.dart': patch_badge,
    }
    updates = {
        project/'lib'/name: patch((project/'lib'/name).read_text(encoding='utf-8'))
        for name, patch in transforms.items()
    }
    for path, source in updates.items():
        path.write_text(source, encoding='utf-8')
    print('PASS_STAGE04_ORIGINAL_GIFT_ROUTES_PROTECTED_UID_INVENTORY')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('project', type=Path)
    bind(parser.parse_args().project)
