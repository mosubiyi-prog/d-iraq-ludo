"""DEDA 100390: same READ-ONLY diamond/gold presentation across profile/tasks/shop.

Apply AFTER 100389's original signed isolated build preparation and binders.
Repair style page's *frozen numeric snapshot* to read the SAME existing
DedaUnifiedCurrencyTotals as task banner and profile, reacting to the same
DedaDiamondsWallet and DedaSocialProgressWallet notifiers.
NO wallet writes, grants, migration, manager budget or purchase modifications.
"""
import argparse
import hashlib
import json
from pathlib import Path

ROOT=Path(__file__).resolve().parents[3]
APP="com.diraq.ludo.d_iraq_ludo"
VERSION=100390


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def one(source,old,new,name):
    if source.count(old)!=1:
        raise ValueError("stage15 frozen wallet projection anchor mismatch: "+name)
    return source.replace(old,new,1)


def bind(project):
    project=Path(project).resolve()
    if project==ROOT or project in ROOT.parents or ROOT in project.parents:
        raise ValueError("never patch GitHub original checkout")
    meta=project/"internal-build-inputs.json"
    p=project/"lib/main.dart"
    if not p.is_file() or not meta.is_file():
        raise ValueError("signed original app workspace required")
    cfg=json.loads(meta.read_text())
    previous=cfg.get("sourceHashes",{})
    if cfg.get("versionCode")!=100389 or cfg.get("package")!=APP or \
       cfg.get("variant")!="candidate" or \
       cfg.get("completeOwnerDelivery") is not False or \
       cfg.get("productionExecutionPerformed") is not False or \
       cfg.get("financialRestoreEnabled") is not False or \
       not cfg.get("activeIdStage14",{}).get("preloadedBeforeFirstFrame") or \
       not cfg.get("weeklyStage13",{}).get("sameOfficialPackage") or \
       any(not (project/name).is_file() or sha(project/name)!=hashval
           for name,hashval in previous.items()):
        raise ValueError("100389 original private candidate drifted")

    text=p.read_text()
    start=text.index("class _DedaStylePageState extends State<DedaStylePage>")
    end=text.index("\nclass ",start+10)
    piece=text[start:end]
    original=piece
    piece=one(piece,
        "class _DedaStylePageState extends State<DedaStylePage> {",
        "class _DedaStylePageState extends State<DedaStylePage>\n"
        "    with WidgetsBindingObserver {",
        "watch app resume")
    piece=one(piece,"  int _diamonds = 0;",
        """  // Same live, account-scoped presentation as My Profile and daily tasks.
  // This is NOT the spendable wallet or an entitlement to buy.
  int get _personalDiamonds => DedaUnifiedCurrencyTotals(
    ordinaryEarnedAndGiftedDiamonds: DedaDiamondsWallet.effectiveBalance,
    hasVerifiedManagerPersonalWallet:
        DedaDiamondsWallet.hasGeneralManagerPersonalWallet,
    managerPersonalDiamonds: DedaDiamondsWallet.generalManagerPersonalBalance,
    taskCoins: DedaSocialProgressWallet.coinsNotifier.value,
  ).diamonds;
  int get _personalGold => DedaSocialProgressWallet.coinsNotifier.value;

  void _onAccountWalletUpdated() {
    // Renders the already-updated wallet values. Does not read or write
    // account balances and does not touch purchase/ownership code.
    if (mounted) setState(() {});
  }""","stop freezing balance into style page local snapshot")
    piece=one(piece,
        "    super.initState();\n    _load();",
        """    super.initState();
    WidgetsBinding.instance.addObserver(this);
    DedaDiamondsWallet.balanceNotifier.addListener(_onAccountWalletUpdated);
    DedaDiamondsWallet.generalManagerPersonalNotifier
        .addListener(_onAccountWalletUpdated);
    DedaSocialProgressWallet.coinsNotifier
        .addListener(_onAccountWalletUpdated);
    _load();""","listen to exact existing wallet projection")
    piece=one(piece,
        "  Future<void> _load() async {",
        """  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      // Existing verified original wallet reads on resume, not client sums.
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    // Do not hold stale user-page references after account switch.
    ++_dedaPoint09StyleReadEpoch;
    DedaDiamondsWallet.balanceNotifier.removeListener(_onAccountWalletUpdated);
    DedaDiamondsWallet.generalManagerPersonalNotifier
        .removeListener(_onAccountWalletUpdated);
    DedaSocialProgressWallet.coinsNotifier
        .removeListener(_onAccountWalletUpdated);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _load() async {""","resume re-read and dispose")
    old="""      // DEDA_100374_TOTAL_PERSONAL_DIAMONDS_AND_GOLD_DISPLAY_ONLY
      // SHOW the same complete personal diamond display balance as My Profile.
      // Do not conflate the administrative diamond gift pool or assume this
      // displayed sum is eligible for a debit (wallet spend remains unchanged).
      _diamonds = DedaUnifiedCurrencyTotals(
        ordinaryEarnedAndGiftedDiamonds: DedaDiamondsWallet.effectiveBalance,
        hasVerifiedManagerPersonalWallet:
            DedaDiamondsWallet.hasGeneralManagerPersonalWallet,
        managerPersonalDiamonds:
            DedaDiamondsWallet.generalManagerPersonalBalance,
        taskCoins: (values[0] as DedaSocialProgressSnapshot).coins,
      ).diamonds;"""
    piece=one(piece,old,
      "      // Currency is read live from existing wallet notifiers above;\n"
      "      // no frozen value or separate balance exists on this page.",
      "never capture diamonds at end of asynchronous load")
    piece=one(piece,"_miniBalanceChip('💎', _diamonds)",
        "_miniBalanceChip('💎', _personalDiamonds)",
        "live mini diamond header")
    piece=one(piece,"value: _diamonds,",
        "value: _personalDiamonds,",
        "live main diamond header")
    # Exactly these two visible gold surfaces used the stale load snapshot.
    if piece.count("progress.coins")!=2:
        raise ValueError("style gold frozen snapshot changed")
    piece=piece.replace("progress.coins","_personalGold")
    if "_diamonds" in piece or "progress.coins" in piece:
        raise ValueError("old frozen style-wallet fields still displayed")
    if original==piece:
        raise ValueError("wallet display not changed")
    text=text[:start]+piece+text[end:]
    p.write_text(text)
    changed={name for name,value in previous.items() if sha(project/name)!=value}
    if changed!={"lib/main.dart"}:
        raise ValueError("attempted non-UI original file mutation: "+repr(changed))
    cfg["sourceHashes"]={
      str(f.relative_to(project)):sha(f) for f in sorted((project/"lib").rglob("*.dart"))
    }
    cfg["sourceHashes"].update({
      "pubspec.yaml":sha(project/"pubspec.yaml"),
      "pubspec.lock":sha(project/"pubspec.lock"),
    })
    cfg["versionCode"]=VERSION
    cfg["currencyStage15"]={
      "profileAndTasksRemainExistingUnifiedSources":True,
      "styleDiamondNowLive":True,
      "styleGoldNowLive":True,
      "shopResumeRefreshes":True,
      "shopAccountSwitchGuardPreserved":True,
      "walletSpendingChanged":False,
      "walletCreditChanged":False,
      "adminPersonalBalanceChanged":False,
      "adminGiftPoolChanged":False,
      "levelOrTaskPointsChanged":False,
      "ownerVisible60DiamondDiscrepancyNeedsDeviceRecheck":True,
      "privateQaOnly":True,
    }
    cfg["purpose"]="PRIVATE ORIGINAL 100390 UNIFIED CURRENCY READ-ONLY QA NO PLAY"
    meta.write_text(json.dumps(cfg,indent=2,ensure_ascii=False)+"\n")
    return cfg["currencyStage15"]


if __name__=="__main__":
    arg=argparse.ArgumentParser(description=__doc__)
    arg.add_argument("project",type=Path)
    args=arg.parse_args()
    print(json.dumps(bind(args.project),ensure_ascii=False))
