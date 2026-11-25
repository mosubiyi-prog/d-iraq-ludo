"""Add storage-only controls to a disposable copy of the verified stage02 runner."""
import json
import os
from pathlib import Path
import shutil
import sys
import stage01_lab_gate_2026_11_25 as gate
import stage02_lab_bind_entry_2026_11_25 as base

def once(text, old, new):
    gate.require(text.count(old) == 1, 'ENTRY_ANCHOR_MISMATCH')
    return text.replace(old, new, 1)

def prepare(root):
    root = Path(root).resolve()
    base.prepare(root, 'auth-runtime', json.loads(os.environ['LAB_CONFIG']))
    lib = root/'lib'
    for name in ('deda_private_data_sync.dart','deda_stage03_lab_uid_storage_2026_11_25.dart','deda_step2_local_places_settings_evidence.dart'):
        gate.require(not (lib/name).exists(), 'DUPLICATE_STORAGE')
        shutil.copyfile(gate.ROOT/'lib'/name,lib/name)
    entry=lib/base.ENTRY
    s=entry.read_text()
    s=once(s,"import 'deda_auth_session_runtime.dart';","import 'deda_auth_session_runtime.dart';\nimport 'deda_private_data_sync.dart';\nimport 'deda_stage03_lab_uid_storage_2026_11_25.dart';")
    s=once(s,'  @override\n  void dispose() {', '''  static final _first = DedaPrivateDataPayload(
      {'favorites': ['DEDA_STAGE03_LIVE_SYNTHETIC_ONLY_20261125']});
  static final _second = DedaPrivateDataPayload(
      {'favorites': ['DEDA_STAGE03_ANDROID_SYNTHETIC_ONLY_20261125']});
  Future<void> _storage(bool write) async {
    if (_busy || _observe() != 'UID_MATCHED_SERVER_UNVERIFIED') return;
    setState(() { _busy = true; _status = 'CHECKING_STORAGE'; });
    var status = 'BLOCKED_STORAGE';
    try {
      final r = await DedaStage03LabStorage.restore();
      final rev = r.revision;
      if (r.status != DedaPrivateDataStatus.saved) {
        throw StateError('restore not confirmed');
      }
      if (rev.version == 2 && rev.payload?.encode() == _second.encode()) {
        status = write ? 'EXACT_V2_ALREADY_PRESENT_NO_WRITE' : 'RESTORE_V2_OK';
      } else if (rev.version == 1 && rev.payload?.encode() == _first.encode()) {
        if (!write) {
          status = 'RESTORE_V1_OK';
        } else {
          final saved = await DedaStage03LabStorage.backup(_second);
          if (saved.status != DedaPrivateDataStatus.saved ||
              saved.revision.version != 2 ||
              saved.revision.payload?.encode() != _second.encode()) {
            throw StateError('backup not confirmed');
          }
          status = 'BACKUP_V2_CONFIRMED';
        }
      } else {
        throw StateError('unknown remote revision; no overwrite');
      }
    } catch (_) {
      status = 'BLOCKED_STORAGE';
    } finally {
      if (mounted) setState(() { _busy = false; _status = status; });
    }
  }
  @override
  void dispose() {''')
    s=once(s,"child: const Text('VERIFY_SERVER')),","child: const Text('VERIFY_SERVER')),\n        ElevatedButton(onPressed: _busy ? null : () => _storage(false),\n          child: const Text('RESTORE_STORAGE')),\n        ElevatedButton(onPressed: _busy ? null : () => _storage(true),\n          child: const Text('BACKUP_STORAGE')),")
    s=once(s,'DEDA LAB — PHASE 02','DEDA LAB — PHASE 03')
    entry.write_text(s)
    pub=root/'pubspec.yaml'
    pub.write_text(once(pub.read_text(),'  firebase_auth: 5.7.0\n','  firebase_auth: 5.7.0\n  cloud_firestore: 5.6.12\n  shared_preferences: 2.5.3\n'))
    print('PASS_DISPOSABLE_STAGE03_BINDS_EXISTING_DART_ENGINE_NO_FULL_APP')

if __name__=='__main__':
    try:
        prepare(sys.argv[1])
    except Exception as exc:
        print('BLOCK_STAGE03_BIND',type(exc).__name__)
        raise SystemExit(1) from None
