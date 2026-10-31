"""100408 ordered owner corrections. Apply to verified assembled 100407 QA only.

Point 1: instant same-UID previously verified display ID, reconciled by Stage71.
Points 2-7: applied separately below once each prior point has passed.
No changes to a signed rollback reference, XP, wallet, or Google Play.
"""
import argparse, hashlib, json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
SCOPE="lib/deda_qa32_active_account_scope.dart"
def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def one(s,old,new,label):
    if s.count(old)!=1:
        raise ValueError("100408 safety anchor mismatch: "+label+" count "+str(s.count(old)))
    return s.replace(old,new,1)
def bind(project):
    project=Path(project).resolve()
    if project==ROOT or project in ROOT.parents or ROOT in project.parents:
        raise ValueError("owner-approved source is read only")
    meta_file=project/"internal-build-inputs.json"
    meta=json.loads(meta_file.read_text())
    if meta.get("versionCode")!=100407 or meta.get("package")!="com.diraq.ludo.d_iraq_ludo" or meta.get("financialRestoreEnabled") is not False or meta.get("weekly100407OwnerCorrections",{}).get("profileAlreadyUsesVerifiedOwnerStore") is not True:
        raise ValueError("100407 verified output required before 100408")
    for path,digest in meta["sourceHashes"].items():
        if not (project/path).is_file() or sha(project/path)!=digest:
            raise ValueError("verified baseline changed "+path)
    scope=(project/SCOPE).read_text()
    if "import 'deda_verified_active_id_store.dart';" not in scope or "DedaVerifiedActiveIdStore.confirmed(" not in scope:
        raise ValueError("verified owner-only Stage71 cache is missing")
    scope=one(scope,
        """    return widget.builder(context, proof);
  }
}""",
        """    // Same-UID server-confirmed UI display is restored before the slow
    // independent account/ownership refresh completes. NEVER use this to
    // authorize transactions, gifts, friendships, grants, or change a UID.
    return ValueListenableBuilder<int>(
      valueListenable: DedaVerifiedActiveIdStore.revision,
      builder: (context, _, __) {
        final owner = _currentUid();
        final valid = owner != null &&
            _proof?.verifiedFor(owner, widget.originalId) == true;
        final cached = owner != null &&
                widget._source is _FirebaseIdentitySource
            ? DedaVerifiedActiveIdStore.read(owner, widget.originalId)
            : null;
        final shown = valid ? _proof
            : cached == null ? null : DedaQa32ActiveAccountIdentity(
                uid: owner!, originalId: widget.originalId,
                displayId: cached.displayId, fixedColor: cached.fixedColor,
              );
        return widget.builder(context, shown);
      },
    );
  }
}""",
        "point1 same UID cached profile paint")
    (project/SCOPE).write_text(scope)

    # Point 2: the existing bottom status card shows only this week's
    # server-confirmed official pause notice and clears on resume.
    import shutil
    pause_source="lib/deda_weekly_maintenance_status_100408.dart"
    pause_target="lib/deda_weekly_maintenance_status.dart"
    shutil.copy2(ROOT/pause_source,project/pause_target)
    page_file=project/"lib/deda_weekly_leaderboard_page.dart"
    page=page_file.read_text()
    page=one(page,
        "import 'deda_weekly_league_clock.dart';",
        "import 'deda_weekly_league_clock.dart';\n"
        "import 'deda_weekly_maintenance_status.dart';",
        "point2 import")
    page=one(page,
        "child: fitted(view.reviewNotice != null",
        "child: DedaWeeklyMaintenanceStatus(normal: fitted(view.reviewNotice != null",
        "point2 official pause notice in existing card")
    page=one(page,
        """            size: 11 * scale, color: silver),
      );""",
        """            size: 11 * scale, color: silver),
        ),
      );""",
        "point2 close bottom status banner")

    # Point 4: independent Firebase identity document reads in parallel,
    # bounded public appearance queries. No fake ranks or guessed premium IDs.
    bridge_file=project/"lib/deda_weekly_firestore_direct_bridge.dart"
    bridge=bridge_file.read_text()
    bridge=one(bridge,
        """    final sess = await db.collection('deda_sessions').doc(uid).get();
    if (sess.data()?['accountKey'] != accountKey) return null;
    final doc = await db.collection('users').doc(uid).get();""",
        """    final ownerDocs = await Future.wait([
      db.collection('deda_sessions').doc(uid).get(),
      db.collection('users').doc(uid).get(),
    ]);
    final sess = ownerDocs[0];
    if (sess.data()?['accountKey'] != accountKey) return null;
    final doc = ownerDocs[1];""",
        "point4 parallel same-principal identity reads")
    old_query="""              .get(const GetOptions(source: Source.server))
              .then((doc) => doc.data()).catchError((_) => null),"""
    if bridge.count(old_query)!=2:
        raise ValueError("point4 two independent profile queries required")
    bridge=bridge.replace(old_query,
        """              .get(const GetOptions(source: Source.server))
              .timeout(const Duration(seconds: 5))
              .then((doc) => doc.data()).catchError((_) => null),""")
    bridge=one(bridge,
        """          .doc(w.id).collection('users').doc(me.id).get();""",
        """          .doc(w.id).collection('users').doc(me.id).get()
          .timeout(const Duration(seconds: 3));""",
        "point4 no slow optional notice blocking ranks")
    bridge_file.write_text(bridge)
    meta["sourceHashes"]["lib/deda_weekly_firestore_direct_bridge.dart"] = sha(bridge_file)

    # Point 5: tiny translucent medallion below the portrait, never over face.
    begin=page.index("  Widget podium(")
    finish=page.index("  Widget rankingTable(",begin)
    podium=page[begin:finish]
    podium=one(podium,
        """                  Positioned(
                    bottom: 0,
                    child: Container(
                      padding: EdgeInsets.symmetric(
                          horizontal: 10 * scale, vertical: 2 * scale),""",
        """                  Positioned(
                    bottom: -5 * scale,
                    child: Opacity(
                      opacity: .70,
                      child: Container(
                        padding: EdgeInsets.symmetric(
                            horizontal: 7 * scale, vertical: 1 * scale),""",
        "point5 move medal below portrait")
    podium=one(podium,
        """                              fontSize: 20 * scale,
                              fontWeight: FontWeight.w900)),
                    ),
                  ),""",
        """                              fontSize: 14 * scale,
                              fontWeight: FontWeight.w900)),
                      ),
                    ),
                  ),""",
        "point5 translucent smaller number")
    page=page[:begin]+podium+page[finish:]
    page_file.write_text(page)

    # Point 6: display verified alias, but retain original ID as Firestore
    # score document / freeze / manager-review key.
    alias_source="lib/deda_admin_league_active_id_100408.dart"
    alias_target="lib/deda_admin_league_active_id.dart"
    shutil.copy2(ROOT/alias_source,project/alias_target)
    live_file=project/"lib/deda_admin_league_live_widgets.dart"
    live=live_file.read_text()
    live=one(live,
        "import 'deda_admin_league_live_data.dart';",
        "import 'deda_admin_league_live_data.dart';\n"
        "import 'deda_admin_league_active_id.dart';",
        "point6 live manager alias import")
    live=one(live,
        """Text(person.publicId,
                            textDirection: TextDirection.ltr,
                            style: const TextStyle(fontSize: 11)),""",
        """DedaAdminLeagueActiveId(originalId: person.publicId,
                            style: const TextStyle(fontSize: 11)),""",
        "point6 live Top10 verified alias")
    live=one(live,
        "subtitle: Text(player.publicId),",
        "subtitle: DedaAdminLeagueActiveId(originalId: player.publicId),",
        "point6 archive public alias")
    live_file.write_text(live)
    review_file=project/"lib/deda_admin_league_control_widgets.dart"
    review=review_file.read_text()
    review=one(review,
        "import 'deda_admin_league_controls.dart';",
        "import 'deda_admin_league_controls.dart';\n"
        "import 'deda_admin_league_active_id.dart';",
        "point6 frozen user display only")
    review=one(review,
        """Text('${row.publicId} — ${row.xp} XP',
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(fontSize: 11)),""",
        """Row(children: [
                  Flexible(child: DedaAdminLeagueActiveId(
                    originalId: row.publicId,
                    style: const TextStyle(fontSize: 11))),
                  Text(' — ${row.xp} XP',
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(fontSize: 11)),
                ]),""",
        "point6 freeze panel display not control key")
    review_file.write_text(review)
    for file in (pause_target, "lib/deda_weekly_leaderboard_page.dart",
                 alias_target, "lib/deda_admin_league_live_widgets.dart",
                 "lib/deda_admin_league_control_widgets.dart"):
        meta["sourceHashes"][file]=sha(project/file)


    # Point 7: manager-only prize-increase editor; plan read by competitors.
    # Payment worker stays entirely disabled; rules require real GM and pause.
    prize_source="lib/deda_weekly_prize_plan_100408.dart"
    prize_target="lib/deda_weekly_prize_plan.dart"
    shutil.copy2(ROOT/prize_source,project/prize_target)
    admin_page=project/"lib/deda_admin_league_page.dart"
    admin=admin_page.read_text()
    admin=one(admin,
        "import 'deda_admin_league_reward_status.dart';",
        "import 'deda_admin_league_reward_status.dart';\n"
        "import 'deda_weekly_prize_plan.dart';",
        "point7 import manager editor")
    # Dynamic exact amounts replace the four original static summary rows.
    # The original 370-masa base plan remains only for older static previews.
    left=admin.index("                       _prizeRow(t('الأول'")
    right=admin.index("                       const SizedBox(height: 7),",left)
    prior=admin[left:right]
    if prior.count("_prizeRow(")!=5:
        raise ValueError("unexpected fixed original prize summary")
    admin=(admin[:left] +
      "                       if (liveDataEnabled) const DedaAdminLeaguePrizeSummary()\n"
      "                       else ...[\n" + prior +
      "                       ],\n" + admin[right:])
    admin=one(admin,
        """                        DedaAdminLeagueRewardStatus(isArabic: isArabic),""",
        """                        const DedaAdminLeaguePrizeEditor(),
                        const SizedBox(height: 10),
                        DedaAdminLeagueRewardStatus(isArabic: isArabic),""",
        "point7 expose editor within GM-only prize plan card")
    admin_page.write_text(admin)
    page=page_file.read_text()
    page=one(page,
        "import 'deda_weekly_maintenance_status.dart';",
        "import 'deda_weekly_maintenance_status.dart';\n"
        "import 'deda_weekly_prize_plan.dart';",
        "point7 import public server prize plan")
    page=one(page,
        """                    pill('💎 ${prize(place)}',
                        accent, navy),""",
        """                    SizedBox(
                      height: 15 * scale,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        decoration: BoxDecoration(color: accent,
                          borderRadius: BorderRadius.circular(28)),
                        child: Center(child: DedaWeeklyPrizeAmount(
                          place: place, color: navy, fontSize: 10 * scale)),
                      ),
                    ),""",
        "point7 dynamic prize on top three")
    page=one(page,
        """child: fitted('💎 10 ماسات',
                              size: 11 * scale, color: silver)),""",
        """child: DedaWeeklyPrizeAmount(
                              place: rank, color: silver, fontSize: 11 * scale)),""",
        "point7 dynamic prizes ranks 4-10")
    page_file.write_text(page)
    for file in (prize_target, "lib/deda_admin_league_page.dart",
                 "lib/deda_weekly_leaderboard_page.dart"):
        meta["sourceHashes"][file]=sha(project/file)

    meta["sourceHashes"][SCOPE]=sha(project/SCOPE)
    meta["versionCode"]=100408
    meta["weekly100408OwnerSevenPoints"]={
      "point1VerifiedCacheBeforeServerRecheck": True,
      "point1OriginalAccountKeyImmutable": True,
      "point1OtherAccountCacheForbidden": True,
      "point1OwnerPhoneTestPending": True,
      "point2MaintenanceBanner": True,
      "point3WrongTransitionalBalances": False,
      "point4SlowLeagueFirstPaint": True,
      "point5PodiumNumberOpacity": True,
      "point6AdminAliasPresentation": True,
      "point7ManagerPausedPrizeEditor": True,
      "payoutActivated": False,
      "walletOrXPModified": False,
    }
    meta_file.write_text(json.dumps(meta,ensure_ascii=False,indent=2)+"\n")
    return meta["weekly100408OwnerSevenPoints"]
if __name__=="__main__":
    parser=argparse.ArgumentParser()
    parser.add_argument("workspace",type=Path)
    print(json.dumps(bind(parser.parse_args().workspace),ensure_ascii=False))
