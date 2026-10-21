/// Pure security policy for current GM's OWN original DEDA identifier.
///
/// The route from deda_share_ids MUST have ownerUid of the logged-in user.
/// A legacy users document need not contain 'sharePersonalId'; if it does,
/// its stored ID MUST match. Account/session account keys must match.
/// The locally computed ID is only a requested lookup key, NOT authority.
/// Never writes an ID, diamonds, wallet, grant, owned item or Firebase rule.
class DedaQa32ManagerOriginalOwnerProof {
  const DedaQa32ManagerOriginalOwnerProof._();

  static final RegExp _original = RegExp(r'^@DEDA-[A-Z0-9]{6}$');

  static bool authentic({
    required String expectedOriginal,
    required String authUid,
    required Map<String, dynamic> account,
    required Map<String, dynamic> session,
    required Map<String, dynamic> route,
  }) {
    if (!_original.hasMatch(expectedOriginal) || authUid.trim().isEmpty) {
      return false;
    }
    final accountKey = account['accountKey'];
    if (accountKey is! String ||
        accountKey.trim().isEmpty ||
        accountKey != session['accountKey']) {
      return false;
    }
    final claimedOriginal = account['sharePersonalId'];
    if (claimedOriginal != null &&
        (claimedOriginal is! String || claimedOriginal != expectedOriginal)) {
      return false;
    }
    if (route['publicId'] != expectedOriginal ||
        route['kind'] != 'personal' ||
        route['active'] != true ||
        route['ownerUid'] != authUid) {
      return false;
    }
    return true;
  }
}
