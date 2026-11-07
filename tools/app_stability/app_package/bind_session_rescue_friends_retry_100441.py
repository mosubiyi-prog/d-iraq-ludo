#!/usr/bin/env python3
"""Owner-approved stage4/point1 friends retry fix on DISPOSABLE full DEDA 100440.

Run strictly AFTER bind_session_rescue_stage3_100441.py in a disposable
assembled workspace. This binder touches only its temporary lib/main.dart.
The old wallet, leagues, gifts, manager auth, accounts and 100440 remain intact.
"""
from __future__ import annotations

import argparse
import re
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
    target = re.search(r'class\s+_DedaFriendsPageState\b[^{]{0,300}\{', whole)
    if target is None:
        matches = re.findall(r'class\s+[^\n{]{0,110}(?:Friend|Social)[^\n{]*', whole)
        print('DEDA_FRIENDS_ASSEMBLED_CLASSES', matches[:45])
        raise ValueError('BLOCK_FRIENDS_RETRY_FRIENDS_STATE_NOT_FOUND')
    start = target.start()
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

    # Leave the assembled owner initialization body BIT FOR BIT as it is.
    # Rename it and wrap with a bounded, visible retry rather than replacing
    # previously reviewed account/session rules from other build stages.
    friends = once(
        friends,
        "  Future<void> _prepare() async {",
        "  Future<void> _prepareOriginal() async {",
        "preserve original friends session initializer",
    )
    friends = once(
        friends,
        """  @override
  void initState() {
    super.initState();""",
        """  @override
  void initState() {
    super.initState();
    if (dedaSessionRescueStage3Enabled) {
      DedaSessionRescueStage3Bridge.updates.addListener(_onRescueReady);
    }""",
        "one readiness listener on friends init",
    )
    before_original = "  Future<void> _prepareOriginal() async {"
    wrapper = """  void _onRescueReady() {
    if (!mounted || _loadingFriends || !dedaSessionRescueStage3Enabled) return;
    final proof = DedaSessionRescueStage3Bridge.updates.value;
    final viewer = FirebaseAuth.instance.currentUser;
    final expectedOriginal = DedaBackend.personalShareIdForPhone(
      DedaPreferences.phone,
    );
    if (proof?.status != DedaRescueStatus.ready ||
        viewer == null || proof?.uid != viewer.uid ||
        proof?.originalId != expectedOriginal) return;
    // The already verified SAME-UID event reloads only the existing friend
    // reader. Do not call the rescue again from its own event.
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
    // The tap MUST produce immediate visual feedback. Clear old error and
    // stream so the same terminal StreamBuilder failure isn't replayed.
    setState(() {
      _loadingFriends = true;
      _session = null;
      _relationsStream = null;
      _error = null;
    });
    try {
      if (dedaSessionRescueStage3Enabled && startUid == null) {
        throw StateError('deda-friends-original-session-required');
      }
      if (dedaSessionRescueStage3Enabled && !ownerProofAlreadyReady) {
        final recovery = await DedaSessionRescueStage3Bridge.runForPhone(
          DedaPreferences.phone,
        );
        if (recovery?.status == DedaRescueStatus.uidChanged ||
            recovery?.status == DedaRescueStatus.signedOut) {
          throw StateError('deda-friends-owner-session-changed');
        }
      }
      if (!mounted || generation != _friendsGeneration) return;
      if (dedaSessionRescueStage3Enabled &&
          FirebaseAuth.instance.currentUser?.uid != startUid) {
        throw StateError('deda-friends-auth-changed-before-original-read');
      }
      await _prepareOriginal();
      if (!mounted || generation != _friendsGeneration) return;
      // The original initializer may catch an auth/network failure itself.
      // Treat null _session as ERROR, never an empty friend list.
      final verified = _session;
      if (verified == null) {
        throw _error ?? StateError('deda-friends-session-not-ready');
      }
      final liveUid = FirebaseAuth.instance.currentUser?.uid;
      if (liveUid != verified.uid ||
          (dedaSessionRescueStage3Enabled && liveUid != startUid)) {
        throw StateError('deda-friends-owner-uid-changed');
      }
      final latest = DedaSocialService.watchRelations(verified.uid);
      if (mounted && generation == _friendsGeneration) {
        setState(() {
          _relationsStream = latest;
          _error = null;
        });
      }
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
    friends = once(
        friends, before_original, wrapper + before_original,
        "wrap original friends loader, not replace",
    )

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
    improved_error_ui = """      body: _loadingFriends || session == null
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
