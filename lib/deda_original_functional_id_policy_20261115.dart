/// DEDA 2026-11-15: approved original-ID-first / cosmetic-premium-only mode.
///
/// This class is copied ONLY into the isolated Step3 assembled APK source.
/// It never changes immutable Firebase records or historical ID grants.
/// Public labels, copies and share headers use the original DEDA identifier.
/// Previously used premium aliases remain server-side legacy records until
/// separately authorized cleanup; DO NOT delete routes on the client.
class DedaOriginalFunctionalIdPolicy20261115 {
  DedaOriginalFunctionalIdPolicy20261115._();
  static const bool originalOnly = true;
}
