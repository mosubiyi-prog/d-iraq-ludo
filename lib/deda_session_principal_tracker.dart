import 'deda_session_flow_prototype.dart';
import 'deda_session_transition_gate.dart';

/// One shared observer per FirebaseAuth instance, independent of user intent.
class DedaSessionPrincipalTracker {
  String? _uid;
  DedaSessionAuthKind _kind = DedaSessionAuthKind.none;
  int _revision = 0;

  DedaFlowSdkUser? observe(String? uid, DedaSessionAuthKind kind) {
    final nextKind = uid == null ? DedaSessionAuthKind.none : kind;
    if (uid != _uid || nextKind != _kind) {
      _uid = uid;
      _kind = nextKind;
      _revision++;
    }
    if (uid == null) return null;
    return DedaFlowSdkUser(uid, nextKind, _revision);
  }
}
