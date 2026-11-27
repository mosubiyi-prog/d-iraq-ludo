import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'deda_auth_session_runtime.dart';
import 'deda_stage02_lab_options_2026_11_25.dart';
import 'deda_stage02_lab_single_uid_2026_11_25.dart';

const _runner = bool.fromEnvironment('DEDA_STAGE02_DISPOSABLE_RUNNER');
const _uid = DedaStage02LabSingleUid.approvedUid;

// No original DEDA startup, legacy preferences, Firestore or admin routes.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    if (Firebase.apps.isNotEmpty) {
      throw StateError('unexpected preinitialized app');
    }
    final app = await Firebase.initializeApp(options: stage02LabOptions)
        .timeout(const Duration(seconds: 5));
    DedaStage02LabSingleUid.requireLab(app);
    await FirebaseAuth.instanceFor(app: app).authStateChanges().first
        .timeout(const Duration(seconds: 10));
    runApp(const MaterialApp(home: _LabPage()));
  } catch (_) {
    runApp(const MaterialApp(home: Scaffold(body: Center(
        child: Text('BLOCKED_STAGE02_CONFIG_OR_AUTH_INIT')))));
  }
}

class _LabPage extends StatefulWidget {
  const _LabPage();
  @override
  State<_LabPage> createState() => _LabPageState();
}

class _LabPageState extends State<_LabPage> with WidgetsBindingObserver {
  final _password = TextEditingController();
  StreamSubscription<User?>? _subscription;
  String _status = 'CHECKING';
  bool _busy = false;
  String _observe() {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return 'SIGNED_OUT_NO_ADMISSION';
      return DedaStage02LabSingleUid.inspect(expectedUid: _uid) == _uid &&
          user.email == DedaStage02LabSingleUid.approvedEmail
          ? 'UID_MATCHED_SERVER_UNVERIFIED' : 'BLOCKED_WRONG_PRINCIPAL';
    } catch (_) {
      return 'BLOCKED_SESSION_INSPECTION';
    }
  }
  void _invalidate() {
    if (mounted && !_busy) setState(() => _status = _observe());
  }
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _status = _observe();
    _subscription = FirebaseAuth.instance.authStateChanges().listen(
        (_) => _invalidate(), onError: (Object _) {
      if (mounted) setState(() => _status = 'BLOCKED_AUTH_OBSERVER');
    });
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _invalidate();
  }
  Future<void> _login() async {
    if (_busy || _observe() != 'SIGNED_OUT_NO_ADMISSION') return;
    setState(() { _busy = true; _status = 'CHECKING'; });
    String? password;
    try {
      if (_runner) {
        // Disposable CI only: private app file, never embedded in APK.
        final file = File('/data/data/com.deda.qa.uiddevice/files/stage02-qa-password');
        try { password = await file.readAsString(); }
        finally { if (await file.exists()) await file.delete(); }
      } else {
        password = _password.text;
        _password.clear();
      }
      await DedaStage02LabSingleUid.loginExisting(expectedUid: _uid,
        email: DedaStage02LabSingleUid.approvedEmail, password: password!,
        explicitUserAction: true);
      if (mounted) setState(() => _status = _observe());
    } catch (_) {
      if (mounted) setState(() => _status =
          _observe() == 'SIGNED_OUT_NO_ADMISSION'
              ? 'LOGIN_REJECTED_NO_ADMISSION' : _observe());
    } finally {
      password = null;
      if (mounted) setState(() => _busy = false);
    }
  }
  Future<void> _verify() async {
    if (_busy || _observe() != 'UID_MATCHED_SERVER_UNVERIFIED') return;
    setState(() { _busy = true; _status = 'CHECKING'; });
    try {
      final snapshot = await DedaStage02LabSingleUid.verifyServer(expectedUid: _uid);
      DedaAuthRuntime.checkSnapshot(snapshot);
      if (_observe() != 'UID_MATCHED_SERVER_UNVERIFIED') {
        throw StateError('no server proof');
      }
      if (mounted) setState(() => _status = 'UID_SERVER_VERIFIED');
    } catch (_) {
      if (mounted) setState(() => _status =
          _observe() == 'UID_MATCHED_SERVER_UNVERIFIED'
              ? 'UID_RETAINED_SERVER_UNAVAILABLE' : _observe());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _subscription?.cancel();
    _password.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('DEDA LAB — PHASE 02')),
    body: SafeArea(child: Center(child: SingleChildScrollView(child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('ALL_SECTIONS_HELD'),
        Text(_status),
        if (!_runner) TextField(controller: _password, obscureText: true,
          enableSuggestions: false, autocorrect: false,
          decoration: const InputDecoration(labelText: 'Lab password only')),
        ElevatedButton(onPressed: _busy ? null : _login,
          child: const Text('LOGIN_EXISTING')),
        ElevatedButton(onPressed: _busy ? null : _verify,
          child: const Text('VERIFY_SERVER')),
      ]),
    )))),
  );
}
