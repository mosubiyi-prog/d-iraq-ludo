#!/usr/bin/env python3
"""Stage read-only premium ID aliases in DEDA social friend search, DEFAULT OFF.

Never route live location shares through a cosmetic active ID. Existing
friends, messages and old IDs stay bound to their original UID/public ID.
No original DEDA business logic or Firestore rules change in the repository.
"""
from pathlib import Path
import re

MAIN = Path("lib/deda_social_service.dart")
MARKER = "// DEDA_INTAKADHA_POINT16_READONLY_SOCIAL_ALIAS_FALLBACK_DEFAULT_OFF"
IMPORT = "import 'package:firebase_auth/firebase_auth.dart';\n"
NEW_IMPORT = "import 'package:cloud_functions/cloud_functions.dart';\n"
LOOKS_OLD = "RegExp(r'^@DEDA-[A-Z0-9]{5,12}$').hasMatch(normalizePublicId(value));"
LOOKS_NEW = "RegExp(r'^@DEDA-[A-Z0-9]{4,12}$').hasMatch(normalizePublicId(value));"
OLD_LOOKUP = """    final publicId = normalizePublicId(raw);
    if (!looksLikePersonalId(publicId)) return null;

    final directory = await _db.collection('deda_share_ids').doc(publicId).get();
    final directoryData = directory.data();
    if (!directory.exists ||
        directoryData == null ||
        directoryData['active'] != true ||
        directoryData['kind'] != 'personal') {
      return null;
    }"""
NEW_LOOKUP = """    final requestedId = normalizePublicId(raw);
    if (!looksLikePersonalId(requestedId)) return null;

    var publicId = requestedId;
    var directory = await _db.collection('deda_share_ids').doc(publicId).get();
    var directoryData = directory.data();
    // Original registered ID always takes priority; do not override existing
    // location/share records. Server fallback returns ONLY the old canonical ID.
    if ((!directory.exists || directoryData == null ||
         directoryData['active'] != true ||
         directoryData['kind'] != 'personal') &&
        DedaPoint16SocialAliasCompat.enabled) {
      final canonical = await DedaPoint16SocialAliasCompat.tryResolve(requestedId);
      if (canonical != null && canonical != requestedId) {
        publicId = canonical;
        directory = await _db.collection('deda_share_ids').doc(publicId).get();
        directoryData = directory.data();
      }
    }
    if (!directory.exists ||
        directoryData == null ||
        directoryData['active'] != true ||
        directoryData['kind'] != 'personal') {
      return null;
    }"""
ALIAS = r'''// DEDA_INTAKADHA_POINT16_READONLY_SOCIAL_ALIAS_FALLBACK_DEFAULT_OFF
// Server route is NEVER a location-sharing authorization.
// The original personal DEDA ID remains the persisted friend/profile key.
class DedaPoint16SocialAliasCompat {
  static const bool enabled = bool.fromEnvironment(
    'DEDA_PREMIUM_ALIAS_ROUTING_LIVE',
    defaultValue: false,
  );

  static Future<String?> tryResolve(String input) async {
    if (!enabled) return null;
    final requester = FirebaseAuth.instance.currentUser?.uid;
    if (requester == null || requester.isEmpty) return null;
    if (!RegExp(r'^@DEDA-[A-Z0-9]{4,12}$').hasMatch(input)) return null;
    try {
      final value = await FirebaseFunctions.instance
          .httpsCallable('dedaPremiumResolveAlias')
          .call<Map<String, dynamic>>(<String, dynamic>{
        'identifier': input,
      });
      if (FirebaseAuth.instance.currentUser?.uid != requester) return null;
      final data = Map<String, dynamic>.from(value.data);
      final original = data['originalId'];
      if (original is! String ||
          !RegExp(r'^@DEDA-[A-Z0-9]{6}$').hasMatch(original)) return null;
      return original;
    } catch (_) {
      // Offline, undeployed or unverified => old ID lookup stays unchanged.
      return null;
    }
  }
}

'''

def exact_or_whitespace_only(source: str, target: str, label: str) -> str:
    if source.count(target) == 1:
        return target
    # The full app reconstruction formats Dart in earlier historical stages.
    # Accept only identical Dart tokens with whitespace changed; never alter
    # imports, search permissions, friend ownership or route semantics.
    compact = lambda x: re.sub(r"\s+", "", x)
    view, wanted = compact(source), compact(target)
    if view.count(wanted) != 1:
        raise ValueError(
            "SAFE_STOP: social " + label + " has semantic differences, "
            "normalized-count=" + str(view.count(wanted))
        )
    positions = [i for i, c in enumerate(source) if not c.isspace()]
    start = view.index(wanted)
    actual = source[positions[start]:positions[start + len(wanted) - 1] + 1]
    if compact(actual) != wanted or source.count(actual) != 1:
        raise ValueError("SAFE_STOP: social " + label + " ambiguous")
    return actual

def apply(source: str) -> str:
    if MARKER in source:
        if source.count(MARKER) != 1 or \
                source.count(NEW_LOOKUP) != 1 or source.count(LOOKS_NEW) != 1:
            raise ValueError("SAFE_STOP: modified partially enabled alias route")
        return source
    if NEW_IMPORT in source:
        raise ValueError("SAFE_STOP: alias import already present without marker")
    anchor = exact_or_whitespace_only(source, IMPORT, "import")
    reg = exact_or_whitespace_only(source, LOOKS_OLD, "original-ID-regex")
    lookup = exact_or_whitespace_only(source, OLD_LOOKUP, "original-friend-query")
    profile = exact_or_whitespace_only(
        source, "class DedaSocialProfile {", "profile-class")
    updated = source.replace(anchor, anchor + NEW_IMPORT, 1)
    updated = updated.replace(reg, LOOKS_NEW, 1)
    updated = updated.replace(lookup, NEW_LOOKUP, 1)
    updated = updated.replace(profile, ALIAS + profile, 1)
    restored = (updated.replace(ALIAS, "", 1)
        .replace(NEW_LOOKUP, lookup, 1)
        .replace(LOOKS_NEW, reg, 1)
        .replace(anchor + NEW_IMPORT, anchor, 1))
    if restored != source or "defaultValue: false" not in ALIAS:
        raise ValueError("SAFE_STOP: social alias patch touched unrelated logic")
    return updated

if __name__ == "__main__":
    if not MAIN.is_file(): raise SystemExit("SAFE_STOP: checked-in social source absent")
    original = MAIN.read_text(encoding="utf8")
    try: checked = apply(original)
    except ValueError as e: raise SystemExit(str(e))
    if original != checked: MAIN.write_text(checked, encoding="utf8")
    print("PASS: old friend IDs continue by default; 4-12-char premium social aliases staged only")
    print("PASS: no location access, no direct registry reads, no deployment")
