from pathlib import Path

path = Path('lib/main.dart')
text = path.read_text(encoding='utf-8')

marker = '// DEDA_COMPACT_SOCIAL_FIELDS_100268'
if marker in text:
    print('compact social fields 100268 already applied')
    raise SystemExit(0)

friends_marker = '// DEDA_FRIENDS_PAGE_UI_100266'
add_marker = '// DEDA_ADD_FRIEND_UI_100267'
if friends_marker not in text or add_marker not in text:
    raise SystemExit('required 100266/100267 social markers not found')


def replace_once(src: str, old: str, new: str, label: str) -> str:
    count = src.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected 1 match, found {count}')
    return src.replace(old, new, 1)

# ----- Friends page: make search and empty-state card compact -----
pre = text[: text.index(friends_marker)]
friends = text[text.index(friends_marker): text.index(add_marker)]
add = text[text.index(add_marker):]

friends = replace_once(
    friends,
    'padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),',
    'padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),',
    'friends page outer padding',
)
friends = replace_once(
    friends,
    'const SizedBox(height: 16),',
    'const SizedBox(height: 10),',
    'friends header/search gap',
)
friends = replace_once(
    friends,
    'borderRadius: BorderRadius.circular(18),\n                          border: Border.all(',
    'borderRadius: BorderRadius.circular(14),\n                          border: Border.all(',
    'friends search radius',
)
friends = replace_once(
    friends,
    'fontSize: 13.5,',
    'fontSize: 12.5,',
    'friends search hint size',
)
friends = replace_once(
    friends,
    'horizontal: 14,\n                              vertical: 16,',
    'horizontal: 12,\n                              vertical: 10,',
    'friends search padding',
)
friends = replace_once(
    friends,
    'const SizedBox(height: 26),',
    'const SizedBox(height: 14),',
    'friends search/empty gap',
)
friends = replace_once(
    friends,
    'padding: const EdgeInsets.fromLTRB(24, 30, 24, 28),',
    'padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),',
    'friends empty card padding',
)
friends = replace_once(
    friends,
    'borderRadius: BorderRadius.circular(28),',
    'borderRadius: BorderRadius.circular(20),',
    'friends empty card radius',
)
friends = replace_once(friends, 'width: 88,\n                              height: 88,', 'width: 64,\n                              height: 64,', 'friends empty icon box')
friends = replace_once(friends, 'size: 44,', 'size: 32,', 'friends empty icon size')
friends = replace_once(friends, 'const SizedBox(height: 18),', 'const SizedBox(height: 12),', 'friends empty icon/title gap')
friends = replace_once(friends, 'fontSize: 23,', 'fontSize: 20,', 'friends empty title size')
friends = replace_once(friends, 'const SizedBox(height: 9),', 'const SizedBox(height: 6),', 'friends empty title/body gap')
friends = replace_once(
    friends,
    'height: 1.55,\n                                fontWeight: FontWeight.w600,\n                                fontSize: 14,',
    'height: 1.45,\n                                fontWeight: FontWeight.w600,\n                                fontSize: 13,',
    'friends empty body style',
)
friends = replace_once(friends, 'const SizedBox(height: 22),', 'const SizedBox(height: 14),', 'friends empty body/button gap')
friends = replace_once(
    friends,
    'horizontal: 20,\n                                    vertical: 15,',
    'horizontal: 18,\n                                    vertical: 11,',
    'friends add button padding',
)

# ----- Add friend page: compact cards and controls, keep all text inside -----
add = replace_once(
    add,
    'padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),',
    'padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),',
    'add friend outer padding',
)
add = replace_once(
    add,
    "_headerCard(),\n                const SizedBox(height: 18),\n                _myIdCard(myId),\n                const SizedBox(height: 18),\n                _searchCard(),\n                const SizedBox(height: 18),\n                _resultPlaceholder(),",
    "_headerCard(),\n                const SizedBox(height: 10),\n                _myIdCard(myId),\n                const SizedBox(height: 10),\n                _searchCard(),\n                const SizedBox(height: 10),\n                _resultPlaceholder(),",
    'add friend section gaps',
)
add = replace_once(
    add,
    'padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),',
    'padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),',
    'add friend header padding',
)
add = replace_once(add, 'borderRadius: BorderRadius.circular(24),', 'borderRadius: BorderRadius.circular(18),', 'add friend header radius')
add = replace_once(add, 'width: 66,\n            height: 66,', 'width: 52,\n            height: 52,', 'add friend header icon box')
add = replace_once(add, 'size: 34,', 'size: 28,', 'add friend header icon size')
add = replace_once(add, 'const SizedBox(width: 14),', 'const SizedBox(width: 10),', 'add friend header gap')
add = replace_once(add, 'fontSize: 20,', 'fontSize: 17,', 'add friend header title size')
add = replace_once(add, 'height: 1.45,\n                    fontWeight: FontWeight.w600,\n                    fontSize: 13.5,', 'height: 1.35,\n                    fontWeight: FontWeight.w600,\n                    fontSize: 12.5,', 'add friend header body style')

# My ID card
add = replace_once(add, 'padding: const EdgeInsets.all(16),', 'padding: const EdgeInsets.all(12),', 'my id card padding')
add = replace_once(add, 'borderRadius: BorderRadius.circular(22),', 'borderRadius: BorderRadius.circular(18),', 'my id card radius')
add = replace_once(add, 'fontSize: 16,', 'fontSize: 15,', 'my id title size')
add = replace_once(add, 'const SizedBox(height: 11),', 'const SizedBox(height: 7),', 'my id title gap')
add = replace_once(
    add,
    'padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),',
    'padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),',
    'my id inner padding',
)
add = replace_once(add, 'borderRadius: BorderRadius.circular(16),', 'borderRadius: BorderRadius.circular(13),', 'my id inner radius')
add = replace_once(add, 'fontSize: 16,', 'fontSize: 15,', 'my id value size')
add = replace_once(add, 'const SizedBox(width: 10),', 'const SizedBox(width: 6),', 'my id copy gap')
add = replace_once(add, 'icon: const Icon(Icons.copy_rounded, size: 20),', 'icon: const Icon(Icons.copy_rounded, size: 18),', 'my id copy icon size')
add = replace_once(add, 'fontSize: 12.5,', 'fontSize: 11.5,', 'my id helper size')

# Search card and field
add = replace_once(add, 'padding: const EdgeInsets.all(16),', 'padding: const EdgeInsets.all(12),', 'search card padding')
add = replace_once(add, 'borderRadius: BorderRadius.circular(24),', 'borderRadius: BorderRadius.circular(18),', 'search card radius')
add = replace_once(add, 'fontSize: 17,', 'fontSize: 15,', 'search title size')
add = replace_once(add, 'const SizedBox(height: 10),', 'const SizedBox(height: 7),', 'search title gap')
add = replace_once(add, 'prefixIcon: const Icon(Icons.alternate_email_rounded),\n                ', '', 'remove duplicate at icon')
add = replace_once(
    add,
    'horizontal: 14,\n                  vertical: 15,',
    'horizontal: 12,\n                  vertical: 9,',
    'friend id input padding',
)
# Two input radii: enabled and focused borders.
old_radius = 'borderRadius: BorderRadius.circular(16),'
if add.count(old_radius) < 2:
    raise SystemExit('friend id border radii not found twice')
add = add.replace(old_radius, 'borderRadius: BorderRadius.circular(13),', 2)
add = replace_once(add, 'const SizedBox(height: 12),', 'const SizedBox(height: 8),', 'input/button gap')
add = replace_once(add, 'icon: const Icon(Icons.search_rounded, size: 22),', 'icon: const Icon(Icons.search_rounded, size: 19),', 'search button icon size')
add = replace_once(add, 'fontSize: 16,', 'fontSize: 14,', 'search button label size')
add = replace_once(add, 'padding: const EdgeInsets.symmetric(vertical: 14),', 'padding: const EdgeInsets.symmetric(vertical: 10),', 'search button padding')
add = replace_once(add, 'borderRadius: BorderRadius.circular(17),', 'borderRadius: BorderRadius.circular(13),', 'search button radius')

# Result placeholder compactness
add = replace_once(
    add,
    'padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),',
    'padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),',
    'result card padding',
)
add = replace_once(add, 'borderRadius: BorderRadius.circular(22),', 'borderRadius: BorderRadius.circular(18),', 'result card radius')
add = replace_once(add, 'width: 48,\n            height: 48,', 'width: 40,\n            height: 40,', 'result icon box')
add = replace_once(add, 'size: 29,', 'size: 24,', 'result icon size')
add = replace_once(add, 'const SizedBox(width: 12),', 'const SizedBox(width: 10),', 'result icon/text gap')
add = replace_once(add, 'fontSize: 15,', 'fontSize: 14,', 'result title size')

text = pre + friends + add
text = text.rstrip() + '\n\n' + marker + '\n'
path.write_text(text, encoding='utf-8')
print('applied DEDA 100268 compact social fields polish')
