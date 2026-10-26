"""Opt-in actual native checkout binding; original fallback remains unchanged."""
from pathlib import Path
from bind_auth_runtime import body_range

PREFIX = "// DEDA_MIGRATED_FRAME_CHECKOUT_BOUND_V1\nimport 'deda_migrated_progress_firebase.dart';\n"
INJECTIONS = {
    '_buy': '''
    if (dedaMigratedProgressEnabled) {
      await DedaMigratedProgressBridge.buyFrame(original, frame);
      return;
    }
''',
    'verifiedPurchaseBalance': '''
    if (dedaMigratedProgressEnabled) {
      return DedaMigratedProgressBridge.purchaseBalance(originalId);
    }
''',
    'isOwned': '''
    if (dedaMigratedProgressEnabled) {
      _item(frameId);
      final data = await DedaOwner18Cosmetics.read(originalId);
      if (data['ownedFrames'] is List && (data['ownedFrames'] as List).contains(frameId)) return true;
      return DedaLabFrameSecureCheckout.isOwned(originalId: originalId, frameId: frameId);
    }
''',
}


def bind_source(source):
    if 'DEDA_MIGRATED_FRAME_CHECKOUT_BOUND_V1' in source:
        raise ValueError('migrated checkout already bound')
    edits = []
    for name, text in INJECTIONS.items():
        opening, _, _, _ = body_range(source, name)
        edits.append((opening+1, text))
    for offset, text in sorted(edits, reverse=True):
        source = source[:offset] + text + source[offset:]
    return PREFIX + source


def unbind_source(source):
    if not source.startswith(PREFIX):
        raise ValueError('exact migrated checkout header required')
    source = source[len(PREFIX):]
    for name, text in INJECTIONS.items():
        opening, closing, _, _ = body_range(source, name)
        if not source[opening+1:closing].startswith(text):
            raise ValueError('migrated checkout overlay changed')
        source = source[:opening+1] + source[opening+1+len(text):]
    return source


def bind(output):
    target = Path(output)/'lib/deda_owner18_frame_checkout.dart'
    target.write_text(bind_source(target.read_text()))
