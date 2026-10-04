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


def replace_n(src: str, old: str, new: str, n: int, label: str) -> str:
    count = src.count(old)
    if count != n:
        raise SystemExit(f'{label}: expected {n} matches, found {count}')
    return src.replace(old, new, n)

pre = text[: text.index(friends_marker)]
friends = text[text.index(friends_marker): text.index(add_marker)]
add_all = text[text.index(add_marker):]

# Friends page: compact search and empty-state card.
friends = replace_once(friends, 'padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),', 'padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),', 'friends outer padding')
friends = replace_once(friends, 'const SizedBox(height: 16),', 'const SizedBox(height: 10),', 'friends header gap')
friends = replace_once(friends, 'borderRadius: BorderRadius.circular(18),\n                          border: Border.all(', 'borderRadius: BorderRadius.circular(14),\n                          border: Border.all(', 'friends search radius')
friends = replace_once(friends, 'fontSize: 13.5,', 'fontSize: 12.5,', 'friends search hint size')
friends = replace_once(friends, 'horizontal: 14,\n                              vertical: 16,', 'horizontal: 12,\n                              vertical: 10,', 'friends search padding')
friends = replace_once(friends, 'const SizedBox(height: 26),', 'const SizedBox(height: 14),', 'friends search/empty gap')
friends = replace_once(friends, 'padding: const EdgeInsets.fromLTRB(24, 30, 24, 28),', 'padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),', 'friends empty padding')
friends = replace_once(friends, 'borderRadius: BorderRadius.circular(28),', 'borderRadius: BorderRadius.circular(20),', 'friends empty radius')
friends = replace_once(friends, 'width: 88,\n                              height: 88,', 'width: 64,\n                              height: 64,', 'friends empty icon box')
friends = replace_once(friends, 'size: 44,', 'size: 32,', 'friends empty icon size')
friends = replace_once(friends, 'const SizedBox(height: 18),', 'const SizedBox(height: 12),', 'friends icon/title gap')
friends = replace_once(friends, 'fontSize: 23,', 'fontSize: 20,', 'friends empty title size')
friends = replace_once(friends, 'const SizedBox(height: 9),', 'const SizedBox(height: 6),', 'friends title/body gap')
friends = replace_once(friends, 'height: 1.55,\n                                fontWeight: FontWeight.w600,\n                                fontSize: 14,', 'height: 1.45,\n                                fontWeight: FontWeight.w600,\n                                fontSize: 13,', 'friends body style')
friends = replace_once(friends, 'const SizedBox(height: 22),', 'const SizedBox(height: 14),', 'friends body/button gap')
friends = replace_once(friends, 'horizontal: 20,\n                                    vertical: 15,', 'horizontal: 18,\n                                    vertical: 11,', 'friends add button padding')

# Split Add Friend page by method, so repeated values never cross sections.
for needle in ['Widget _headerCard()', 'Widget _myIdCard(String myId)', 'Widget _searchCard()', 'Widget _resultPlaceholder()']:
    if needle not in add_all:
        raise SystemExit('Add Friend section not found: ' + needle)

i_header = add_all.index('Widget _headerCard()')
i_myid = add_all.index('Widget _myIdCard(String myId)')
i_search = add_all.index('Widget _searchCard()')
i_result = add_all.index('Widget _resultPlaceholder()')

add_prefix = add_all[:i_header]
header = add_all[i_header:i_myid]
myid = add_all[i_myid:i_search]
search = add_all[i_search:i_result]
result = add_all[i_result:]

# Main Add Friend spacing.
add_prefix = replace_once(add_prefix, 'padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),', 'padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),', 'add friend outer padding')
add_prefix = replace_once(
    add_prefix,
    "_headerCard(),\n                const SizedBox(height: 18),\n                _myIdCard(myId),\n                const SizedBox(height: 18),\n                _searchCard(),\n                const SizedBox(height: 18),\n                _resultPlaceholder(),",
    "_headerCard(),\n                const SizedBox(height: 10),\n                _myIdCard(myId),\n                const SizedBox(height: 10),\n                _searchCard(),\n                const SizedBox(height: 10),\n                _resultPlaceholder(),",
    'add friend section gaps',
)

# Header card.
header = replace_once(header, 'padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),', 'padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),', 'header padding')
header = replace_once(header, 'borderRadius: BorderRadius.circular(24),', 'borderRadius: BorderRadius.circular(18),', 'header radius')
header = replace_once(header, 'width: 66,\n            height: 66,', 'width: 52,\n            height: 52,', 'header icon box')
header = replace_once(header, 'size: 34,', 'size: 28,', 'header icon size')
header = replace_once(header, 'const SizedBox(width: 14),', 'const SizedBox(width: 10),', 'header icon gap')
header = replace_once(header, 'fontSize: 20,', 'fontSize: 17,', 'header title size')
header = replace_once(header, 'height: 1.45,\n                    fontWeight: FontWeight.w600,\n                    fontSize: 13.5,', 'height: 1.35,\n                    fontWeight: FontWeight.w600,\n                    fontSize: 12.5,', 'header body style')

# My DEDA ID card.
myid = replace_once(myid, 'padding: const EdgeInsets.all(16),', 'padding: const EdgeInsets.all(12),', 'my id padding')
myid = replace_once(myid, 'borderRadius: BorderRadius.circular(22),', 'borderRadius: BorderRadius.circular(18),', 'my id radius')
myid = replace_n(myid, 'fontSize: 16,', 'fontSize: 15,', 2, 'my id title/value sizes')
myid = replace_once(myid, 'const SizedBox(height: 11),', 'const SizedBox(height: 7),', 'my id title gap')
myid = replace_once(myid, 'padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),', 'padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),', 'my id inner padding')
myid = replace_once(myid, 'borderRadius: BorderRadius.circular(16),', 'borderRadius: BorderRadius.circular(13),', 'my id inner radius')
myid = replace_once(myid, 'const SizedBox(width: 10),', 'const SizedBox(width: 6),', 'my id copy gap')
myid = replace_once(myid, 'icon: const Icon(Icons.copy_rounded, size: 20),', 'icon: const Icon(Icons.copy_rounded, size: 18),', 'my id copy icon')
myid = replace_once(myid, 'fontSize: 12.5,', 'fontSize: 11.5,', 'my id helper size')

# Friend ID search card. Remove the decorative @ icon because the actual ID already contains @.
search = replace_once(search, 'padding: const EdgeInsets.all(16),', 'padding: const EdgeInsets.all(12),', 'search padding')
search = replace_once(search, 'borderRadius: BorderRadius.circular(24),', 'borderRadius: BorderRadius.circular(18),', 'search radius')
search = replace_once(search, 'fontSize: 17,', 'fontSize: 15,', 'search title size')
search = replace_once(search, 'const SizedBox(height: 10),', 'const SizedBox(height: 7),', 'search title gap')
search = replace_once(search, 'prefixIcon: const Icon(Icons.alternate_email_rounded),\n                ', '', 'duplicate at icon')
search = replace_once(search, 'horizontal: 14,\n                  vertical: 15,', 'horizontal: 12,\n                  vertical: 9,', 'friend id input padding')
search = replace_n(search, 'borderRadius: BorderRadius.circular(16),', 'borderRadius: BorderRadius.circular(13),', 2, 'friend id borders')
search = replace_once(search, 'const SizedBox(height: 12),', 'const SizedBox(height: 8),', 'input/button gap')
search = replace_once(search, 'icon: const Icon(Icons.search_rounded, size: 22),', 'icon: const Icon(Icons.search_rounded, size: 19),', 'search button icon')
search = replace_once(search, 'fontSize: 16,', 'fontSize: 14,', 'search button label')
search = replace_once(search, 'padding: const EdgeInsets.symmetric(vertical: 14),', 'padding: const EdgeInsets.symmetric(vertical: 10),', 'search button padding')
search = replace_once(search, 'borderRadius: BorderRadius.circular(17),', 'borderRadius: BorderRadius.circular(13),', 'search button radius')

# Search result placeholder.
result = replace_once(result, 'padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),', 'padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),', 'result padding')
result = replace_once(result, 'borderRadius: BorderRadius.circular(22),', 'borderRadius: BorderRadius.circular(18),', 'result radius')
result = replace_once(result, 'width: 48,\n            height: 48,', 'width: 40,\n            height: 40,', 'result icon box')
result = replace_once(result, 'size: 29,', 'size: 24,', 'result icon size')
result = replace_once(result, 'const SizedBox(width: 12),', 'const SizedBox(width: 10),', 'result icon gap')
result = replace_once(result, 'fontSize: 15,', 'fontSize: 14,', 'result title size')

add = add_prefix + header + myid + search + result
text = pre + friends + add
text = text.rstrip() + '\n\n' + marker + '\n'
path.write_text(text, encoding='utf-8')
print('applied DEDA 100268 compact social fields polish')
