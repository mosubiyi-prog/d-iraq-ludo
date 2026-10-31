"""DEDA 100406. Apply only four owner-reported league appearance corrections.

Must run AFTER 100405 assembled in an ephemeral verified workspace.
No 100404 rollback edits, no Firestore mutations, no XP/gift/wallet writes.
"""
import argparse,hashlib,json,shutil
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
PAGE='lib/deda_weekly_leaderboard_page.dart'
MAIN='lib/main.dart'
DIRECT='lib/deda_weekly_firestore_direct_bridge.dart'
SAFE='lib/deda_weekly_leaderboard_safe_screen.dart'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def bind(project):
    project=Path(project).resolve()
    if project==ROOT or project in ROOT.parents or ROOT in project.parents:
        raise ValueError('NEVER modify 100405 source or owner accepted source')
    meta=project/'internal-build-inputs.json'
    m=json.loads(meta.read_text())
    if (m.get('versionCode')!=100405 or
        m.get('package')!='com.diraq.ludo.d_iraq_ludo' or
        m.get('weekly100405AdminProgress',{}).get('sevenPointOwnerBundle') is not True or
        m.get('financialRestoreEnabled') is not False):
        raise ValueError('100405 assembled SHA-checked source required')
    for rel,h in m['sourceHashes'].items():
        f=project/rel
        if not f.is_file() or sha(f)!=h:raise ValueError('INPUT_DRIFT '+rel)
    # 100405 renderer already supports genuine externally validated equipment,
    # but SafeScreen never forwarded the owner's real DedaFramedAvatar painter.
    # Preserve the 100405 assembled screen, including the original
    # localTrialAccountKey constructor parameter. Replacing it with an older
    # repository template breaks the signed Android release compilation.
    source=(project/SAFE).read_text()
    assert source.count('drawOriginalEquippedAvatar') == 0
    constructor='  const DedaWeeklyLeaderboardSafeScreen({'
    if source.count(constructor)!=1 or source.count('drawOriginalEquippedAvatar')!=0:
        raise ValueError('unexpected generated 100405 safe screen')
    begin=source.index(constructor)
    closing=source.index('  });',begin)
    source=(source[:closing] + '    this.drawOriginalEquippedAvatar,\n'
            + source[closing:])
    field='  final Duration? refreshInterval;'
    if source.count(field)!=1:
        raise ValueError('original safe reader field missing')
    source=source.replace(field,
        field + '\n  final Widget Function(BuildContext, int, int, double)? '
        'drawOriginalEquippedAvatar;',1)
    forwarded='onOpenDailyTasks: widget.onOpenDailyTasks,'
    if source.count(forwarded)!=1:
        raise ValueError('original safe screen task CTA missing')
    source=source.replace(forwarded,
        forwarded + '\n      drawOriginalEquippedAvatar: '
        'widget.drawOriginalEquippedAvatar,',1)
    assert 'this.localTrialAccountKey' in source
    assert 'drawOriginalEquippedAvatar: widget.drawOriginalEquippedAvatar' in source
    (project/SAFE).write_text(source)

    before=(project/MAIN).read_text()
    old='          refreshInterval: const Duration(seconds: 30),\n'
    assert before.count(old)==2 and before.count('DedaWeeklyLeaderboardSafeScreen(')==2
    assert 'class DedaFramedAvatar' in before
    insertion=('          drawOriginalEquippedAvatar: (ctx, avatarStyle, frameStyle, size) =>\n'
               '              DedaFramedAvatar(avatarStyle: avatarStyle,\n'
               '                frameStyle: frameStyle, size: size),\n')
    updated=before.replace(old,old+insertion)
    assert updated.count('drawOriginalEquippedAvatar: (ctx, avatarStyle')==2
    (project/MAIN).write_text(updated)

    direct=(ROOT/'lib/deda_weekly_firestore_direct_bridge_100406.dart').read_text()
    assert direct.count("'publicAppearance': publicAppearance")==1
    assert direct.count("DedaQa32SparkPublicIdentifierDirectory.styleFromProjection(")==1
    assert (project/DIRECT).read_text().count("'activePublicId': pid")==1
    (project/DIRECT).write_text(direct)

    page=(project/PAGE).read_text()
    old_clock=("                      fitted(clock.daysAndHours,\n"
               "                          size: 15 * scale, color: gold),\n"
               "                      fitted(clock.minutesAndSeconds,\n"
               "                          size: 11 * scale, color: silver),")
    new_clock=("                      fitted(clock.daysAndHours,\n"
               "                          size: 16 * scale, color: gold),")
    if page.count(old_clock)!=1 or 'deda-weekly-inline-countdown' not in page:
        raise ValueError('verified 100405 countdown not found')
    page=page.replace(old_clock,new_clock)
    assert 'fitted(clock.minutesAndSeconds' not in page
    (project/PAGE).write_text(page)
    for name in (PAGE,MAIN,DIRECT,SAFE):
        m['sourceHashes'][name]=sha(project/name)
    m['versionCode']=100406
    m['weekly100406DisplayFixes']={
        'ownerReportedFourIssues':True,
        'minuteSecondLineRemoved':True,
        'countDaysHoursInSameCard':True,
        'activePremiumFromVerifiedPublicProjection':True,
        'immutableOriginalScoreKey':True,
        'publicAvatarAndFrameReadFromOwnerPublishedSocialProfile':True,
        'originalDedaFramedAvatarPassedThroughBothOfficialRoutes':True,
        'financialRestoreEnabled':False,
        'walletOrLevelXpChanged':False,
        'firebaseUserAccountModified':False,
        'ownerPhoneAndTabletQaPending':True,
        'productionPrizeSettlementActivated':False,
    }
    meta.write_text(json.dumps(m,ensure_ascii=False,indent=2)+'\n')
    return m['weekly100406DisplayFixes']
if __name__=='__main__':
    p=argparse.ArgumentParser()
    p.add_argument('workspace',type=Path)
    print(json.dumps(bind(p.parse_args().workspace),ensure_ascii=False))
