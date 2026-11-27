"""04/04: original store components, disposable assembly only, default off."""
from pathlib import Path
import sys
import re

REPO = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPO / 'tools/app_stability'))
from bind_auth_runtime import body_range, tokens, pairs
IMPORT = "import 'deda_stage03_lab_uid_storage_2026_11_25.dart';\n"
MODE = "DedaStage03LabStorage.storeLabMode"


def once(source, old, new):
    if source.count(old) != 1:
        raise ValueError('STORE_SOURCE_ANCHOR_DRIFT: ' + old[:80])
    return source.replace(old, new, 1)


def inject(source, name, code):
    # Reuse the existing balanced Dart parser, not guessed await text.
    declarations = re.findall(r'\bFuture<[^;\n]+?>\s+' + re.escape(name) + r'\s*\(', source)
    if len(declarations) != 1:
        raise ValueError('STORE_METHOD_NOT_UNIQUE: ' + name)
    opening, closing, _, _ = body_range(source, name)
    if 'DedaStage03LabStorage.storeLabMode' in source[opening+1:closing]:
        raise ValueError('STORE_METHOD_ALREADY_BOUND: ' + name)
    updated = source[:opening+1] + '\n' + code.rstrip() + '\n' + source[opening+1:]
    pairs(tokens(updated))
    return updated


def patch_cards(source):
    s = IMPORT + source
    s = once(s, '  static final Map<String, int> _versions = {};',
        '''  static final Map<String, int> _versions = {};
  static final _labOpen = <String,DedaStage04AppearanceRead>{};

  static DedaPremiumIdCardColor? visibleChoice(String originalId,
      DedaPremiumIdCardColor? value) {
    if (!DedaStage03LabStorage.storeLabMode) return value;
    try {
      final proof = _labOpen[originalId];
      if (proof == null || proof.requireCurrent().originalId != originalId ||
          proof.freeCardChoice != value?.name) return null;
      return value;
    } catch (_) { return null; }
  }''')
    s = inject(s, 'restore',
        '''    if (DedaStage03LabStorage.storeLabMode) {
      final state = notifier(originalId);
      final version = (_versions[originalId] ?? 0) + 1;
      _versions[originalId] = version;
      _labOpen.remove(originalId);
      state.value = null;
      try {
        final proof = await DedaStage03LabStorage.readStoreFreeCard(originalId);
        if (_versions[originalId] != version) return;
        final choice = proof.freeCardChoice;
        _labOpen[originalId] = proof;
        state.value = choice == null ? null :
          DedaPremiumIdCardColor.values.singleWhere((c)=>c.name==choice);
      } catch (_) {
        if (_versions[originalId] == version) {
          _labOpen.remove(originalId);
          state.value = null;
        }
        rethrow;
      }
      return;
    }
    ''')
    s = inject(s, 'use',
        '''    if (DedaStage03LabStorage.storeLabMode) {
      final opening = _labOpen[originalId];
      if (opening == null) throw StateError('store-card-open-required');
      opening.requireCurrent();
      final version = (_versions[originalId] ?? 0) + 1;
      _versions[originalId] = version;
      final saved = await DedaStage03LabStorage.saveStoreFreeCard(
        opening,originalId,choice.name);
      if (saved.status != DedaPrivateDataStatus.saved) {
        throw StateError('store-card-save-unconfirmed');
      }
      if (_versions[originalId] != version) return;
      opening.requireCurrent();
      await restore(originalId);
      if (visibleChoice(originalId,notifier(originalId).value) != choice) {
        throw StateError('store-card-readback-unconfirmed');
      }
      return;
    }
    '''.rstrip())
    s = once(s, '    _states[originalId]?.value = null;',
        '    _labOpen.remove(originalId);\n    _states[originalId]?.value = null;')
    if s.count('active == widget.color') != 2:
        raise ValueError('STORE_CARD_ACTION_DRIFT')
    s = s.replace('active == widget.color','DedaStage71FreeCards.visibleChoice(widget.originalId,active) == widget.color')
    if 'DEDA_ACCOUNT_CHOICE_BOUND_V1' in s:
        s = once(s, '(!dedaAccountChoiceSyncEnabled || DedaFreeCardSyncBridge.statusFor',
            '(DedaStage03LabStorage.storeLabMode || !dedaAccountChoiceSyncEnabled || DedaFreeCardSyncBridge.statusFor')
        s = once(s, '(dedaAccountChoiceSyncEnabled && DedaFreeCardSyncBridge.statusFor',
            '(!DedaStage03LabStorage.storeLabMode && dedaAccountChoiceSyncEnabled && DedaFreeCardSyncBridge.statusFor')
    s = once(s, 'builder: (context, color, child) => color == null',
        'builder: (context, color, child) => DedaStage71FreeCards.visibleChoice(widget.originalId,color) == null')
    s = once(s, '                color: color,', '                color: color!,')
    return "import 'deda_private_data_sync.dart';\n" + s


def patch_native_checkout(source):
    s = IMPORT + source
    s = once(s,'  static const live = true;', '  static const live = !'+MODE+';')
    s = inject(s, 'isOwned',
        '''    if (DedaStage03LabStorage.storeLabMode) {
      _item(frameId);
      final p = await DedaStage03LabStorage.readStoreProfile(originalId);
      return p.requireCurrent().verifiedPaidFrameIds.contains(frameId);
    }
    '''.rstrip())
    s = inject(s, 'verifiedOwnedFrameIds',
        '''    if (DedaStage03LabStorage.storeLabMode) {
      final p = await DedaStage03LabStorage.readStoreProfile(originalId);
      return p.requireCurrent().verifiedPaidFrameIds;
    }''')
    s = inject(s, 'verifiedPurchaseBalance',
        '''    if (DedaStage03LabStorage.storeLabMode) {
      throw StateError('store-central-spend-authority-held');
    }''')
    s = inject(s, '_buy', '''    if (DedaStage03LabStorage.storeLabMode) {
      throw StateError('store-central-spend-authority-held');
    }''')
    s = once(s,"    _item(frameId);\n    final key = '$originalId/$frameId';",
        """    _item(frameId);
    if (DedaStage03LabStorage.storeLabMode) {
      return Future<void>.error(StateError('store-central-spend-authority-held'));
    }
    final key = '$originalId/$frameId';""")
    return s


def patch_receipt_checkout(source):
    s = IMPORT + source
    s = once(s, "static const bool live = bool.fromEnvironment(",
        "static const bool live = !"+MODE+" && bool.fromEnvironment(")
    s = inject(s, 'verifiedPurchaseBalance',
        '''    if (DedaStage03LabStorage.storeLabMode) {
      throw StateError('store-central-spend-authority-held');
    }''')
    s = inject(s, 'isOwned',
        '''    if (DedaStage03LabStorage.storeLabMode) {
      purchaseId(originalId,frameId);
      final p = await DedaStage03LabStorage.readStoreProfile(originalId);
      return p.requireCurrent().verifiedPaidFrameIds.contains(frameId);
    }
    '''.rstrip())
    s = inject(s, 'verifiedOwnedFrameIds',
        '''    if (DedaStage03LabStorage.storeLabMode) {
      final p = await DedaStage03LabStorage.readStoreProfile(originalId);
      return p.requireCurrent().verifiedPaidFrameIds;
    }''')
    return s


def patch_profile(source):
    old = """                    if (_stage04LabMode)
                      GestureDetector(
                        onTap: _stage04CopyId,
                        child: Text(_stage04View!.activeId,
                            key: const Key('deda_stage04_verified_id'),
                            style: const TextStyle(color: Color(0xFFFFD76A),
                                fontWeight: FontWeight.w900, fontSize: 18)),
                      )
                    else"""
    new = """                    if (_stage04LabMode)
                      if (DedaStage03LabStorage.storeLabMode &&
                          _stage04View!.activeId == _stage04View!.originalId)
                        DedaStage71FreeProfileFoil(
                          originalId: _stage04View!.originalId,
                          onCopy: _stage04CopyId,
                          fallback: GestureDetector(
                            onTap: _stage04CopyId,
                            child: Text(_stage04View!.activeId,
                              key: const Key('deda_stage04_verified_id'),
                              style: const TextStyle(color: Color(0xFFFFD76A),
                                fontWeight: FontWeight.w900, fontSize: 18)),
                          ),
                        )
                      else
                        GestureDetector(
                          onTap: _stage04CopyId,
                          child: Text(_stage04View!.activeId,
                            key: const Key('deda_stage04_verified_id'),
                            style: const TextStyle(color: Color(0xFFFFD76A),
                                fontWeight: FontWeight.w900, fontSize: 18)),
                        )
                    else"""
    # Use conditional expression rather than nested collection-if to preserve
    # the original else binding in the widget list.
    new = new.replace('                      if (DedaStage03LabStorage.storeLabMode &&\n                          _stage04View!.activeId == _stage04View!.originalId)\n',
        '                      (DedaStage03LabStorage.storeLabMode &&\n                          _stage04View!.activeId == _stage04View!.originalId)\n                      ? ')
    new = new.replace('                      else\n                        GestureDetector(', '                      : GestureDetector(')
    return once(source,old,new)


def bind(root):
    root = Path(root).resolve()
    if root == REPO or root in REPO.parents or REPO in root.parents:
        raise ValueError('STORE_DISPOSABLE_ONLY')
    lib=root/'lib'
    main=lib/'main.dart'
    original=main.read_text()
    if "DedaStage71FreeCardAction(" not in original or "DedaStage71FreeProfileFoil(" not in original:
        raise ValueError('STORE_APPROVED_FREE_CARD_ROUTE_REQUIRED')
    changes={
        main:patch_profile(original),
        lib/'deda_stage71_free_id_cards.dart':patch_cards((lib/'deda_stage71_free_id_cards.dart').read_text()),
        lib/'deda_owner18_frame_checkout.dart':patch_native_checkout((lib/'deda_owner18_frame_checkout.dart').read_text()),
        lib/'deda_lab_frame_secure_checkout.dart':patch_receipt_checkout((lib/'deda_lab_frame_secure_checkout.dart').read_text()),
    }
    for p,s in changes.items():
        pairs(tokens(s))
    for p,s in changes.items():
        p.write_text(s)
    print('PASS_STAGE04_STORE_ORIGINAL_FREE_CARDS_UID_JOURNAL_PAID_OWNERSHIP_PROTECTED_NO_NATIVE_DEBIT')


if __name__ == '__main__':
    bind(sys.argv[1])
