"""100411 isolated integration after VERIFIED 100410; never edits baseline.

Adds an exact verified friend ID copy action and routes pasted premium ID
through the existing signed-in Spark alias -> original resolver. No Firebase
deploy, no wallet writes, no score keys changed. A missing public normal-ID
projection must NOT silently become an unverified retired ID.
"""
import argparse
import hashlib
import json
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]

def digest(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()

def once(s, old, new, label):
    count = s.count(old)
    if count != 1:
        raise ValueError(f"100411 safety anchor: {label} count={count}")
    return s.replace(old, new, 1)

def call_end(source, start):
    depth=0
    for i in range(start,len(source)):
        if source[i] == '(':
            depth+=1
        elif source[i] == ')':
            depth-=1
            if depth == 0:
                return i+1
    raise ValueError("100411 Dart call unclosed")

def bind(destination):
    dest=Path(destination).resolve()
    if dest == ROOT or ROOT in dest.parents:
        raise ValueError("100411 never edit repository reference")
    manifest=dest/"internal-build-inputs.json"
    meta=json.loads(manifest.read_text())
    proof=meta.get("weekly100410UnifiedActiveId",{})
    if meta.get("versionCode") != 100410 or not (
        proof.get("locationSessionGuardPreAndPostGps") and
        proof.get("oneUidScopedOwnerStore") and
        proof.get("originalKeysNeverReplaced") and
        proof.get("noXpDiamondOrRewardWrites")
    ):
        raise ValueError("100411: authenticated 100410 baseline required")
    for name,h in meta["sourceHashes"].items():
        if not (dest/name).is_file() or digest(dest/name)!=h:
            raise ValueError("100411: source hash drift "+name)

    filename="lib/deda_friend_id_copy_100411.dart"
    shutil.copy2(ROOT/filename,dest/filename)

    p=dest/"lib/main.dart"
    text=p.read_text()
    text=once(text,
      "import 'deda_unified_active_id_100410.dart';",
      "import 'deda_unified_active_id_100410.dart';\n"
      "import 'deda_friend_id_copy_100411.dart';\n"
      "import 'deda_qa32_public_recipient_resolver.dart';",
      "friend clipboard and verified recipient imports")

    # The card's outer InkWell continues to open the friend's public profile.
    # Only the narrow visible ID section gains a separate copy interaction.
    first=text.index("class _DedaFriendCompactCard")
    last=text.index("class ",first+len("class _DedaFriendCompactCard"))
    card=text[first:last]
    key="DedaStage50VerifiedFriendInkBadge(\n"
    anchor=card.index("originalId: dedaId,")
    begin=card.rfind(key,0,anchor)
    if begin<0 or anchor-begin>140 or card.count("originalId: dedaId,")!=1:
        raise ValueError("100411 friend list exact ID badge missing")
    finish=call_end(card,begin)
    original=card[begin:finish]
    if "fallback:" not in original:
        raise ValueError("100411 friend badge missing original fallback")
    replaced="""DedaUnifiedActiveIdBuilder100410(
                            originalId: dedaId,
                            builder: (context, confirmed) =>
                                DedaFriendIdCopy100411(
                                  verifiedDisplayId: confirmed,
                                  child: """+original+""",
                                ),
                          )"""
    card=card[:begin]+replaced+card[finish:]
    text=text[:first]+card+text[last:]

    share_begin=text.index("class DedaShareLocationPage")
    share_end=text.index("class DedaReceived",share_begin)
    share=text[share_begin:share_end]
    send_begin=share.index("Future<void> _send() async")
    send_end=share.index("  Widget _idCard(",send_begin)
    send=share[send_begin:send_end]
    send=once(send,
        "if (!DedaBackend.isValidPersonalShareId(recipient)) {",
        "if (DedaFriendIdCopy100411.exactCopyValue(recipient) == null) {",
        "accept structurally valid copyable premium input")

    # The original busy flag is set before any network resolution, and the
    # entire route proof is inside the existing try/finally cleanup path.
    busy=send.index("setState(() => _sending = true);")
    try_at=send.index("try {",busy)
    at=try_at+len("try {")
    guard="""
      // Prefer the existing canonical, active personal share route; otherwise
      // resolve the pasted PREMIUM alias against the CURRENT server projection.
      // Never change stable friendship/share keys or accept an old alias.
      String canonicalRecipient = recipient;
      final direct = DedaBackend.isValidPersonalShareId(recipient)
          ? await DedaSectionOperationContext.wait(
              () => DedaBackend.locationShareIdInfo(recipient))
          : null;
      if (direct == null || direct['kind'] != 'personal') {
        final resolved = await DedaSectionOperationContext.wait(
            () => DedaQa32PublicRecipientResolver.resolveActiveAlias(
                recipient));
        if (resolved == null ||
            !DedaBackend.isValidPersonalShareId(resolved)) {
          throw StateError('recipient-share-id-not-found');
        }
        canonicalRecipient = resolved;
      }
      if (!_locationAccountCurrent() || !DedaPreferences.isLoggedIn ||
          DedaPreferences.phone != _ownerPhoneAtOpen) return;
      DedaAuthRuntime.checkSnapshot(requestPrincipal);
      if (canonicalRecipient == personalId) {
        throw StateError('share-self-recipient');
      }
"""
    send=send[:at]+guard+send[at:]
    send=once(send,"recipientPublicId: recipient,",
                   "recipientPublicId: canonicalRecipient,",
                   "server-authoritative canonical routing for location")
    share=share[:send_begin]+send+share[send_end:]
    text=text[:share_begin]+share+text[share_end:]
    p.write_text(text)

    for name in (filename,"lib/main.dart"):
        meta["sourceHashes"][name]=digest(dest/name)
    meta["versionCode"]=100411
    meta["weekly100411FriendCopy"]={
       "friendCardOpenUnchanged": True,
       "onlyVerifiedDisplayedIdCopyable": True,
       "clipboardNoCommasOrBidiMarks": True,
       "originalIdStillRoutingOnly": True,
       "premiumAliasServerResolvedForLocationRecipient": True,
       "unknownPublicNormalNeedsServerAuthoritativeBackfill": True,
       "realFirestoreDeployPerformed": False,
       "walletPointsGrantsUnchanged": True,
       "noPlay": True
    }
    manifest.write_text(json.dumps(meta,ensure_ascii=False,indent=2)+"\n")
    print("100411_FRIEND_ID_COPY_AND_SERVER_VERIFIED_SHARE_ROUTE_BOUND")

if __name__=="__main__":
    ap=argparse.ArgumentParser()
    ap.add_argument("workspace",type=Path)
    bind(ap.parse_args().workspace)
