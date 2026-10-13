"""DEDA Heartbeat: fail-closed UI refinements after 100332 reconstruction.

Does NOT deploy Firestore/Functions/Play and never writes real place records.
Run after stage_owner_branding_100332_2026_10_13.py, before flutter analyze.
"""
from pathlib import Path
main_path = Path("lib/main.dart")
toggle_path = Path("lib/deda_admin_automation_toggle.dart")
main = main_path.read_text()
toggle = toggle_path.read_text()
FLAG = "DEDA_HEARTBEAT_OWNER_UI_100333"
if FLAG in main:
    raise SystemExit("Already applied")

def replace_once(source, old, new, description):
    count = source.count(old)
    if count != 1:
        raise RuntimeError(f"SAFE_STOP {description}: expected 1, found {count}")
    return source.replace(old, new, 1)

start = main.index("class _OwnerPlacePageState extends State<OwnerPlacePage> {")
end = main.index("class PersonalPlacesPage", start)
owner = main[start:end]
# Approval number/date still have exact original fields and approved message
# remains untouched in Firestore. Eliminate only generated redundant display.
owner = replace_once(
    owner,
    "  Widget _statusCard() {",
    """  // DEDA_HEARTBEAT_OWNER_UI_100333: display deduplicated approval text only.
  // Never rewrite or erase an administrator's original approved message.
  String _approvalMessageForCard() {
    final raw = (_approvalMessage ?? '').trim();
    if (raw.isEmpty || _status != 'approved') return raw;
    final number = (_approvalNumber ?? '').trim();
    final date = (_approvalDate ?? '').trim();
    return raw.split('\\n').where((row) {
      final value = row.trim();
      if (value.isEmpty || value == 'DEDA - الدليل الدقيق') return false;
      if (number.isNotEmpty &&
          ((value.startsWith('رقم الاعتماد:') ||
            value.startsWith('Approval number:')) && value.contains(number))) {
        return false;
      }
      if (date.isNotEmpty &&
          ((value.startsWith('تاريخ الاعتماد:') ||
            value.startsWith('Approval date:')) && value.contains(date))) {
        return false;
      }
      return true;
    }).join('\\n');
  }

  Widget _statusCard() {""",
    "approval display helper"
)
owner = replace_once(
    owner,
    "if (_approvalMessage?.trim().isNotEmpty == true) ...[",
    "if (_approvalMessageForCard().isNotEmpty) ...[",
    "approval conditional"
)
owner = replace_once(
    owner,
    "SelectableText(\n                _approvalMessage!,",
    "SelectableText(\n                _approvalMessageForCard(),",
    "approval text"
)
# The existing 14-colour palette is preserved, with visible accessible
# outline/label colours on inputs even when a pastel is selected.
owner = replace_once(
    owner,
    """  InputDecoration _fieldDecoration({
    required String label,
    required IconData icon,
    String? hint,
  }) {
    return InputDecoration(""",
    """  InputDecoration _fieldDecoration({
    required String label,
    required IconData icon,
    String? hint,
  }) {
    // A light swatch uses its vivid primary for the outline and label.
    final primaryIndex = _placeThemeIndex.isOdd
        ? _placeThemeIndex - 1 : _placeThemeIndex;
    final accent = DedaPlacePalette.forIndex(primaryIndex);
    return InputDecoration(""",
    "owner field accent"
)
owner = replace_once(
    owner,
    "prefixIcon: Icon(icon, color: const Color(0xFF17652F)),",
    "prefixIcon: Icon(icon, color: accent),",
    "owner field icon"
)
owner = replace_once(
    owner,
    "borderSide: const BorderSide(color: Color(0xFFAAB5AB)),",
    "borderSide: BorderSide(color: accent.withOpacity(0.58)),",
    "owner enabled outline"
)
owner = replace_once(
    owner,
    "borderSide: const BorderSide(color: Color(0xFF17652F), width: 2),",
    "borderSide: BorderSide(color: accent, width: 2),",
    "owner focused outline"
)
# A genuine count is displayed in full. Disabled backend displays words,
# never a fabricated zero or a dash that looks like missing real numbers.
owner = replace_once(
    owner,
    """            Text(value, style: TextStyle(
              fontSize: 17, fontWeight: FontWeight.bold, color: color,
            )),""",
    """            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(value, maxLines: 1, softWrap: false,
                  style: TextStyle(
                    fontSize: 17, fontWeight: FontWeight.bold, color: color,
                  ),
                ),
              ),
            ),""",
    "owner long count overflow"
)
owner = replace_once(
    owner,
    """    final loading = _metricsLoading || _placeOwnerMetrics == null;
    return Padding(""",
    """    final loading = _metricsLoading || _placeOwnerMetrics == null;
    final disabled = !DedaPlaceEngagementService.live;
    return Padding(""",
    "owner count availability"
)
owner = replace_once(
    owner,
    """loading ? '—' : _placeOwnerMetrics!.followers.toString()""",
    """disabled ? dedaText('قريباً', 'Pending')
                  : (loading ? '…' : _placeOwnerMetrics!.followers.toString())""",
    "follower count safe unavailable"
)
owner = replace_once(
    owner,
    """loading ? '—' : _placeOwnerMetrics!.likes.toString()""",
    """disabled ? dedaText('قريباً', 'Pending')
                  : (loading ? '…' : _placeOwnerMetrics!.likes.toString())""",
    "like count safe unavailable"
)
main = main[:start] + owner + main[end:]
# Preserve the same authorized toggle and server readiness logic. Only
# the AUTO PLACE panel is compact; the separate PIN recovery card is untouched.
toggle = replace_once(
    toggle,
    """                      title: Text(title,
                        style: const TextStyle(fontWeight: FontWeight.w800,
                          fontSize: 15)),
                      subtitle: Text(help,
                        style: const TextStyle(fontSize: 12.5)),""",
    """                      title: Tooltip(
                        message: help,
                        child: Text(title, maxLines: _place ? 2 : null,
                          style: const TextStyle(fontWeight: FontWeight.w800,
                            fontSize: 15)),
                      ),
                      subtitle: _place ? null : Text(help,
                        style: const TextStyle(fontSize: 12.5)),""",
    "compact place automation title"
)
toggle = replace_once(
    toggle,
    """                    Text(_error ?? blocked,
                      textAlign: TextAlign.start,
                      style: TextStyle(fontSize: 12,
                        color: _error == null
                            ? const Color(0xFF3B6043)
                            : const Color(0xFF9C3324))),""",
    """                    if (!_place || _error != null)
                      Text(_error ?? blocked,
                        textAlign: TextAlign.start,
                        style: TextStyle(fontSize: 12,
                          color: _error == null
                              ? const Color(0xFF3B6043)
                              : const Color(0xFF9C3324))),""",
    "compact place automation details"
)
# Owner image selector is intentionally absent; category logo should
# remain independent of the old stale local preview.
assert "onPressed: _chooseOwnerLogo" not in owner
assert "localFilePath: ''" in owner
assert "DedaPlaceSuggestions.iconForCategory(" in owner
assert "DedaBackend.submitPlace(data)" in owner
assert "DedaBackend.resubmitPlaceRequest(" in owner
assert "DedaBackend.ownerPlaceNotifications(" in owner
assert "onChanged: _saving" in toggle
assert main.count(FLAG) == 1

main_path.write_text(main)
toggle_path.write_text(toggle)
print("PASS Heartbeat UI: deduplicated approval details, readable colour")
print("outlines, truthful non-live counts, long-count scaling, compact")
print("place automation UI. All requests, PIN and server flags preserved.")
