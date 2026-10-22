#!/usr/bin/env python3
"""Point12: safe, read-only real My Store entry in the reconstructed owner profile.
NO checkout, new gifts, cloud writes, or 'purchased' claims from local UI state.
Runs only after Point01/02 and the original profile card have been restored.
"""
from pathlib import Path

MAIN = Path('lib/main.dart')
MARK = '// DEDA_100377_POINT12_READ_ONLY_PERSONAL_MY_STORE'
IMPORT = "import 'deda_100377_my_store_page_staged.dart';\n"
ANCHOR = '  Widget _featureGrid() {'
METHOD = """  // DEDA_100377_POINT12_READ_ONLY_PERSONAL_MY_STORE
  Future<void> _openDedaMyStore() async {
    final accountPhone = DedaPreferences.phone;
    final originalId = _dedaId;
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
      DedaMyStoreItem(
        id: 'avatar_$avatarStyle',
        label: dedaText('الصورة المختارة ($avatarStyle)',
                        'Selected avatar ($avatarStyle)'),
        section: DedaMyStoreSection.avatars,
        proof: DedaMyStoreProof.deviceSaved, active: true,
      ),
      DedaMyStoreItem(
        id: 'background_$backgroundStyle',
        label: dedaText('الخلفية المختارة ($backgroundStyle)',
                        'Selected background ($backgroundStyle)'),
        section: DedaMyStoreSection.backgrounds,
        proof: DedaMyStoreProof.deviceSaved, active: true,
      ),
    ];
    if (frameStyle <= 5) {
      items.add(DedaMyStoreItem(
        id: 'frame_$frameStyle',
        label: dedaText('الإطار المجاني المختار ($frameStyle)',
                        'Selected free frame ($frameStyle)'),
        section: DedaMyStoreSection.frames,
        proof: DedaMyStoreProof.basicFree, active: true,
      ));
    } else {
      // A premium frame is NEVER called owned based on selected preferences.
      final frame = DedaLabPremiumFrameStyles.byProfileStyle(frameStyle);
      if (frame != null) {
        try {
          if (await DedaLabFrameSecureCheckout.isOwned(
              originalId: originalId, frameId: frame.id)) {
            items.add(DedaMyStoreItem(
              id: frame.id, label: frame.nameAr,
              section: DedaMyStoreSection.frames,
              proof: DedaMyStoreProof.serverVerified,
              receiptKind: 'purchase', active: true,
            ));
          }
        } catch (_) {
          // Keep premium frame absent when server proof cannot be verified.
        }
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
    // Only the server-confirmed active ID is presented, not unreceived gifts
    // or locally typed premium aliases. Full owned 200-list is Point13.
    if (DedaStage71OwnedIdentifierService.enabled) {
      try {
        final verifiedActive =
            await DedaStage71OwnedIdentifierService.active(originalId);
        if (verifiedActive != originalId) {
          items.add(DedaMyStoreItem(
            id: verifiedActive, label: verifiedActive,
            section: DedaMyStoreSection.identifiers,
            proof: DedaMyStoreProof.serverVerified, active: true,
          ));
        }
      } catch (_) {
        // No premium ownership claim without trusted current-account read.
      }
    }
    if (!mounted || DedaPreferences.phone != accountPhone ||
        _dedaId != originalId) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => DedaMyStorePage(originalId: originalId, items: items),
      ),
    );
  }

"""
TILE = """        // Point12: PERSONAL OWNERSHIP, separate from the paid ID shop below.
        _featureCard(
          icon: Icons.inventory_2_rounded,
          title: dedaText('متجري', 'My Store'),
          subtitle: dedaText('مقتنياتي وممتلكاتي', 'My inventory'),
          colors: const <Color>[Color(0xFF247C86), Color(0xFF125968)],
          onTap: () { _openDedaMyStore(); },
        ),
        const SizedBox(height: 10),
"""

def patch(src: str) -> str:
    if MARK in src:
        if src.count(MARK) != 1 or src.count(IMPORT) != 1 or src.count("title: dedaText('متجري', 'My Store')") != 1:
            raise ValueError('SAFE_STOP_POINT12_PARTIAL_PATCH')
        return src
    if src.count(ANCHOR) != 1 or src.count("title: dedaText('متجر المعرّفات', 'Identifier store')") != 1:
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
    if grid.count(head) != 1:
        raise ValueError('SAFE_STOP_POINT12_FEATURE_GRID_ROWS_DRIFT')
    grid = grid.replace(head, head.replace('        Row(\n', TILE + '        Row(\n'), 1)
    src = src[:pos] + grid + src[end:]
    import_anchor = "import 'deda_lab_frame_secure_checkout.dart';\n"
    src = src.replace(import_anchor, import_anchor + IMPORT, 1)
    if src.count(MARK) != 1 or src.count(IMPORT) != 1 or src.count("title: dedaText('متجر المعرّفات', 'Identifier store')") != 1:
        raise ValueError('SAFE_STOP_POINT12_SHOP_OR_IMPORT_MUTATED')
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
