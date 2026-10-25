# Atomic closed-transaction recovery — 25 October 2026 Baghdad

Status: local Node396/396 passed; new source/Emulator CI pending. Server-internal, undeployed. No client Dart/auth SDK package changed.

Evidence: run40200445729 again failed the same actual-Auth two-owner-UID concurrent claim with3 INVALID_ARGUMENT: Transaction is invalid or closed (202/203). Previous root-first ordering alone is not a fully demonstrated cure. Historical Firebase-maintainer issue https://github.com/firebase/firebase-tools/issues/4473 documents the same error family; that history alone does not establish this run's exact emulator/internal cause.

DedaTrustedProgressTransactionStore now permits ONE extra fresh full SDK transaction for code3 and the exact known closed message/details, after the former transaction Future has settled. Other invalid data, permission errors, unavailable and arbitrary application exceptions do not trigger this extra loop. Normal SDK transaction retry behavior remains inside each SDK call. This is not a purchase/provider retry or individual write replay. Like any SDK transaction callback, actions may contain transactional reads/writes and repeatable verification reads only, with no external side effects.

Each rerun executes all original authorization/evidence reads again. Existing protected event/claim markers reconcile an already committed but lost result and return current state rather than awarding again. No original timestamp/receipt or baseline is reset. A second closed result stops and propagates the error. Fresh owner SDK disabled/revoked or changed proof still blocks further writes.

Eight new Node boundary cases cover no-commit closure, ambiguous committed closure, bounded termination, four unrelated/nonclosed errors, and reverified authority. Four new actual Auth/Firestore cases inject closure before/after a real Admin SDK transaction, repeat closure and disable the actual synthetic user between attempts. The original concurrent-UID assertion stays unchanged. Final CI result is pending and must not be inferred from local counts.
