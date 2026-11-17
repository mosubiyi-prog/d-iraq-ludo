#!/usr/bin/env python3
"""Guarded point2 source integration into the disposable FULL DEDA 100447 app.

The full assembler has already transformed social relationships to use the
immutable personal DEDA public ID, wrapped section operations, and extended
cosmetic ranges. NEVER copy or three-way merge raw social source over those
features. Patch only exact reviewed operations. Fail closed on any ambiguity.
"""
import argparse
import hashlib
import json
import re
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]

def stop(reason):
    raise SystemExit("BLOCK_POINT2_PROTECTED_SOURCE_PATCH:" + reason)

def once(text, old, new, label):
    if text.count(old) != 1:
        stop("MISSING_OR_NONUNIQUE_" + label + ":" + str(text.count(old)))
    return text.replace(old, new, 1)

def in_method(src, start, end, transform, label):
    first, last = src.find(start), src.find(end, src.find(start) + len(start))
    if first < 0 or last < first or src.count(start) != 1:
        stop("METHOD_ANCHOR_" + label)
    original = src[first:last]
    replacement = transform(original)
    if replacement == original:
        stop("NO_CHANGE_" + label)
    return src[:first] + replacement + src[last:]

def social_patch(src):
    # Unique verified profile source in FULL 100447: it already retains the
    # real Firebase ownerUid but returns a stable publicId as friendship key.
    # Never change that stable relation key to an ephemeral Firebase UID.
    start = "    final existing = await DedaSectionOperationContext.wait(() => profileRef.get());"
    final = "    return DedaSocialSession("
    i = src.find(start)
    j = src.find(final, i)
    if i < 0 or j < i or src.count(start) != 1:
        stop("EXISTING_SOCIAL_PROFILE_WRAPPER_DIFFERENT")
    old = src[i:j]
    write = "    await DedaSectionOperationContext.wait(() => profileRef.set(<String, dynamic>{"
    suffix = "    }, SetOptions(merge: true)));"
    if old.count(write) != 1 or old.count(suffix) != 1:
        stop("SOCIAL_PROFILE_SET_UNEXPECTED")
    payload = old[old.index(write) + len(write): old.index(suffix)]
    if payload.count("'ownerUid': user.uid") != 1 or "'createdAt'" not in payload:
        stop("SOCIAL_OWNER_OR_CREATED_AT_UNEXPECTED")
    payload = payload.replace("'ownerUid': user.uid", "'ownerUid': ownerUid", 1)
    replacement = (
        "    final ownerUid = user.uid;\n"
        "    // Point2: historical social owner C must never be silently moved to B.\n"
        "    // The publicId friendship keys and full 100447 appearance stay intact.\n"
        "    await DedaSectionOperationContext.wait(() => _db.runTransaction((transaction) async {\n"
        "      final existing = await transaction.get(profileRef);\n"
        "      final previousOwner = (existing.data()?['ownerUid'] ?? '').toString();\n"
        "      if (existing.exists && previousOwner != ownerUid) {\n"
        "        throw StateError('social-historical-owner-preserved');\n"
        "      }\n"
        "      if (FirebaseAuth.instance.currentUser?.uid != ownerUid) {\n"
        "        throw StateError('social-session-changed');\n"
        "      }\n"
        "      transaction.set(profileRef, <String, dynamic>{"
        + payload + "    }, SetOptions(merge: true));\n"
        "    }));\n"
        "    if (FirebaseAuth.instance.currentUser?.uid != ownerUid) {\n"
        "      throw StateError('social-session-changed');\n"
        "    }\n\n"
    )
    src = src[:i] + replacement + src[j:]
    # Preserve ALL 100447 stable publicId friendship routing. Guard the real
    # Firebase principal instead of comparing currentUser.uid to sender.uid,
    # which is a *public ID* in the assembled version.
    if src.count("      uid: publicId,") != 1:
        stop("STABLE_FRIENDSHIP_PUBLIC_ID_MISSING")
    def guard_send(body):
        marker = "  }) async {\n"
        return once(body, marker, marker +
            "    if (FirebaseAuth.instance.currentUser?.uid != sender.profile.ownerUid) {\n"
            "      throw StateError('social-session-changed');\n"
            "    }\n", "FRIEND_SENDER_ENTRY")
    src = in_method(src,
        "  static Future<String> sendFriendRequest(",
        "  static Future<void> respondToRequest(",
        guard_send, "SEND_FRIEND")
    for name, ending in [
        ("respondToRequest", "removeRelation"),
        ("removeRelation", "profileForFriend"),
    ]:
        def guard_write(body):
            # The 100447 member methods may use the immutable public ID
            # instead of a local 'user' variable. Capture the real Auth UID
            # before the first await, then recheck at the write boundary.
            if body.count("async {\n") != 1:
                stop("FRIEND_METHOD_ASYNC_ANCHOR_" + name)
            body = body.replace("async {\n",
                "async {\n"
                "    final principalAtEntry = FirebaseAuth.instance.currentUser?.uid;\n"
                "    if (principalAtEntry == null) {\n"
                "      throw StateError('social-session-missing');\n"
                "    }\n",1)
            matches = list(re.finditer(r"(?m)^    await (?:DedaSectionOperationContext\.wait\(\(\) => )?ref\.(?:update|delete)\(",body))
            if len(matches) != 1:
                stop("FRIEND_MUTATION_UNEXPECTED_" + name)
            i = matches[0].start()
            return body[:i] + (
                "    if (FirebaseAuth.instance.currentUser?.uid != principalAtEntry) {\n"
                "      throw StateError('social-session-changed');\n"
                "    }\n"
            ) + body[i:]
        src = in_method(
            src, "  static Future<void> " + name + "(",
            "  static Future<" + ("void" if name == "respondToRequest" else "DedaSocialProfile?") +
            "> " + ending + "(",
            guard_write, name.upper())
    return src

def league_patch(src):
    # The legacy anonymous path is unchanged. The optional provider-linked
    # route needs independent server proof for the SAME historical UID;
    # never let mere feature flags make a fresh UID an eligible score owner.
    token = "import 'deda_weekly_league_clock.dart';"
    src = once(src, token,
        token + "\nimport 'deda_100431_linked_owner_session_policy.dart';",
        "LEAGUE_COMPAT_IMPORT")
    pattern1 = (r"(?m)(^\s*if \(!accountPattern\.hasMatch\(accountKey\) \|\| user == null \|\|\s*)"
                r"!user\.isAnonymous\) return null;")
    replacement1 = (
        r"\1(!user.isAnonymous && (!dedaLinkedOwnerCompatEnabled || "
        r"!await DedaLinkedOwnerSessionPolicy.verified(user, accountKey)))) return null;"
    )
    if len(re.findall(pattern1,src)) != 1:
        stop("LEAGUE_READ_ENTRY_UNEXPECTED")
    src = re.sub(pattern1,replacement1,src,count=1)
    pattern2 = r"if \(user == null \|\| !user\.isAnonymous \|\|"
    replacement2 = ("if (user == null ||\n"
                    "        (!user.isAnonymous && (!dedaLinkedOwnerCompatEnabled ||\n"
                    "          !await DedaLinkedOwnerSessionPolicy.verified(user, accountKey))) ||")
    if len(re.findall(pattern2,src)) != 1:
        stop("LEAGUE_REWARD_ENTRY_UNEXPECTED")
    src = re.sub(pattern2,replacement2,src,count=1)
    if "deda_sessions" not in src or "weeklyXp" not in src:
        stop("LEAGUE_CANONICAL_SOURCE_UNEXPECTED")
    return src

def apply(project):
    project=Path(project).resolve()
    if project == REPO or project in REPO.parents or REPO in project.parents:
        stop("NOT_DISPOSABLE_ASSEMBLY")
    evidence=project/"internal-build-inputs.json"
    if not evidence.is_file():
        stop("MISSING_BUILD_EVIDENCE")
    meta=json.loads(evidence.read_text())
    if meta.get("package") != "com.diraq.ludo.d_iraq_ludo" or (
        meta.get("completeOwnerDelivery") is not False or
        meta.get("financialRestoreEnabled") is not False
    ):
        stop("ORIGINAL_APP_OR_FINANCIAL_SAFETY_HOLD")
    transforms={
        "lib/deda_social_service.dart":social_patch,
        "lib/deda_weekly_firestore_direct_bridge.dart":league_patch,
    }
    pending={}
    proof={}
    for relative,transform in transforms.items():
        path=project/relative
        if not path.is_file():
            stop("REQUIRED_ASSEMBLED_SOURCE_MISSING_" + relative)
        before=path.read_text()
        after=transform(before)
        if before == after:
            stop("NO_CHANGE_" + relative)
        pending[path]=after
        proof[relative]={
            "sha256Before":hashlib.sha256(before.encode()).hexdigest(),
            "sha256After":hashlib.sha256(after.encode()).hexdigest(),
            "sourceGuardRepaired":True,
        }
    # Atomic preparation: all source anchors verified before any patch is written.
    for path,src in pending.items():
        path.write_text(src)
    (project/"deda-point2-section-binding-proof.json").write_text(
        json.dumps({
            "source":"100447-assembled-only",
            "point1Reference":"ea6f215039eee2ad123d76977c5d95ab433c07f2",
            "applied":proof,
            "uidChanged":False,
            "historicalFriendshipKeyChanged":False,
            "financialRestorationPerformed":False,
            "productionFirebaseChanged":False,
            "apkBuilt":False,
        },indent=2)+"\n"
    )
    print("PASS_POINT2_ASSEMBLED_SOCIAL_PUBLIC_ID_AND_LEAGUE_SAME_UID_GUARDS")

if __name__ == "__main__":
    parser=argparse.ArgumentParser()
    parser.add_argument("project")
    apply(parser.parse_args().project)
