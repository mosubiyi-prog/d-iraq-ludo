#!/usr/bin/env python3
"""DEDA 100343: keep edit-profile avatar preview always visible.

Patch ONLY the reconstructed DedaEditProfilePage layout after 100342 point7.
Move existing real preview widget into a fixed top slot and allow only
selection gallery/background/name to scroll under it. No state persistence,
purchase, wallet, Firebase, friends, or navigation modification.
"""
from pathlib import Path

file = Path("lib/main.dart")
source = file.read_text(encoding="utf-8")
marker = "// DEDA_100343_STICKY_EDIT_PROFILE_PREVIEW"
assert marker not in source, "SAFE_STOP sticky stage already applied"
assert "DEDA_100342_POINT7_COMPACT_IDS_UI_ONLY" in source, \
    "SAFE_STOP apply point7 source first"
start = "class _DedaEditProfilePageState extends State<DedaEditProfilePage> {"
end = "class DedaAccountInfoPage extends StatefulWidget {"
assert source.count(start) == 1 and source.count(end) == 1, \
    "SAFE_STOP edit profile anchors missing"
a = source.index(start)
b = source.index(end, a)
old = source[a:b]

prefix = """      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 30),
          children: [
"""
assert old.count(prefix) == 1, "SAFE_STOP edit gallery list changed"
p = old.index(prefix)
begin = p + len(prefix)
portrait = old.find("                child: DedaFramedAvatar(", begin)
assert portrait > begin, "SAFE_STOP actual portrait preview missing"
# Stop at the next top-level widget (the read-only ID card added in
# 100341), NOT at an inner closing paren of Center/DedaFramedAvatar.
next_widget = """            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
"""
assert old.count(next_widget) == 1, "SAFE_STOP read-only ID anchor moved"
end_preview = old.index(next_widget, portrait)
preview = old[begin:end_preview]
assert preview.rstrip().endswith("),"), "SAFE_STOP portrait root not complete"
assert preview.count("DedaFramedAvatar(") == 1
assert preview.startswith("            Container(\n")
assert preview.count("constraints: const BoxConstraints(minHeight: 166),") == 1
assert preview.count("size: 142,") == 1
assert "avatarStyle: _avatarStyle" in preview and \
    "frameStyle: _frameStyle" in preview and \
    "dedaProfileBackgroundColors(_backgroundStyle)" in preview, \
    "SAFE_STOP selection-dependent preview changed"

# Keep the exact accepted preview visuals, just reduce its slot modestly so
# it does not hide the scrolling three-column controls on smaller phones.
fixed = preview.replace(
    "            Container(\n",
    "Container(\n              key: const Key('deda_sticky_preview_avatar_card'),\n", 1
).replace(
    "constraints: const BoxConstraints(minHeight: 166),",
    "constraints: const BoxConstraints(minHeight: 154, maxHeight: 154),", 1
).replace("size: 142,", "size: 126,", 1)

new_prefix = """      // DEDA_100343_STICKY_EDIT_PROFILE_PREVIEW
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 9, 18, 5),
              child: """ + fixed + """            ),
            Expanded(
              child: ListView(
                key: const Key('deda_edit_profile_scroll_choices'),
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 30),
                children: [
"""

# We added a Column/Expanded pair, so finish the existing ListView,
# then close Expanded, Column, SafeArea and Scaffold in exact order.
old_ending = """          ],
        ),
      ),
    );
  }
}
"""
new_ending = """                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
"""
assert old.count(old_ending) == 1, "SAFE_STOP unique profile build ending changed"
new = old[:p] + new_prefix + old[end_preview:]
assert new.count(old_ending) == 1, \
    "SAFE_STOP after moving preview original closing not found"
new = new.replace(old_ending, new_ending, 1)

# Ensure gallery and all form/storage remain exactly once with no
# changed save handlers or legacy selected frame behavior.
for needle in (
    "Future<void> _save() async",
    "await DedaPreferences.setProfileAppearance(",
    "onTap: () => setState(() => _avatarStyle = index)",
    "onPressed: _saving ? null : _save",
    "DedaProfileFramePreview(",
    "deda_point7_current_id_chip",
):
    # point7 marker exists outside edit page, so test first five here only.
    if needle != "deda_point7_current_id_chip":
        assert needle in new, "SAFE_STOP edit behavior lost: " + needle
assert new.count("deda_sticky_preview_avatar_card") == 1
assert new.count("deda_edit_profile_scroll_choices") == 1
assert new.count("DedaFramedAvatar(") == old.count("DedaFramedAvatar("), \
    "SAFE_STOP duplicate or lost avatar"
result = source[:a] + new + source[b:]
assert result[:a] == source[:a] and result[a + len(new):] == source[b:], \
    "SAFE_STOP unrelated source changed"
file.write_text(result, encoding="utf-8")
print("PASS: preview pinned below edit-profile appbar, galleries scroll separately")
print("PASS: existing avatar/frame/background choices and persistence untouched")
