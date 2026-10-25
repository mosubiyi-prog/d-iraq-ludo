import 'dart:async';

/// Concurrency checks only. Never grants an account, role, balance or ownership.
/// The selected account and the SDK principal remain independent evidence.
class DedaSectionOperationContext {
  DedaSectionOperationContext._(this.owner, this.isCurrent, this.principal, this.parent)
      : _expectedPrincipal = principal();
  static final Object _zoneKey = Object();
  final Object owner;
  final bool Function() isCurrent;
  final Object? Function() principal;
  final DedaSectionOperationContext? parent;
  Object? _expectedPrincipal;

  static DedaSectionOperationContext? get _current {
    final value = Zone.current[_zoneKey];
    return value is DedaSectionOperationContext ? value : null;
  }
  static bool get hasCurrent => _current != null;

  static void checkCurrent() {
    final context = _current;
    if (context != null && (!context.isCurrent() ||
        context._expectedPrincipal != context.principal())) {
      throw const DedaSectionOperationExpired();
    }
  }

  /// Only the shared auth lane calls this after verifying the result of its
  /// own SDK mutation. It cannot adopt an account-selection change.
  static void adoptVerifiedPrincipal() {
    final context = _current;
    if (context == null) return;
    if (!context.isCurrent()) throw const DedaSectionOperationExpired();
    final previous = context._expectedPrincipal;
    final adopted = context.principal();
    context._expectedPrincipal = adopted;
    var ancestor = context.parent;
    while (ancestor != null && ancestor.isCurrent() &&
        ancestor._expectedPrincipal == previous) {
      ancestor._expectedPrincipal = adopted;
      ancestor = ancestor.parent;
    }
  }

  static Future<T> run<T>({required Object owner,
    required bool Function() isCurrent,
    required Object? Function() principal,
    required Future<T> Function() action}) async {
    final inherited = _current;
    checkCurrent();
    if (inherited != null && identical(inherited.owner, owner)) {
      checkCurrent();
      final result = await action();
      checkCurrent();
      return result;
    }
    final context = DedaSectionOperationContext._(owner, isCurrent, principal, inherited);
    return runZoned(() async {
      checkCurrent();
      final result = await action();
      checkCurrent();
      return result;
    }, zoneValues: {_zoneKey: context});
  }

  static Future<void> runVoid({required Object owner,
    required bool Function() isCurrent,
    required Object? Function() principal,
    required Future<void> Function() action}) async {
    final nested = _current != null;
    try {
      await run<void>(owner: owner, isCurrent: isCurrent,
          principal: principal, action: action);
    } on DedaSectionOperationExpired {
      // Only a top-level UI event may silently finish after its page expires.
      // Nested calls must throw so the caller cannot continue a write chain.
      if (nested) rethrow;
    }
  }

  static Future<T> wait<T>(FutureOr<T> Function() action) async {
    checkCurrent();
    try {
      final value = await action();
      checkCurrent();
      return value;
    } catch (_) {
      checkCurrent();
      rethrow;
    }
  }

  static Stream<T> guardStream<T>(Stream<T> source) async* {
    checkCurrent();
    await for (final event in source) {
      checkCurrent();
      yield event;
    }
    checkCurrent();
  }
}

class DedaSectionOperationExpired implements Exception {
  const DedaSectionOperationExpired();
}
