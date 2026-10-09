/// DEDA profile presentation only.
///
/// Normal rewarded-ad diamonds (including separately gifted diamonds)
/// live in the ordinary DEDA Diamonds Wallet notifier.
/// An authorized general manager may ALSO have a protected personal
/// test wallet. The profile must DISPLAY THE SUM rather than hiding
/// earned-ad rewards when a manager's personal wallet is present.
///
/// The function does not mint, move, spend or merge underlying wallets.
/// The separate administrative gift wallet is NOT part of either input.
int dedaProfileVisibleDiamonds({
  required int ordinaryEarnedAndGifted,
  required bool hasGeneralManagerPersonalWallet,
  required int generalManagerPersonal,
}) {
  final ordinary = ordinaryEarnedAndGifted < 0 ? 0 : ordinaryEarnedAndGifted;
  final manager =
      hasGeneralManagerPersonalWallet && generalManagerPersonal > 0
          ? generalManagerPersonal
          : 0;
  return ordinary + manager;
}
