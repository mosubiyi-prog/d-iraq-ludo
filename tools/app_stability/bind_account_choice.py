"""Bind only the free cosmetic choice, keeping ownership and wallets untouched."""
from pathlib import Path


def bind(output):
    path=Path(output)/'lib/deda_stage71_free_id_cards.dart'
    source=path.read_text()
    if 'DEDA_ACCOUNT_CHOICE_BOUND_V1' in source:
        raise ValueError('Account choice already bound')
    restore='''    final value = prefs.getString(key);
    if ((_versions[originalId] ?? 0) != previousVersion) return;'''
    replacement='''    var value = prefs.getString(key);
    if (dedaAccountChoiceSyncEnabled) {
      value = await DedaFreeCardSyncBridge.restore(originalId);
    }
    if ((_versions[originalId] ?? 0) != previousVersion) return;'''
    use='''    final key = _key(originalId);
    final prefs = await SharedPreferences.getInstance();
    final saved = await prefs.setString(key, choice.name);'''
    updated='''    final key = _key(originalId);
    if (dedaAccountChoiceSyncEnabled) {
      final version = (_versions[originalId] ?? 0) + 1;
      _versions[originalId] = version;
      await DedaFreeCardSyncBridge.use(originalId, choice.name);
      if ((_versions[originalId] ?? 0) == version) notifier(originalId).value = choice;
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final saved = await prefs.setString(key, choice.name);'''
    if source.count(restore)!=1 or source.count(use)!=1:
        raise ValueError('Exact original free card entry required')
    source=source.replace(restore,replacement,1).replace(use,updated,1)
    disabled='onPressed: _busy || active == widget.color ? null : _use,'
    label="active == widget.color ? 'مستخدمة حاليًا' : 'استخدام مجاني',"
    if source.count(disabled)!=1 or source.count(label)!=1:
        raise ValueError('Exact original free card action required')
    source=source.replace(disabled,'''onPressed: _busy || (active == widget.color &&
              (!dedaAccountChoiceSyncEnabled || DedaFreeCardSyncBridge.statusFor(widget.originalId) == DedaChoiceSyncStatus.saved)) ? null : _use,''',1)
    source=source.replace(label,'''active == widget.color
              ? (dedaAccountChoiceSyncEnabled && DedaFreeCardSyncBridge.statusFor(widget.originalId) != DedaChoiceSyncStatus.saved
                  ? 'حفظ للحساب' : 'مستخدمة حاليًا') : 'استخدام مجاني',''',1)
    path.write_text("// DEDA_ACCOUNT_CHOICE_BOUND_V1\nimport 'deda_account_choice_sync.dart';\nimport 'deda_free_card_sync_bridge.dart';\n"+source)
