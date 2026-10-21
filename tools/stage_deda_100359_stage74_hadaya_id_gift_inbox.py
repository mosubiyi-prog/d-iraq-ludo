#!/usr/bin/env python3
"""Add received ID gift section INTO the existing original DEDA 'هداياي' page.

Applies after reconstructing actual 100359 and stage71. Does NOT replace any
diamond gift cards, stream, claim handler or Firestore wallet; modifies only
the page's body layout to add our verified ID gift inbox above old gifts.
"""
from pathlib import Path

MAIN = Path('lib/main.dart')
MARK = '// DEDA_STAGE74_HADAYA_GIFTED_IDENTIFIERS_AND_DIAMOND_HISTORY_PRESERVED'
IMPT = "import 'deda_stage74_hadaya_identifier_section.dart';\n"
HEAD = 'class _DedaMyGiftsPageState extends State<DedaMyGiftsPage> {'
END = 'class DedaMyGiftsPage extends StatefulWidget {'

def once(s, a, b):
    if s.count(a) != 1:
        raise ValueError('SAFE_STOP_STAGE74_EXPECTED_SINGLE_ANCHOR_'+repr(a[:100])+'_'+str(s.count(a)))
    return s.replace(a,b,1)

def patch(src):
    if MARK in src:
        if src.count(MARK) != 1 or src.count(IMPT) != 1:
            raise ValueError('SAFE_STOP_STAGE74_PARTIAL_GIFT_INBOX')
        return src
    if src.count(HEAD) != 1 or src.count(END) != 1:
        raise ValueError('SAFE_STOP_STAGE74_ORIGINAL_GIFTS_PAGE_MISSING')
    begin = src.index(HEAD)
    finish = src.index('  Widget _giftCard(', begin)
    section = src[begin:finish]
    if ('DedaBackend.claimDiamondGift(' not in section or
        'DedaBackend.watchPersonalDiamondGifts(_publicId)' not in section or
        '...gifts.map(_giftCard)' not in section):
        raise ValueError('SAFE_STOP_STAGE74_LEGACY_DIAMOND_GIFT_FLOW_CHANGED')
    section = once(
        section,
        ': StreamBuilder<List<Map<String, dynamic>>>(\n',
        ': Column(children: <Widget>[\n'
        '              DedaStage74IdGiftsSection(originalId: _publicId),\n'
        '              Expanded(child: StreamBuilder<List<Map<String, dynamic>>>(\n')
    section = once(
        section,
        '            ),\n    );\n  }\n\n',
        '            )),\n            ]),\n    );\n  }\n\n')
    if 'DedaStage74IdGiftsSection(originalId: _publicId)' not in section:
        raise ValueError('SAFE_STOP_STAGE74_HADAYA_INSERTION_INCOMPLETE')
    if src.count("import 'package:flutter/material.dart';\n") != 1:
        raise ValueError('SAFE_STOP_STAGE74_FLUTTER_IMPORT_MISSING')
    src = once(src,
        "import 'package:flutter/material.dart';\n",
        "import 'package:flutter/material.dart';\n"+IMPT)
    start = src.index(HEAD)
    end = src.index('  Widget _giftCard(', start)
    return src[:start] + '  '+MARK+'\n'+section+src[end:]

if __name__ == '__main__':
    previous = MAIN.read_text()
    updated = patch(previous)
    if updated != previous:
        MAIN.write_text(updated)
    print('PASS_STAGE74_ORIGINAL_HADAYA_DIAMOND_GIFTS_INTACT_ID_RECEIPT_INBOX_ADDED')
