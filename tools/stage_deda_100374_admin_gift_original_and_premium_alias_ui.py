#!/usr/bin/env python3
"""Owner QA: admin gems recipient search accepts authenticated premium alias.

No production callable deploy/flag flip, no Firestore rules/credit/debit, no
change to real grantDiamondGift transaction targetPublicId (canonical).
Apply AFTER exact original admin gifts UI reconstruction.
"""
from pathlib import Path

ADMIN=Path('lib/admin_pages.dart')
PREVIEW=Path('lib/deda_gift_recipient_preview.dart')
MARK='// DEDA_QA32_ADMIN_GM_ALIAS_TO_ORIGINAL_GIFT_TARGET_SAFE_NO_DEPLOY'
IMPORT="import 'deda_qa32_admin_gift_recipient_alias_bridge.dart';\n"
GIFT_START='class _DedaAdminDiamondGiftPageState'
GIFT_END='class '  # find next class (or end of file)

def once(s,old,new,label):
    if s.count(old)!=1:
        raise ValueError('SAFE_STOP_QA32_ADMIN_'+label+'_COUNT='+str(s.count(old)))
    return s.replace(old,new,1)

def patch_admin(s):
    if MARK in s:
        if s.count(MARK)!=1 or s.count(IMPORT)!=1:
            raise ValueError('SAFE_STOP_QA32_ADMIN_PARTIAL_PATCH')
        return s
    if s.count(GIFT_START)!=1 or "class DedaAdminDiamondGiftPage" not in s:
        raise ValueError('SAFE_STOP_QA32_GM_GIFT_PAGE_MISSING')
    a=s.index(GIFT_START)
    b=s.find('\nclass ',a+len(GIFT_START))
    if b<0:b=len(s)
    gift=s[a:b]
    old="final target = await DedaBackend.adminDiamondGiftTarget(raw);"
    new=MARK+"\n      final target = await DedaQa32AdminGiftRecipientAliasBridge.verifiedTarget(raw);"
    gift=once(gift,old,new,'LOOKUP')
    if "targetPublicId: target['publicId'].toString()" not in gift:
        raise ValueError('SAFE_STOP_QA32_ADMIN_CANONICAL_GIFT_GRANT_DRIFT')
    if gift.count("DedaGiftRecipientPreview(")!=1:
        raise ValueError('SAFE_STOP_QA32_ADMIN_PUBLIC_PREVIEW_MISSING')
    s=s[:a]+gift+s[b:]
    return once(s,"import 'package:flutter/material.dart';\n",
                "import 'package:flutter/material.dart';\n"+IMPORT,'IMPORT')

def patch_preview(s):
    # Replace visual text only. This widget cannot originate or send a gift.
    old="final id = (profile['publicId'] ?? '').toString().trim().toUpperCase();"
    new=("final id = (profile['activeDisplayId'] ?? profile['publicId'] ?? '')"
         ".toString().trim().toUpperCase();")
    if new in s:
        return s
    return once(s,old,new,'PREVIEW_ALIAS')

if __name__=='__main__':
    raw_admin=ADMIN.read_text()
    raw_preview=PREVIEW.read_text()
    admin=patch_admin(raw_admin)
    preview=patch_preview(raw_preview)
    if admin==raw_admin and preview==raw_preview:
        raise SystemExit('SAFE_STOP_QA32_ALREADY_APPLIED')
    ADMIN.write_text(admin)
    PREVIEW.write_text(preview)
    print('PASS QA32 GM alias lookup uses ONLY verified read-only callable behind OFF default flags')
    print('PASS original canonical receiver publicId remains grantDiamondGift target')
    print('PASS public recipient confirmation shows trusted active display alias if returned')
    print('PASS no real gift sent, no wallet debit, no Firebase or Play deployment')
