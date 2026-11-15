"""DEDA STEP3 final isolated compatibility and administration-entry safeguard.

Run only on the assembled 100448 + STEP1 + STEP2 temporary workspace. All
shared ID labels/copies display the permanent original; premium remains an
owner-verified local cosmetic option on the owner's profile ONLY. No server
aliases or ownership records are removed/migrated. Admin entry continues to
be authorized exclusively by the EXISTING backend protected gateway.
"""
import argparse
import hashlib
import json
import shutil
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
POLICY = "lib/deda_original_functional_id_policy_20261115.dart"
UNI = "lib/deda_unified_active_id_100410.dart"
SIX = "lib/deda_six_active_identity.dart"
FRIEND = "lib/deda_stage50_verified_friend_ink_badge.dart"
SYNC = "lib/deda_active_id_public_sync_100409.dart"
MAIN = "lib/main.dart"
BACKEND = "lib/deda_backend.dart"
ADMIN = "lib/admin_pages.dart"
STAGE = "lib/deda_stage71_free_owned_use_profile.dart"
INK48 = "lib/deda_stage48_verified_active_profile_ink.dart"
SHARE49 = "lib/deda_stage49_verified_share_id_badge.dart"
DUAL_ADMIN = "lib/deda_stage71_dual_admin_page.dart"

POLICY_TYPE = "DedaOriginalFunctionalIdPolicy20261115.originalOnly"
POLICY_IMPORT = "import 'deda_original_functional_id_policy_20261115.dart';\n"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def once(source, before, after, title):
    count = source.count(before)
    if count != 1:
        raise ValueError("STEP3_EXPECTED_" + title + "_" + str(count))
    return source.replace(before, after, 1)


def patch_unified(text):
    text = once(text, "import 'deda_verified_active_id_store.dart';\n",
        "import 'deda_verified_active_id_store.dart';\n" + POLICY_IMPORT,
        "UNIFIED_IMPORT")
    text = once(text,
        "  static DedaVerifiedActiveId? proof(String original) {\n",
        """  static DedaVerifiedActiveId? proof(String original) {
    if (DedaOriginalFunctionalIdPolicy20261115.originalOnly) {
      if (!valid(original)) return null;
      return DedaVerifiedActiveId(
        uid:'public-server',originalId:original,
        displayId:original,fixedColor:null);
    }
""", "CANONICAL_PROOF")
    text = once(text,
        "  static String? display(String original) {\n",
        """  static String? display(String original) {
    if (DedaOriginalFunctionalIdPolicy20261115.originalOnly) {
      return valid(original) ? original : null;
    }
""", "ORIGINAL_PUBLIC_LABEL")
    text = once(text,
        "  static void Function() watch(String original) {\n",
        """  static void Function() watch(String original) {
    if (DedaOriginalFunctionalIdPolicy20261115.originalOnly) {
      return () {}; // No premium subscription for friend/league ID labels.
    }
""", "NO_PUBLIC_PREMIUM_WATCH")
    text = once(text,
        "  static Future<void> ensureOwner(String original) async {\n",
        """  static Future<void> ensureOwner(String original) async {
    if (DedaOriginalFunctionalIdPolicy20261115.originalOnly) {
      return; // Existing backend ownership proof still guards cosmetic use.
    }
""", "NO_PUBLIC_PREMIUM_READER")
    text = once(text,
        "  static void confirmedUse(String current,String original,String id,String? color) {\n",
        """  static void confirmedUse(String current,String original,String id,String? color) {
    if (DedaOriginalFunctionalIdPolicy20261115.originalOnly) return;
""", "NO_GLOBAL_PREMIUM_CONFIRM")
    return text


def patch_six(text):
    text = once(text, "import 'deda_qa32_active_account_scope.dart';\n",
                "import 'deda_qa32_active_account_scope.dart';\n"
                + POLICY_IMPORT, "SIX_IMPORT")
    text = once(text,
        "  Widget build(BuildContext context) => DedaQa32ActiveAccountScope(\n",
        """  Widget build(BuildContext context) =>
    DedaOriginalFunctionalIdPolicy20261115.originalOnly
      ? Directionality(
          textDirection: TextDirection.ltr,
          child: selectable
            ? SelectableText(originalId, style: style, textAlign: textAlign)
            : Text(originalId, style: style, textAlign: textAlign),
        )
      : DedaQa32ActiveAccountScope(
""", "ORIGINAL_TEXT_BEFORE_SCOPE")
    # The assembled received-sender view differs from the checked-in
    # standalone helper. Restrict the insertion to this one class and
    # preserve its complete original implementation after the early guard.
    begin=text.index("class DedaSixReceivedIdentity")
    end=text.index("class DedaSixIdentityCopy",begin)
    piece=text[begin:end]
    piece=once(piece, "  Widget build(BuildContext context) {\n",
        "  Widget build(BuildContext context) {\n"
        "    if (DedaOriginalFunctionalIdPolicy20261115.originalOnly) "
        "return fallback;\n", "ORIGINAL_LOCATION_SENDER")
    text=text[:begin]+piece+text[end:]
    text = once(text,
        "  static Future<String?> resolve(String original) async {\n",
        """  static Future<String?> resolve(String original) async {
    if (DedaOriginalFunctionalIdPolicy20261115.originalOnly) return original;
""", "ORIGINAL_COPY_SHARE")
    return text


def patch_friend(text):
    text = once(text,
        "import 'deda_unified_active_id_100410.dart';\n",
        "import 'deda_unified_active_id_100410.dart';\n"+POLICY_IMPORT,
        "FRIEND_IMPORT")
    # This exact class is made Stateless by the verified 100410 binder.
    old = ("  Widget build(BuildContext context) {\n"
           "    if (!DedaStage50PublicIdStyleBridge.enabled ||\n"
           "        Firebase.apps.isEmpty) return fallback;")
    new = ("  Widget build(BuildContext context) {\n"
           "    if (DedaOriginalFunctionalIdPolicy20261115.originalOnly) "
           "return fallback;\n"
           "    if (!DedaStage50PublicIdStyleBridge.enabled ||\n"
           "        Firebase.apps.isEmpty) return fallback;")
    text = once(text,old,new,"FRIEND_CARD_ORIGINAL")
    # Two independent public premium renderers also must never draw it.
    premium_marker = "class DedaStage50PremiumPublicCard extends StatelessWidget {"
    next_marker = "class DedaStage50FriendIdInkText extends StatelessWidget {"
    start = text.index(premium_marker)
    finish = text.index(next_marker, start)
    segment = text[start:finish]
    segment = once(segment,
        "  Widget build(BuildContext context) {\n",
        """  Widget build(BuildContext context) {
    if (DedaOriginalFunctionalIdPolicy20261115.originalOnly) return fallback;
""", "PREMIUM_PUBLIC_CARD_FALLBACK")
    text = text[:start] + segment + text[finish:]
    marker = "class DedaStage50FriendIdInkText extends StatelessWidget {"
    p = text.index(marker)
    first, remainder = text[:p],text[p:]
    remainder = once(remainder,
        "  Widget build(BuildContext context) {\n",
        """  Widget build(BuildContext context) {
    if (DedaOriginalFunctionalIdPolicy20261115.originalOnly) return fallback;
""", "PREMIUM_FRIEND_INK_FALLBACK")
    return first+remainder


def patch_public_sync(text):
    text = once(text,
        "import 'deda_qa32_spark_public_identifier_directory.dart';\n",
        "import 'deda_qa32_spark_public_identifier_directory.dart';\n"
        + POLICY_IMPORT,"SYNC_IMPORT")
    text = once(text,
        """    required String? fixedColor,
  }) async {
    if (!DedaQa32SparkPublicIdentifierDirectory.enabled ||""",
        """    required String? fixedColor,
  }) async {
    if (DedaOriginalFunctionalIdPolicy20261115.originalOnly) return;
    if (!DedaQa32SparkPublicIdentifierDirectory.enabled ||""",
        "NO_PUBLIC_PREMIUM_WRITE")
    return text


def patch_stage48(text):
    text = once(text,
        "import 'deda_verified_identifier_ink.dart';\n",
        "import 'deda_verified_identifier_ink.dart';\n"+POLICY_IMPORT,
        "STAGE48_POLICY_IMPORT")
    marker="class _DedaStage48ActiveInkProfileSlotState"
    if text.count(marker)!=1: raise ValueError("STEP3_STAGE48_PROFILE_SLOT_MISSING")
    start=text.index(marker)
    before,body=text[:start],text[start:]
    body=once(body,
        "    if (!DedaStage48ActiveInkBridge.enabled) return;\n",
        "    if (DedaOriginalFunctionalIdPolicy20261115.originalOnly || "
        "!DedaStage48ActiveInkBridge.enabled) return;\n",
        "STAGE48_NO_PREMIUM_AUTH_SUBSCRIPTION")
    body=once(body,
        "  Future<void> _read() async {\n",
        "  Future<void> _read() async {\n"
        "    if (DedaOriginalFunctionalIdPolicy20261115.originalOnly) return;\n",
        "STAGE48_NO_PREMIUM_REMOTE_READ")
    body=once(body,
        "  Widget build(BuildContext context) {\n",
        "  Widget build(BuildContext context) {\n"
        "    if (DedaOriginalFunctionalIdPolicy20261115.originalOnly) "
        "return widget.fallback;\n",
        "STAGE48_ORIGINAL_DISPLAY")
    return before+body


def patch_stage49(text):
    text=once(text,
        "import 'deda_verified_identifier_ink.dart';\n",
        "import 'deda_verified_identifier_ink.dart';\n"+POLICY_IMPORT,
        "STAGE49_POLICY_IMPORT")
    first="class _DedaStage49VerifiedShareIdBadgeState"
    second="class DedaStage49VerifiedShareIdPreview"
    if text.count(first)!=1 or text.count(second)!=1:
        raise ValueError("STEP3_STAGE49_CARD_OR_PREVIEW_CHANGED")
    begin=text.index(first)
    end=text.index(second,begin)
    pre,body,tail=text[:begin],text[begin:end],text[end:]
    body=once(body,
        "    if (!DedaStage48ActiveInkBridge.enabled) return;\n",
        "    if (DedaOriginalFunctionalIdPolicy20261115.originalOnly || "
        "!DedaStage48ActiveInkBridge.enabled) return;\n",
        "STAGE49_NO_PREMIUM_SUBSCRIPTION")
    body=once(body,
        "  Future<void> _fetch() async {\n",
        "  Future<void> _fetch() async {\n"
        "    if (DedaOriginalFunctionalIdPolicy20261115.originalOnly) return;\n",
        "STAGE49_NO_PREMIUM_REMOTE_READ")
    body=once(body,
        "  Widget build(BuildContext context) {\n",
        "  Widget build(BuildContext context) {\n"
        "    if (DedaOriginalFunctionalIdPolicy20261115.originalOnly) "
        "return const SizedBox.shrink();\n",
        "STAGE49_QR_PREMIUM_BADGE_HIDDEN")
    tail=once(tail,
        "  Widget build(BuildContext context) {\n",
        "  Widget build(BuildContext context) {\n"
        "    if (DedaOriginalFunctionalIdPolicy20261115.originalOnly) "
        "return const SizedBox.shrink();\n",
        "STAGE49_PREVIEW_PREMIUM_HIDDEN")
    return pre+body+tail


ORIGINAL_ADMIN_STATE = """class _DedaSettingsPageState extends State<DedaSettingsPage> {
  bool _adminEntryVisible = false;

  @override
  void initState() {
    super.initState();
    unawaited(_refreshAdminEntryVisibility());
  }

  Future<void> _refreshAdminEntryVisibility() async {
    final phone = DedaPreferences.accountPhone.trim().isNotEmpty
        ? DedaPreferences.accountPhone
        : DedaPreferences.phone;

    var allowed = false;
    try {
      allowed = await DedaBackend.currentDedaAccountCanSeeAdminEntry(
        phone: phone,
      );
    } catch (_) {
      allowed = false;
    }

    if (!mounted) return;
    setState(() => _adminEntryVisible = allowed);
  }
"""

NEW_ADMIN_STATE = """class _DedaSettingsPageState extends State<DedaSettingsPage>
    with WidgetsBindingObserver {
  bool _adminEntryVisible = false;
  StreamSubscription<User?>? _adminEntryAuth;
  int _adminEntryEpoch = 0;

  String _adminPhone() => DedaPreferences.accountPhone.trim().isNotEmpty
      ? DedaPreferences.accountPhone : DedaPreferences.phone;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (Firebase.apps.isNotEmpty) {
      _adminEntryAuth = FirebaseAuth.instance.authStateChanges().listen((_) {
        if (!mounted) return;
        if (_adminEntryVisible) setState(() => _adminEntryVisible = false);
        unawaited(_refreshAdminEntryVisibility());
      });
    }
    unawaited(_refreshAdminEntryVisibility());
  }

  // A temporarily unavailable read must not permanently hide the card.
  // Re-check on foregrounding, and after Firebase restores the auth session.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      unawaited(_refreshAdminEntryVisibility());
    }
  }

  @override
  void dispose() {
    ++_adminEntryEpoch;
    _adminEntryAuth?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _refreshAdminEntryVisibility() async {
    final generation = ++_adminEntryEpoch;
    final phone = _adminPhone();
    var allowed = false;
    try {
      // The existing protected, phone-bound gateway remains authoritative.
      allowed = await DedaBackend.currentDedaAccountCanSeeAdminEntry(
        phone: phone,
      );
    } catch (_) {
      allowed = false;
    }
    if (!mounted || generation != _adminEntryEpoch) return;
    if (_adminPhone() != phone) {
      if (_adminEntryVisible) setState(() => _adminEntryVisible = false);
      unawaited(_refreshAdminEntryVisibility());
      return;
    }
    if (_adminEntryVisible != allowed) {
      setState(() => _adminEntryVisible = allowed);
    }
  }
"""


def patch_admin200_self_use(text):
    # Source format varies between the checked-in manager page and the fully
    # reconstructed 100448 assembly. Match the actual isolated self-use call,
    # NOT its neighboring comments, which legitimately changed between builds.
    # Fail closed unless the manager grant and the one self-use call coexist
    # in the same _assign method, in that order.
    old_import = "import 'deda_stage71_free_owned_use_profile.dart';\n"
    new_import = (old_import +
                  "import 'deda_cosmetic_premium_profile_20261115.dart';\n")
    text = once(text, old_import, new_import, "DUAL_ADMIN_LOCAL_IMPORT")
    method_start = text.find("Future<void> _assign(")
    method_end = text.find("void _history()", method_start)
    if method_start < 0 or method_end < method_start:
        raise ValueError("STEP3_ADMIN200_ASSIGN_BOUNDARY_UNVERIFIED")
    before, method, after = (
        text[:method_start], text[method_start:method_end], text[method_end:]
    )
    grant = "DedaStage71Admin200.assign("
    if method.count(grant) != 1:
        raise ValueError("STEP3_ADMIN200_GRANT_MISSING_OR_DUPLICATED")
    # Two exact historical variants are supported:
    # 1) the direct Stage71.use(target, row.identifier) manager action;
    # 2) the assembled stability-guarded DedaSectionOperationContext.wait
    #    action with selectedTarget (observed in GitHub Actions source QA).
    # Both must be preceded by the verified ownership grant; no other Use
    # shape is permitted here.
    direct = re.compile(
        r"await\s+DedaStage71OwnedIdentifierService\.use\(\s*"
        r"target\s*,\s*row\.identifier\s*,?\s*\);"
    )
    guarded = re.compile(
        r"await\s+DedaSectionOperationContext\.wait\(\s*"
        r"\(\s*\)\s*=>\s*DedaStage71OwnedIdentifierService\.use\(\s*"
        r"selectedTarget\s*,\s*row\.identifier\s*,?\s*\)\s*\);"
    )
    matches_direct = list(direct.finditer(method))
    matches_guarded = list(guarded.finditer(method))
    if (len(matches_direct) + len(matches_guarded) != 1 or
            method.count("DedaStage71OwnedIdentifierService.use(") != 1):
        at = method.find("DedaStage71OwnedIdentifierService.use(")
        print("STEP3_ADMIN200_USE_SHAPE_MISMATCH",
              repr(method[max(0, at-130):at+420]) if at >= 0
              else "NO_USE_PRESENT")
        raise ValueError("STEP3_ADMIN200_SELF_USE_MARKER_CHANGED")
    is_guarded = len(matches_guarded) == 1
    match = matches_guarded[0] if is_guarded else matches_direct[0]
    if match.start() <= method.index(grant):
        raise ValueError("STEP3_ADMIN200_SELF_USE_BEFORE_GRANT")
    # Preserve the existing operation-context wrapper when present.
    local_use = ("""if (uid == null ||
              FirebaseAuth.instance.currentUser?.uid != uid) {
            throw StateError('manager-cosmetic-account-changed');
          }
          await DedaSectionOperationContext.wait(() =>
            DedaCosmeticPremiumChoice20261115.select(
              uid, selectedTarget, row.identifier,
            ));""" if is_guarded else """if (uid == null ||
              FirebaseAuth.instance.currentUser?.uid != uid) {
            throw StateError('manager-cosmetic-account-changed');
          }
          await DedaCosmeticPremiumChoice20261115.select(
            uid, target!, row.identifier,
          );""")
    method = method[:match.start()] + local_use + method[match.end():]
    text = before + method + after
    for old, new in (
        ("'تم تأكيد الاستخدام أو المنح وحفظ الملكية'",
         "'تم تأكيد الزينة أو المنح وحفظ الملكية'"),
        ("'Grant and ownership confirmed'",
         "'Decorative choice or grant and ownership confirmed'"),
        ("'تم تثبيت الملكية. افتح معرّفاتي واضغط استخدام لتفعيله.'",
         "'تم تثبيت الملكية. افتح معرّفاتي واضغط تفعيل للزينة.'"),
        ("'Ownership confirmed. Activate it in My IDs.'",
         "'Ownership confirmed. Activate decoration in My IDs.'"),
        ("'استخدام لنفسي: '", "'زينة لملفي: '"),
        ("'Use myself: '", "'Decorate my profile: '"),
    ):
        if old in text:
            text = text.replace(old, new, 1)
    if (text.count(grant) != 1 or
            "DedaStage71OwnedIdentifierService.use(" in text or
            "DedaCosmeticPremiumChoice20261115.select(" not in text):
        raise ValueError("STEP3_ADMIN200_GRANT_OR_ALIAS_USE_UNSAFE")
    return text



def patch_admin_main(text):
    # The assembled settings state already contains its own entry refresh
    # logic, and may differ from the source-only fixture. Preserve it exactly.
    # Rewriting it on a source-text guess could hide the authorized card.
    # Read-only assertions verify both visibility and protected click gating.
    start = text.find("class _DedaSettingsPageState")
    if start < 0 or text.count("class _DedaSettingsPageState") != 1:
        raise ValueError("STEP3_ADMIN_SETTINGS_STATE_NOT_UNIQUE")
    state = text[start:]
    for expected in (
        "_adminEntryVisible",
        "_refreshAdminEntryVisibility()",
        "DedaBackend.currentDedaAccountCanSeeAdminEntry(",
        ".currentAdminSessionMatchesDedaEntry(",
        "if (_adminEntryVisible) ...[",
    ):
        if expected not in state:
            raise ValueError("STEP3_ADMIN_GATE_OR_CARD_MISSING_" + expected)
    return text  # byte-identical protected admin screen



def bind(project):
    project = Path(project).resolve()
    if project == ROOT or project in ROOT.parents or ROOT in project.parents:
        raise ValueError("STEP3_ISOLATED_PROJECT_REQUIRED")
    meta_path = project/"internal-build-inputs.json"
    meta = json.loads(meta_path.read_text())
    if (meta.get("package") != "com.diraq.ludo.d_iraq_ludo"
            or meta.get("profileCosmeticPremiumStep2", {}).get(
                "premiumActivationLocalOnly") is not True
            or meta.get("profileOriginalImmediateStep1", {}).get(
                "canonicalIdDisplayedWithoutPremiumProof") is not True
            or meta.get("completeOwnerDelivery") is not False
            or meta.get("productionExecutionPerformed") is not False
            or meta.get("financialRestoreEnabled") is not False
            or "originalFunctionalAndAdminParityStep3" in meta):
        raise ValueError("STEP3_VERIFIED_STEP2_ASSEMBLY_REQUIRED")

    paths = (UNI,SIX,FRIEND,SYNC,INK48,SHARE49,DUAL_ADMIN,MAIN,BACKEND,ADMIN,STAGE)
    before = {}
    for relative in paths:
        path=project/relative
        if not path.is_file() or meta["sourceHashes"].get(relative)!=sha(path):
            raise ValueError("STEP3_UNVERIFIED_SOURCE_"+relative)
        before[relative]=path.read_text()
    for must in (
        "currentDedaAccountCanSeeAdminEntry(",
        "currentAdminSessionMatchesDedaEntry(",
        "if (_adminEntryVisible) ...[",
    ):
        if must not in before[MAIN]:
            raise ValueError("STEP3_ADMIN_VISIBLE_GATE_MISSING_"+must)
    if "admin_entry_access" not in before[BACKEND] or (
        "currentDedaAccountCanSeeAdminEntry" not in before[BACKEND]):
        raise ValueError("STEP3_PROTECTED_ADMIN_AUTH_NOT_PRESENT")

    files={
        UNI:patch_unified(before[UNI]),
        SIX:patch_six(before[SIX]),
        FRIEND:patch_friend(before[FRIEND]),
        SYNC:patch_public_sync(before[SYNC]),
        INK48:patch_stage48(before[INK48]),
        SHARE49:patch_stage49(before[SHARE49]),
        DUAL_ADMIN:patch_admin200_self_use(before[DUAL_ADMIN]),
        MAIN:patch_admin_main(before[MAIN]),
    }
    policy_src=ROOT/POLICY
    if not policy_src.is_file() or (project/POLICY).exists():
        raise ValueError("STEP3_POLICY_COPY_CONFLICT")
    for relative,contents in files.items():
        (project/relative).write_text(contents)
        meta["sourceHashes"][relative]=sha(project/relative)
    shutil.copy2(policy_src,project/POLICY)
    meta["sourceHashes"][POLICY]=sha(project/POLICY)
    # Crucial guarantee: no backend/admin, Stage71 grants or rules touched.
    for relative in (BACKEND, ADMIN, STAGE):
        assert (project/relative).read_text()==before[relative]
    meta["originalFunctionalAndAdminParityStep3"]={
        "ownerProfileCosmeticPreserved":True,
        "allLegacyPremiumBadgesOutsideOwnerProfileDisabled":True,
        "allUnifiedFriendLeagueAndShareLabelsOriginal":True,
        "allUnifiedPremiumWatchesDisabled":True,
        "originalProfileCopyAndLocationSender":True,
        "publicActiveAliasPublicationDisabled":True,
        "adminEntryAuthAndPhoneGateUnchanged":True,
        "adminCardRechecksOnAuthAndResume":False,
        "adminCardVisibilityAndClickGateVerified":True,
        "admin200GrantPreservedSelfUseCosmeticOnly":True,
        "adminSettingsSourceByteUnchanged":True,
        "protectedBackendAdminAnd200IdsUnchanged":True,
        "originalPremiumAliasServerDocumentsPreserved":True,
        "productionRulesUnchanged":True,
        "firebaseOrPlayChanged":False,
        "apkBuilt":False,
        "fullPhoneAcceptancePending":True,
    }
    meta_path.write_text(json.dumps(meta,ensure_ascii=False,indent=2)+"\n")
    print("PASS_STEP3_ORIGINAL_ONLY_FUNCTIONAL_ADMIN_GATE_PRESERVED_NO_APK")


if __name__=="__main__":
    parser=argparse.ArgumentParser()
    parser.add_argument("project",type=Path)
    bind(parser.parse_args().project)
