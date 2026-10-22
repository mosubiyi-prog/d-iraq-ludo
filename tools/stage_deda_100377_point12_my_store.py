#!/usr/bin/env python3
"""Point12: safe, read-only real My Store entry in the reconstructed owner profile.
NO checkout, new gifts, cloud writes, or 'purchased' claims from local UI state.
Runs only after Point01/02 and the original profile card have been restored.
"""
from pathlib import Path

MAIN = Path('lib/main.dart')
MARK = '// DEDA_100377_POINT12_READ_ONLY_PERSONAL_MY_STORE'
IMPORT = "import 'deda_100377_my_store_page_staged.dart';\nimport 'deda_100377_profile_free_inventory.dart';\n"
ANCHOR = '  Widget _featureGrid() {'
METHOD = """  // DEDA_100377_POINT12_READ_ONLY_PERSONAL_MY_STORE
  Future<void> _openDedaMyStore() async {
    final accountPhone = DedaPreferences.phone;
    final originalId = _dedaId;
    final signedUidAtOpen = Firebase.apps.isEmpty
        ? null : FirebaseAuth.instance.currentUser?.uid;
    if (!RegExp(r'^@DEDA-[A-Z0-9]{6}$').hasMatch(originalId)) return;
    final avatarStyle = DedaPreferences.profileAvatarStyle;
    final frameStyle = DedaPreferences.profileFrameStyle;
    final backgroundStyle = DedaPreferences.profileBackgroundStyle;
    final inventory = await DedaStyleInventory.load();
    if (!mounted || DedaPreferences.phone != accountPhone ||
        _dedaId != originalId) return;
    final items = <DedaMyStoreItem>[
      DedaMyStoreItem(
        id: 'original_id', label: originalId,
        section: DedaMyStoreSection.identifiers,
        proof: DedaMyStoreProof.basicFree,
        active: true,
      ),
    ];
    // DEDA_100377_POINT12_FULL_NATIVE_FREE_APPEARANCE_NO_FAKE_MOONLIT
    // The original 6/6/6 picker options are FREE and READ-ONLY here;
    // missing owner-approved moonlit images are not substituted.
    items.addAll(DedaProfileFreeInventory.forDevice(
      avatarStyle: avatarStyle,
      frameStyle: frameStyle,
      backgroundStyle: backgroundStyle,
    ));
    // DEDA_100377_P12_ALL_PAID_FRAMES_VERIFIED_NOT_ONLY_SELECTED
    // Source.server receipt AND matching entitlement are checked for EACH of
    // the thirteen authentic premium frames, not just the equipped one.
    // The gated purchase feature is OFF until authorized; never infer ownership
    // from selected style, local diamonds, or a failed/offline server read.
    if (DedaLabFrameSecureCheckout.live) {
      try {
        // One authenticated server proof, then paired receipt/entitlement
        // reads for all 13: do not block on thirteen sequential auth checks.
        final ownedFrames =
            await DedaLabFrameSecureCheckout.verifiedOwnedFrameIds(originalId);
        for (var style = 6; style <= 18; style++) {
          final frame = DedaLabPremiumFrameStyles.byProfileStyle(style);
          if (frame == null || !ownedFrames.contains(frame.id)) continue;
          items.add(DedaMyStoreItem(
            id: frame.id, label: frame.nameAr,
            section: DedaMyStoreSection.frames,
            proof: DedaMyStoreProof.serverVerified,
            receiptKind: 'purchase', active: frameStyle == style,
          ));
        }
      } catch (_) {
        // Offline or wrong account: do not show an unverified purchase.
      }
    }
    for (var i = 0; i < dedaStyleBadgeIds.length; i++) {
      final badgeId = dedaStyleBadgeIds[i];
      if (!inventory.owned.contains(badgeId)) continue;
      items.add(DedaMyStoreItem(
        id: badgeId, label: dedaStyleName(i),
        section: DedaMyStoreSection.badges,
        // Prior badge wallet is local. Do NOT claim a verified receipt.
        proof: DedaMyStoreProof.deviceSaved,
        active: inventory.activeBadges.contains(badgeId),
      ));
    }
    // DEDA_100377_P12_ALL_RECEIVED_OR_SELF_USED_GM_IDS
    // Every held manager ID requires an authenticated server registry record;
    // gifted entries ALSO require the receiver's server receipt. Display
    // all held names, while marking only the currently active alias as active.
    if (DedaStage71OwnedIdentifierService.enabled) {
      try {
        final held = await DedaStage71OwnedIdentifierService
            .acceptedOwnedForMyStore(originalId);
        var currentActive = originalId;
        try {
          currentActive =
              await DedaStage71OwnedIdentifierService.active(originalId);
        } catch (_) {
          // A failed active lookup must NOT grant or activate another ID.
        }
        items[0] = DedaMyStoreItem(
          id: 'original_id', label: originalId,
          section: DedaMyStoreSection.identifiers,
          proof: DedaMyStoreProof.basicFree,
          active: currentActive == originalId,
        );
        for (final row in held) {
          items.add(DedaMyStoreItem(
            id: row.identifier, label: row.identifier,
            section: DedaMyStoreSection.identifiers,
            proof: DedaMyStoreProof.serverVerified,
            receiptKind: row.kind == 'gifted' ? 'gift' : null,
            active: currentActive == row.identifier,
          ));
        }
      } catch (_) {
        // Offline or account mismatch: never show unreceived/non-owned IDs.
      }
    }
    if (!mounted || DedaPreferences.phone != accountPhone ||
        _dedaId != originalId ||
        (Firebase.apps.isNotEmpty &&
         FirebaseAuth.instance.currentUser?.uid != signedUidAtOpen)) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => DedaMyStorePage(
          originalId: originalId,
          items: items,
          onOpenIdentifierShop: () {
            if (!mounted || DedaPreferences.phone != accountPhone ||
                _dedaId != originalId ||
                (Firebase.apps.isNotEmpty &&
                 FirebaseAuth.instance.currentUser?.uid != signedUidAtOpen)) {
              return;
            }
            // Reuse exact original DedaIdentifierStorePage route, never mint
            // an alternative ID store or bypass its ownership controls.
            final activeId = _dedaId;
            Navigator.push<void>(
              context,
              MaterialPageRoute<void>(
                builder: (_) => DedaIdentifierStorePage(
                  identifier: activeId.isEmpty ? '@DEDA' : activeId,
                  readOnlyCatalog: const <String>[],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

"""
# Point12 owner correction: no extra teal card; rename the ORIGINAL purple
# Identifier Store profile tile to My Store, while retaining its exact original
# acquisition route as an explicit action from within My Store.
SHOP_TITLE = "title: dedaText('متجر المعرّفات', 'Identifier store'),"
MY_STORE_TITLE = "title: dedaText('متجري', 'My Store'),"
SHOP_SUBTITLE = "subtitle: dedaText('معرّفات مميزة', 'Premium identifiers'),"
MY_STORE_SUBTITLE = "subtitle: dedaText('مقتنياتي وممتلكاتي', 'My inventory'),"
ORIGINAL_SHOP_TAP = """onTap: () {
                  final activeId = _dedaId;
                  Navigator.push<void>(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => DedaIdentifierStorePage(
                        identifier: activeId.isEmpty ? '@DEDA' : activeId,
                        readOnlyCatalog: const <String>[],
                      ),
                    ),
                  );
                },"""
REPLACEMENT_MY_STORE_TAP = """// DEDA_100377_POINT12_SINGLE_PROFILE_TILE_KEEP_ORIGINAL_SHOP_NESTED
                onTap: () {
                  _openDedaMyStore();
                },"""

def patch(src: str) -> str:
    if MARK in src:
        if (src.count(MARK) != 1 or src.count(IMPORT) != 1 or
                src.count(MY_STORE_TITLE) != 1 or
                src.count('onOpenIdentifierShop: () {') != 1):
            raise ValueError('SAFE_STOP_POINT12_PARTIAL_PATCH')
        return src
    if src.count(ANCHOR) != 1 or src.count(SHOP_TITLE) != 1:
        raise ValueError('SAFE_STOP_POINT12_ORIGINAL_PROFILE_SHOP_DRIFT')
    if src.count("import 'deda_lab_frame_secure_checkout.dart';") != 1:
        raise ValueError('SAFE_STOP_POINT12_MISSING_POINT01_CHECKOUT')
    if src.count("class _DedaProfilePhase2PageState") != 1 or src.count("class DedaStyleInventory {") != 1:
        raise ValueError('SAFE_STOP_POINT12_PROFILE_OR_INVENTORY_MISSING')
    part = src.split(ANCHOR, 1)[1]
    head = '    return Column(\n      children: <Widget>[\n        Row(\n'
    if not part.startswith('\n    return Column') or part.count(head) < 1 or head not in part[:120]:
        raise ValueError('SAFE_STOP_POINT12_FEATURE_GRID_SHAPE_CHANGED')
    src = src.replace(ANCHOR, METHOD + ANCHOR, 1)
    pos = src.index(ANCHOR) + len(ANCHOR)
    end = src.find('  Widget _featureCard(', pos)
    if end < pos: raise ValueError('SAFE_STOP_POINT12_GRID_END')
    grid = src[pos:end]
    if (grid.count(head) != 1 or grid.count(SHOP_TITLE) != 1 or
            grid.count(SHOP_SUBTITLE) != 1 or
            grid.count(ORIGINAL_SHOP_TAP) != 1 or
            grid.count('DEDA_INTAKADHA_POINT8_PHOTOS_TILE_BECOMES_ID_SHOP_2026_10_18') != 1):
        raise ValueError('SAFE_STOP_POINT12_PROFILE_TILE_OR_ORIGINAL_SHOP_DRIFT')
    # Replace the original existing profile tile, NOT add any new tile.
    grid = grid.replace(SHOP_TITLE, MY_STORE_TITLE, 1)
    grid = grid.replace(SHOP_SUBTITLE, MY_STORE_SUBTITLE, 1)
    grid = grid.replace(ORIGINAL_SHOP_TAP, REPLACEMENT_MY_STORE_TAP, 1)
    if grid.count(MY_STORE_TITLE) != 1 or grid.count(SHOP_TITLE) != 0:
        raise ValueError('SAFE_STOP_POINT12_DUPLICATE_STORE_TILE')
    src = src[:pos] + grid + src[end:]
    import_anchor = "import 'deda_lab_frame_secure_checkout.dart';\n"
    src = src.replace(import_anchor, import_anchor + IMPORT, 1)
    if src.count(MARK) != 1 or src.count(IMPORT) != 1 or src.count(MY_STORE_TITLE) != 1:
        raise ValueError('SAFE_STOP_POINT12_SHOP_OR_IMPORT_MUTATED')
    result_grid = src[src.index(ANCHOR):src.index('  Widget _featureCard(', src.index(ANCHOR))]
    if result_grid.count(MY_STORE_TITLE) != 1 or result_grid.count(SHOP_TITLE) != 0:
        raise ValueError('SAFE_STOP_POINT12_MULTIPLE_PROFILE_SHOPS')
    if src.count('onOpenIdentifierShop: () {') != 1:
        raise ValueError('SAFE_STOP_POINT12_ORIGINAL_SHOP_ACCESS_LOST')
    return src

if __name__ == '__main__':
    old = MAIN.read_text(encoding='utf-8')
    new = patch(old)
    if new == old:
        raise SystemExit('SAFE_STOP_POINT12_ALREADY_STAGED')
    MAIN.write_text(new, encoding='utf-8')
    print('PASS_POINT12_READ_ONLY_MY_STORE_TILE_AND_ACCOUNT_SCOPED_SNAPSHOT')
    print('PASS_POINT12_ORIGINAL_ID_SHOP_AND_EXISTING_BADGE_STORE_UNCHANGED')
    print('NO_CHARGES_NO_FAKE_OWNERSHIP_NO_CLOUD_WRITES_NO_PLAY_DEPLOY')
