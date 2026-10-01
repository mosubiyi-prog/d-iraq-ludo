from pathlib import Path

MAIN = Path('lib/main.dart')
s = MAIN.read_text(encoding='utf-8')
original = s


def replace_once(old: str, new: str, label: str) -> None:
    global s
    count = s.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected exactly 1 match, found {count}')
    s = s.replace(old, new, 1)


# 1) All tasks shown on the Daily Tasks page must roll over at local midnight.
# Keep old ledger/awards untouched so accumulated points never reset.
old_cycle = """  /// Development cycle id. Weekly definitions will later supply their own
  /// Firestore weekId, so changing rollover policy will not change task IDs.
  static String currentLocalCycleId([DateTime? value]) {
    final now = (value ?? DateTime.now()).toLocal();
    final monday = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: now.weekday - DateTime.monday));
    final y = monday.year.toString().padLeft(4, '0');
    final m = monday.month.toString().padLeft(2, '0');
    final d = monday.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
"""
new_cycle = """  /// Local progress cycle for the tasks shown on the Daily Tasks page.
  /// A new local calendar day creates fresh completion/claim keys while old
  /// awards stay in the ledger, so accumulated points are never reset.
  static String currentLocalCycleId([DateTime? value]) {
    return currentLocalDayId(value);
  }
"""
replace_once(old_cycle, new_cycle, 'daily task rollover')

# 2) The persisted awards ledger is the source of truth for card sequencing.
# Do not reject a card from a stale in-memory claimed set before reading state.
old_gate = """    final previousThreshold = index == 0 ? null : _pointTierThresholds[index - 1];
    if (previousThreshold != null &&
        !_claimedPointTiers.contains(previousThreshold)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            dedaText(
              'استلم نقاط المرحلة السابقة أولًا حتى تفتح هذه البطاقة.',
              'Claim the previous stage first to unlock this card.',
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
      return;
    }

    try {
"""
new_gate = """    final previousThreshold = index == 0 ? null : _pointTierThresholds[index - 1];

    // The persisted task-points ledger is authoritative. The in-memory set can
    // be briefly stale after returning to this page, so sequencing is verified
    // below against point_tier_claim|<threshold> before a new card is opened.
    try {
"""
replace_once(old_gate, new_gate, 'remove stale in-memory tier gate')

# 3) After a tier claim, immediately reload persisted tier state. This keeps
# the next card visual lock in sync with the just-written claim.
old_claim_sync = """      if (!mounted) return;
      setState(() {
        _claimedPointTiers.add(threshold);
        _claimingPointTiers.remove(threshold);
      });
      ScaffoldMessenger.of(context).showSnackBar(
"""
new_claim_sync = """      if (!mounted) return;
      setState(() {
        _claimedPointTiers.add(threshold);
        _claimingPointTiers.remove(threshold);
      });
      await _loadOpenedPointTiers();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
"""
replace_once(old_claim_sync, new_claim_sync, 'refresh tier sequence after claim')

# 4) Refresh persisted tier state when a locked card is tapped before applying
# sequencing. This makes an already-persisted previous claim recover cleanly.
old_open_start = """  Future<void> _openPointTier(int threshold, int totalPoints) async {
    final index = _pointTierIndex(threshold);
    if (index < 0 || _openedPointTiers.contains(threshold)) return;

    final previousThreshold = index == 0 ? null : _pointTierThresholds[index - 1];
"""
new_open_start = """  Future<void> _openPointTier(int threshold, int totalPoints) async {
    await _loadOpenedPointTiers();
    if (!mounted) return;

    final index = _pointTierIndex(threshold);
    if (index < 0 || _openedPointTiers.contains(threshold)) return;

    final previousThreshold = index == 0 ? null : _pointTierThresholds[index - 1];
"""
replace_once(old_open_start, new_open_start, 'refresh tier state before open')

if s == original:
    raise SystemExit('no changes produced')

MAIN.write_text(s, encoding='utf-8')
print('patched daily rollover and points-card sequence safely')
