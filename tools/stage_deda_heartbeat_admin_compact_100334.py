"""DEDA Heartbeat 100334: fix oversized fixed admin auto-approval header.

Run strictly AFTER 100333 UI script, before dart format/analyze.
Only owner field category glyph and the general-manager place toggle UI change.
All backend guards, approval, requests, history, navigation stay unchanged.
"""
from pathlib import Path
main_path = Path("lib/main.dart")
toggle_path = Path("lib/deda_admin_automation_toggle.dart")
main = main_path.read_text(encoding="utf-8")
toggle = toggle_path.read_text(encoding="utf-8")
marker = "// DEDA_HEARTBEAT_ADMIN_COMPACT_100334"
if marker in toggle:
    raise SystemExit("DEDA 100334 already staged.")

assert "DEDA_HEARTBEAT_OWNER_UI_100333" in main, "SAFE_STOP: apply 100333 first"
assert "DedaPlaceSuggestions.iconForCategory" in main, "SAFE_STOP: missing category-icon helper"
old = """                              label: dedaText('اسم المكان', 'Place name'),
                              icon: Icons.storefront_outlined,
                            ),"""
new = """                              label: dedaText('اسم المكان', 'Place name'),
                              icon: DedaPlaceSuggestions.iconForCategory(
                                _categoryCode,
                                _otherCategoryTextController.text,
                              ),
                            ),"""
start = main.index("class _OwnerPlacePageState extends State<OwnerPlacePage> {")
end = main.index("class PersonalPlacesPage", start)
owner = main[start:end]
if owner.count(old) != 1:
    raise RuntimeError("SAFE_STOP: ambiguous owner place-name icon")
owner = owner.replace(old, new, 1)
main_next = main[:start] + owner + main[end:]

# The long fixed-height top Card reserves room while requests scroll beneath.
# Replace it with a single-line real toggle control, directly above request tabs.
# Do NOT alter the separate PIN recovery automation or server-side checks.
build_start = toggle.index("  @override\n  Widget build(BuildContext context)")
t = toggle[build_start:]
old_anchor = """    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 12, 6),"""
if t.count(old_anchor) != 1:
    raise RuntimeError("SAFE_STOP: admin toggle build anchor changed")
compact = """    // DEDA_HEARTBEAT_ADMIN_COMPACT_100334
    // A 1-row control for the general-manager place request screen only.
    // Preserve the original guarded _setEnabled and PIN layout below.
    if (_place) {
      final canChange = !_saving && !_loading && _error == null &&
          (DedaLaunchFeatureGates.serverFeaturesEnabled || _enabled) &&
          (_backendReady || _enabled);
      return Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(12, 4, 12, 4),
        child: Tooltip(
          message: _error ?? blocked,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFFEAF4EA),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF9FBDA3)),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(10, 1, 6, 1),
                child: Row(
                  children: [
                    const Icon(Icons.verified_outlined,
                        size: 20, color: Color(0xFF17652F)),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        t('الاعتماد التلقائي', 'Auto approval'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Color(0xFF17652F),
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (_loading)
                      const SizedBox(
                        width: 36, height: 36,
                        child: Padding(
                          padding: EdgeInsets.all(8),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    else
                      Switch.adaptive(
                        value: _enabled,
                        onChanged: canChange ? _setEnabled : null,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }
"""
t = t.replace(old_anchor, compact + old_anchor, 1)
toggle_next = toggle[:build_start] + t
assert toggle_next.count(marker) == 1
for token in [
  'Future<bool> _confirmLiveWorker() async',
  'Future<void> _setEnabled(bool next) async',
  "kind == 'place_auto_approval'",
  "pin_auto_recovery",
  'DedaBackend.normalizeAdminRole(profile[\'role\'])',
  "if (_place) {",
  'onChanged: canChange ? _setEnabled : null',
  'value: _enabled',
]:
    assert token in toggle_next, "SAFE_STOP: auth/control lost: " + token
assert "DedaBackend.finalizePlaceApproval" in main_next or "DedaBackend.submitPlace(data)" in main_next
# Only write once all exact checks have passed.
main_path.write_text(main_next, encoding="utf-8")
toggle_path.write_text(toggle_next, encoding="utf-8")
print("PASS 100334: auto-approval panel is one compact control above requests.")
print("PASS: pharmacy/place name icon follows category; backend guards untouched.")
print("No deployment, no production writes, no Play publish.")
