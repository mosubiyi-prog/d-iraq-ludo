import 'deda_account_choice_sync.dart';
import 'deda_account_choice_firebase.dart';
import 'deda_auth_session_runtime.dart';
import 'deda_backend.dart';
import 'deda_section_operation_context.dart';
import 'main.dart' show DedaPreferences;

/// Bound only in the restored section-entry app. The switch remains OFF until
/// its additive rules and this client are approved together for production.
class DedaFreeCardSyncBridge {
  static final DedaAccountChoiceSync _sync=DedaAccountChoiceSync(DedaFirebaseAccountChoiceIo());
  static final Map<String,DedaChoiceSyncStatus> _statuses={};
  static DedaChoiceSyncStatus statusFor(String original) => _statuses[original]??DedaChoiceSyncStatus.local;
  static Future<String?> restore(String original) => _run(original,null);
  static Future<void> use(String original,String value) async {await _run(original,value);}
  static Future<String?> _run(String original,String? selected) async {
    if(!DedaAuthRuntime.enabled) throw StateError('choice-sync-requires-shared-auth');
    final account=DedaBackend.accountKeyForPhone(DedaPreferences.phone);
    final epoch=DedaPreferences.stabilityAccountEpoch;
    final snapshot=DedaAuthRuntime.capture();
    bool current() {
      try {
        DedaSectionOperationContext.checkCurrent();
        final live=DedaAuthRuntime.capture();
        return DedaPreferences.isLoggedIn && DedaPreferences.stabilityAccountEpoch==epoch &&
          account==DedaBackend.accountKeyForPhone(DedaPreferences.phone) &&
          snapshot!=null && live!=null && snapshot.matches(live);
      } catch (_) {return false;}
    }
    return DedaAuthRuntime.run<String?>(kind:DedaSessionTransitionKind.sessionInspection,
      isCurrent:current, action:() async {
        bool permitted() {
          try {DedaAuthRuntime.check();return current();} catch (_) {return false;}
        }
        final result=selected==null
          ?await _sync.restore(account:account,original:original,isCurrent:permitted)
          :await _sync.use(account:account,original:original,value:selected,isCurrent:permitted);
        _statuses[original]=result.status;
        return result.value;
      });
  }
}
