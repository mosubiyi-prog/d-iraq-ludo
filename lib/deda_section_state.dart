import 'dart:async';
import 'package:flutter/material.dart';
import 'deda_auth_session_runtime.dart';
import 'deda_backend.dart';
import 'deda_protected_section_entry.dart';
import 'deda_section_operation_context.dart';
import 'main.dart' show DedaPreferences, dedaText;
enum _UnavailableSectionPrincipal { value }

/// One notification per explicit account selection, including A -> B -> A.
/// It contains no account identifiers and is not a source of authorization.
class DedaSectionAccountChanges {
  static final epoch = ValueNotifier<int>(0);
  static void changed() => epoch.value++;
}

mixin DedaSectionState<T extends StatefulWidget> on State<T> {
  late final String _sectionAccount;
  late final int _sectionEpoch;
  bool _sectionDisposed = false;
  bool get dedaSectionCurrent => mounted && !_sectionDisposed &&
      (!dedaProtectedSectionEntryEnabled ||
       (_sectionEpoch == DedaPreferences.stabilityAccountEpoch &&
        _sectionAccount == DedaBackend.accountKeyForPhone(DedaPreferences.phone)));

  @override
  void initState() {
    super.initState();
    _sectionAccount = DedaBackend.accountKeyForPhone(DedaPreferences.phone);
    _sectionEpoch = DedaPreferences.stabilityAccountEpoch;
    DedaSectionAccountChanges.epoch.addListener(_accountChanged);
  }

  void _accountChanged() {
    if (mounted && !_sectionDisposed && dedaProtectedSectionEntryEnabled) {
      // Deliberately bypass the stale-result setState guard: remove old-account
      // controls/StreamBuilders immediately on the following frame.
      super.setState(() {});
    }
  }

  @override
  void dispose() {
    _sectionDisposed = true;
    DedaSectionAccountChanges.epoch.removeListener(_accountChanged);
    super.dispose();
  }

  @override
  void setState(VoidCallback fn) {
    if (!dedaProtectedSectionEntryEnabled || dedaSectionCurrent) super.setState(fn);
  }

  Object? _principal() {
    try {
      final value = DedaAuthRuntime.capture();
      return (value?.uid, value?.kind, value?.epoch);
    } catch (_) {
      // Let the original backend preparation surface its normal error/retry
      // UI. This token proves no authority and cannot turn a failed SDK
      // observer into a successful owner/admin session.
      return _UnavailableSectionPrincipal.value;
    }
  }

  Future<R> dedaRunSection<R>(Future<R> Function() action) {
    if (!dedaProtectedSectionEntryEnabled) return action();
    if (!DedaAuthRuntime.enabled) {
      throw StateError('section-entry-requires-auth-runtime');
    }
    return DedaSectionOperationContext.run(owner: this,
      isCurrent: () => dedaSectionCurrent, principal: _principal, action: action);
  }

  Future<void> dedaRunSectionVoid(Future<void> Function() action) {
    if (!dedaProtectedSectionEntryEnabled) return action();
    if (!DedaAuthRuntime.enabled) {
      throw StateError('section-entry-requires-auth-runtime');
    }
    return DedaSectionOperationContext.runVoid(owner: this,
      isCurrent: () => dedaSectionCurrent, principal: _principal, action: action);
  }

  void Function(A, B) dedaSectionCallback2<A, B>(void Function(A, B) action) => (a, b) {
    if (!dedaProtectedSectionEntryEnabled) { action(a, b); return; }
    unawaited(dedaRunSectionVoid(() async { action(a, b); }));
  };

  Widget dedaSectionExpiredView() => Center(child: Padding(
    padding: const EdgeInsets.all(16),
    child: Text(dedaText('تغيّر الحساب. ارجع وافتح هذا القسم من جديد.',
      'The account changed. Go back and reopen this section.'),
      textAlign: TextAlign.center),
  ));
}

/// Gives formerly stateless pages the same account lifetime, including their
/// StreamBuilders and context-taking administrative event methods.
class DedaSectionBoundary extends StatefulWidget {
  const DedaSectionBoundary({super.key, required this.builder});
  final WidgetBuilder builder;
  static _DedaSectionBoundaryState _scope(BuildContext context) {
    if (!context.mounted) throw const DedaSectionOperationExpired();
    final scope = context.getInheritedWidgetOfExactType<_SectionScope>();
    if (scope == null) throw StateError('section-context-missing');
    return scope.section;
  }
  static Future<R> runForContext<R>(BuildContext context, Future<R> Function() action) {
    if (!dedaProtectedSectionEntryEnabled) return action();
    return _scope(context).dedaRunSection(action);
  }
  static Future<void> runVoidForContext(BuildContext context, Future<void> Function() action) async {
    if (!dedaProtectedSectionEntryEnabled) return action();
    if (!context.mounted) {
      if (DedaSectionOperationContext.hasCurrent) throw const DedaSectionOperationExpired();
      return;
    }
    return _scope(context).dedaRunSectionVoid(action);
  }
  @override
  State<DedaSectionBoundary> createState() => _DedaSectionBoundaryState();
}

class _DedaSectionBoundaryState extends State<DedaSectionBoundary>
    with DedaSectionState<DedaSectionBoundary> {
  @override
  Widget build(BuildContext context) {
    if (!dedaSectionCurrent) return dedaSectionExpiredView();
    return _SectionScope(section: this, child: Builder(builder: widget.builder));
  }
}

class _SectionScope extends InheritedWidget {
  const _SectionScope({required this.section, required super.child});
  final _DedaSectionBoundaryState section;
  @override
  bool updateShouldNotify(_SectionScope oldWidget) => section != oldWidget.section;
}
