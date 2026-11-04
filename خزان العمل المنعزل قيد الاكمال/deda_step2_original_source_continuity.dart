import 'dart:math';

/// DEDA isolated recovery work vault — SOURCE ONLY, NO PRODUCTION WIRING.
///
/// One immutable historical capture intent must retain the SAME captureId
/// across retries. The existing DedaProgressBackupCoordinator owns its durable
/// pending journal and idempotent upload; this helper only creates the initial
/// unpredictable identifier when no prior journal exists.
///
/// Never generate a replacement capture ID merely because a network response
/// was lost. Never use a capture ID as proof of account ownership.
class DedaStep2OriginalSourceContinuity {
  const DedaStep2OriginalSourceContinuity._();

  static String newCaptureId() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    final value = bytes.map((byte) =>
        byte.toRadixString(16).padLeft(2, '0')).join();

    // Exactly 64 lowercase hex chars, within the existing archive schema's
    // permitted 20..80 [A-Za-z0-9_-] capture-ID length.
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(value)) {
      throw StateError('invalid-original-evidence-capture-id');
    }
    return value;
  }
}
