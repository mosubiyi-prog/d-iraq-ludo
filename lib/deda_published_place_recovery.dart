import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'deda_auth_session_runtime.dart';
import 'deda_session_transition_gate.dart';

class DedaPlaceRecoveryRejected implements Exception {
  const DedaPlaceRecoveryRejected(this.code);
  final String code;
}

class DedaPlaceRecoveryDocument {
  const DedaPlaceRecoveryDocument(this.id, this.data,
      {this.fromCache = false, this.pendingWrites = false});
  final String id;
  final Map<String, dynamic>? data;
  final bool fromCache, pendingWrites;
}

class DedaPlaceRecoveryQuery {
  const DedaPlaceRecoveryQuery(this.documents,
      {this.fromCache = false, this.pendingWrites = false});
  final List<DedaPlaceRecoveryDocument> documents;
  final bool fromCache, pendingWrites;
}

abstract class DedaPlaceRecoveryIo {
  bool get ready;
  DedaAuthSnapshot? get principal;
  Future<String?> currentInstallId();
  Future<DedaPlaceRecoveryDocument> readServer(String path);
  Future<DedaPlaceRecoveryQuery> publishedForAccount(String accountKey);
}

/// Uses the shared SDK epoch; never creates an installation, session, owner,
/// place or role. This adapter is only used by the default-off auth overlay.
class DedaFirebasePlaceRecoveryIo implements DedaPlaceRecoveryIo {
  @override
  bool get ready => DedaAuthRuntime.enabled && Firebase.apps.isNotEmpty;
  @override
  DedaAuthSnapshot? get principal => DedaAuthRuntime.capture();
  @override
  Future<String?> currentInstallId() async =>
      (await SharedPreferences.getInstance()).getString('deda_install_id_v1');
  @override
  Future<DedaPlaceRecoveryDocument> readServer(String path) async {
    final doc = await FirebaseFirestore.instance.doc(path)
        .get(const GetOptions(source: Source.server));
    return DedaPlaceRecoveryDocument(doc.id, doc.data(),
        fromCache: doc.metadata.isFromCache,
        pendingWrites: doc.metadata.hasPendingWrites);
  }
  @override
  Future<DedaPlaceRecoveryQuery> publishedForAccount(String accountKey) async {
    final query = await FirebaseFirestore.instance.collection('published_places')
        .where('accountKey', isEqualTo: accountKey)
        .where('published', isEqualTo: true).limit(2)
        .get(const GetOptions(source: Source.server));
    return DedaPlaceRecoveryQuery(query.docs.map((doc) =>
        DedaPlaceRecoveryDocument(doc.id, doc.data(),
            fromCache: doc.metadata.isFromCache,
            pendingWrites: doc.metadata.hasPendingWrites)).toList(growable: false),
        fromCache: query.metadata.isFromCache,
        pendingWrites: query.metadata.hasPendingWrites);
  }
}

/// Resolve one existing approved place after server account/install proof.
/// A public place or entered phone is not permission. Server rules continue to
/// authorize every owner action; recovery does not rewrite ownerUid or roles.
class DedaPublishedPlaceRecovery {
  DedaPublishedPlaceRecovery(this.io);
  final DedaPlaceRecoveryIo io;
  Future<Map<String, dynamic>?> recover({required String expectedAccountKey,
      required bool Function() isCurrent}) async {
    final account = expectedAccountKey.trim();
    final user = io.principal;
    if (!RegExp(r'^[0-9]+$').hasMatch(account) || !io.ready || user == null ||
        user.kind != DedaSessionAuthKind.anonymous || user.uid == null) {
      throw const DedaPlaceRecoveryRejected('owner-recovery-login-required');
    }
    void check() {
      final live = io.principal;
      if (!isCurrent() || !io.ready || live == null || !user.matches(live)) {
        throw const DedaStaleSessionTransition();
      }
    }
    Future<T> read<T>(Future<T> Function() action) async {
      check();
      try { final value = await action(); check(); return value; }
      catch (_) { check(); rethrow; }
    }
    Map<String, dynamic> verified(DedaPlaceRecoveryDocument document) {
      if (document.fromCache || document.pendingWrites || document.data == null) {
        throw const DedaPlaceRecoveryRejected('owner-recovery-unverified-document');
      }
      return document.data!;
    }
    final install = await read(io.currentInstallId);
    if (install == null || install.trim().isEmpty) {
      throw const DedaPlaceRecoveryRejected('owner-recovery-install-required');
    }
    final session = verified(await read(() => io.readServer('deda_sessions/${user.uid}')));
    if (session['uid'] != user.uid || session['accountKey'] != account ||
        session['installId'] != install) {
      throw const DedaPlaceRecoveryRejected('owner-recovery-session-mismatch');
    }
    final owner = verified(await read(() => io.readServer('users/${user.uid}')));
    if (owner['accountKey'] != account) {
      throw const DedaPlaceRecoveryRejected('owner-recovery-user-mismatch');
    }
    final query = await read(() => io.publishedForAccount(account));
    if (query.fromCache || query.pendingWrites) {
      throw const DedaPlaceRecoveryRejected('owner-recovery-unverified-query');
    }
    if (query.documents.length > 1) {
      throw const DedaPlaceRecoveryRejected('owner-recovery-ambiguous');
    }
    if (query.documents.isEmpty) return null;
    final document = query.documents.single;
    final data = verified(document);
    if (document.id.isEmpty || document.id.contains('/') ||
        data['accountKey'] != account || data['published'] != true) {
      throw const DedaPlaceRecoveryRejected('owner-recovery-invalid-record');
    }
    check();
    return <String, dynamic>{...data, 'id': document.id};
  }
}
