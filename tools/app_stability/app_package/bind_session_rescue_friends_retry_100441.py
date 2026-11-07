#!/usr/bin/env python3
"""Owner-approved stage4/point1 friends retry fix on DISPOSABLE full DEDA 100440.

Run strictly AFTER bind_session_rescue_stage3_100441.py in a disposable
assembled workspace. This binder touches only its temporary lib/main.dart.
The old wallet, leagues, gifts, manager auth, accounts and 100440 remain intact.
"""
from __future__ import annotations

import argparse
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]


def once(source: str, before: str, after: str, purpose: str) -> str:
    amount = source.count(before)
    if amount != 1:
        raise ValueError(f"BLOCK_FRIENDS_RETRY_SOURCE_ANCHOR:{purpose}:{amount}")
    return source.replace(before, after, 1)


def bind(project: Path) -> None:
    project = Path(project).resolve()
    if project == ROOT or ROOT in project.parents or project in ROOT.parents:
        raise ValueError("BLOCK_FRIENDS_RETRY_NEVER_EDIT_REPO_REFERENCE")
    file = project / "lib" / "main.dart"
    if not file.is_file():
        raise ValueError("BLOCK_FRIENDS_RETRY_MISSING_ASSEMBLED_MAIN")
    whole = file.read_text()
    if "DEDA_100441_FRIENDS_RETRY_FIX" in whole:
        raise ValueError("BLOCK_FRIENDS_RETRY_DUPLICATE")
    if "DedaSessionRescueStage3Bridge.runForPhone" not in whole:
        raise ValueError("BLOCK_FRIENDS_RETRY_STAGE3_NOT_PRESENT")
    start = whole.index("class _DedaFriendsPageState extends State<DedaFriendsPage> {")
    end = whole.index("class _DedaFriendCompactCard", start)
    friends = whole[start:end]

    friends = once(
        friends,
        """  DedaSocialSession? _session;
  Object? _error;
  String _query = '';""",
        """  DedaSocialSession? _session;
  Object? _error;
  String _query = '';
  // DEDA_100441_FRIENDS_RETRY_FIX: a stable stream, same-owner generation
  // protection, and one in-flight user-visible retry (no duplicate polling).
  Stream<List<DedaFriendshipRecord>>? _relationsStream;
  bool _loadingFriends = false;
  int _friendsGeneration = 0;""",
        "friend state",
    )

    original = """  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    try {
      final session = await dedaEnsurePersonalSocialSession();
      if (!mounted) return;
      setState(() {
        _session = session;
        _error = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }
"""
    improved = """  @override
  void initState() {
    super.initState();
    if (dedaSessionRescueStage3Enabled) {
      DedaSessionRescueStage3Bridge.updates.addListener(_onRescueReady);
    }
    unawaited(_prepare());
  }

  void _onRescueReady() {
    if (!mounted || _loadingFriends || !dedaSessionRescueStage3Enabled) {
      return;
    }
    final report = DedaSessionRescueStage3Bridge.updates.value;
    final viewer = FirebaseAuth.instance.currentUser;
    final original = DedaBackend.personalShareIdForPhone(
      DedaPreferences.phone,
    );
    if (report?.status != DedaRescueStatus.ready ||
        viewer == null || report?.uid != viewer.uid ||
        report?.originalId != original) return;
    // A successful SAME-UID owner proof reopens the original friends reader.
    // Do not invoke the rescue again from its own readiness event.
    unawaited(_prepare(ownerProofAlreadyReady: true));
  }

  @override
  void dispose() {
    _friendsGeneration++;
    if (dedaSessionRescueStage3Enabled) {
      DedaSessionRescueStage3Bridge.updates.removeListener(_onRescueReady);
    }
    super.dispose();
  }

  Future<void> _prepare({bool ownerProofAlreadyReady = false}) async {
    if (_loadingFriends) return;
    final generation = ++_friendsGeneration;
    final startUid = Firebase.apps.isEmpty
        ? null : FirebaseAuth.instance.currentUser?.uid;
    // Show feedback synchronously on tap, even when the prior Firebase
    // handshake is still failing. Stale 0 friends is never our error UI.
    setState(() {
      _loadingFriends = true;
      _session = null;
      _relationsStream = null;
      _error = null;
    });
    try {
      // The rescuer MUST NOT create an anonymous replacement UID. A missing
      // principal needs the existing explicit DEDA account confirmation.
      if (dedaSessionRescueStage3Enabled && startUid == null) {
        throw StateError('deda-friends-original-session-required');
      }
      if (dedaSessionRescueStage3Enabled && !ownerProofAlreadyReady) {
        final rescue = await DedaSessionRescueStage3Bridge.runForPhone(
          DedaPreferences.phone,
        );
        if (rescue?.status == DedaRescueStatus.uidChanged ||
            rescue?.status == DedaRescueStatus.signedOut) {
          throw StateError('deda-friends-owner-session-changed');
        }
      }
      if (!mounted || generation != _friendsGeneration) return;
      if (dedaSessionRescueStage3Enabled &&
          FirebaseAuth.instance.currentUser?.uid != startUid) {
        throw StateError('deda-friends-auth-changed-during-retry');
      }
      final verified = await dedaEnsurePersonalSocialSession();
      if (!mounted || generation != _friendsGeneration) return;
      final liveUid = FirebaseAuth.instance.currentUser?.uid;
      if (liveUid != verified.uid ||
          (dedaSessionRescueStage3Enabled && liveUid != startUid)) {
        throw StateError('deda-friends-verified-owner-changed');
      }
      // Creating this new stream forces a genuine Firestore re-subscription
      // only for this retry, not on every widget rebuild.
      final stream = DedaSocialService.watchRelations(verified.uid);
      setState(() {
        _session = verified;
        _relationsStream = stream;
        _error = null;
      });
    } catch (error) {
      if (mounted && generation == _friendsGeneration) {
        setState(() {
          _session = null;
          _relationsStream = null;
          _error = error;
        });
      }
    } finally {
      if (mounted && generation == _friendsGeneration) {
        setState(() => _loadingFriends = false);
      }
    }
  }
"""
    friends = once(friends, original, improved, "friends retry button load")

    original_error_ui = """      body: session == null
          ? Center(
              child: _error == null
                  ? const CircularProgressIndicator()
                  : FilledButton.icon(
                      onPressed: _prepare,
                      icon: const Icon(Icons.refresh_rounded),
                      label: Text(dedaText('إعادة المحاولة', 'Retry')),
                    ),
            )
          : StreamBuilder<List<DedaFriendshipRecord>>(
              stream: DedaSocialService.watchRelations(session.uid),
              builder: (context, snapshot) {
                final friends ="""
    improved_error_ui = """      body: session == null
          ? Center(
              child: _loadingFriends || _error == null
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        const CircularProgressIndicator(),
                        const SizedBox(height: 12),
                        Text(dedaText(
                          'جارٍ إعادة الاتصال وتحميل الأصدقاء...',
                          'Reconnecting and loading friends...',
                        )),
                      ],
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(dedaText(
                          'تعذر تحميل الأصدقاء. تأكد من الاتصال أو تأكيد حسابك.',
                          'Friends could not load. Check your connection or account.',
                        ), textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: _loadingFriends
                              ? null : () => unawaited(_prepare()),
                          icon: const Icon(Icons.refresh_rounded),
                          label: Text(dedaText('إعادة المحاولة', 'Retry')),
                        ),
                      ],
                    ),
            )
          : StreamBuilder<List<DedaFriendshipRecord>>(
              stream: _relationsStream,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(dedaText(
                        'فشل تحديث قائمة الأصدقاء. أعد المحاولة.',
                        'Could not update friends. Please retry.',
                      ), textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: _loadingFriends
                            ? null : () => unawaited(_prepare()),
                        icon: const Icon(Icons.refresh_rounded),
                        label: Text(dedaText('إعادة المحاولة', 'Retry')),
                      ),
                    ],
                  ));
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final friends ="""
    friends = once(friends, original_error_ui, improved_error_ui, "friends Firestore error plus real retry")

    old_count = """                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (DedaSocialFriendCount.notifier.value != friends.length) {
                    DedaSocialFriendCount.notifier.value = friends.length;
                  }
                });"""
    new_count = """                // The badge counts all server-confirmed accepted relations,
                // not filtered search results. A failed read never sets 0.
                final verifiedCount = snapshot.data!
                    .where((item) => item.status == 'accepted').length;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted || FirebaseAuth.instance.currentUser?.uid !=
                      session.uid) return;
                  if (DedaSocialFriendCount.notifier.value != verifiedCount) {
                    DedaSocialFriendCount.notifier.value = verifiedCount;
                  }
                });"""
    friends = once(friends, old_count, new_count, "friends count only after server data")

    if friends.count("DedaSocialService.watchRelations(verified.uid)") != 1:
        raise ValueError("BLOCK_FRIENDS_RETRY_STREAM_NOT_FRESH")
    if "signInAnonymously(" in friends or "signOut(" in friends:
        raise ValueError("BLOCK_FRIENDS_RETRY_MUTATES_AUTH")
    if "onPressed: _prepare" in friends:
        raise ValueError("BLOCK_FRIENDS_RETRY_OLD_BUTTON_SURVIVES")
    # No main write until ALL exact friend-state and button anchors pass.
    file.write_text(whole[:start] + friends + whole[end:])
    print("PASS_FRIENDS_RETRY_REAL_BUTTON_BUSY_ERROR_STREAM_REFRESH_OWNER_UID_NO_BUILD")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("project", type=Path)
    bind(parser.parse_args().project)
