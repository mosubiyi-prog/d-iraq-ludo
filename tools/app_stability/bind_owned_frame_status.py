"""Make a failed ownership read visible and explicitly retryable in the editor."""
from pathlib import Path


def bind_source(source):
    if 'DEDA_OWNED_FRAME_RECOVERY_STATUS_V1' in source:
        raise ValueError('owned inventory status already bound')
    start=source.index('class _DedaEditProfilePageState ')
    end=source.index('\nclass ',start+1)
    page=source[start:end]
    fields='  final Set<int> _serverVerifiedPaidStyles = <int>{};'
    load='''    try {
      final owned = await DedaOwner18FrameCheckout.verifiedOwnedFrameIds('''
    success='''      setState(() {
        for (var i = 6; i <= 18; i++) {'''
    failure='''    } catch (_) { /* Keep unpaid frames locked until server proof succeeds. */ }'''
    notice='''            const DedaUnifiedCurrencyStrip(),
            Expanded('''
    for anchor in [fields,load,success,failure,notice]:
        if page.count(anchor)!=1:raise ValueError('exact original owned inventory editor required')
    page=page.replace(fields,fields+'''
  // DEDA_OWNED_FRAME_RECOVERY_STATUS_V1
  bool _loadingOwnedFrames = false;
  bool _ownedFramesUnavailable = false;''',1)
    page=page.replace(load,'''    if (_loadingOwnedFrames) return;
    setState(() { _loadingOwnedFrames = true; _ownedFramesUnavailable = false; });
'''+load,1)
    page=page.replace(success,'''      setState(() {
        _ownedFramesUnavailable = false;
        for (var i = 6; i <= 18; i++) {''',1)
    page=page.replace(failure,'''    } catch (_) {
      // Keep previously verified ownership; a failed read is never a new
      // empty inventory and never triggers a purchase or a refund.
      if (mounted && DedaPreferences.phone == phone) {
        setState(() => _ownedFramesUnavailable = true);
      }
    } finally {
      // Status-only cleanup also releases Retry if the SDK session changed.
      // The shared page epoch guard still suppresses an expired account page.
      if (mounted && DedaPreferences.phone == phone) {
        setState(() => _loadingOwnedFrames = false);
      }
    }''',1)
    page=page.replace(notice,'''            const DedaUnifiedCurrencyStrip(),
            if (_loadingOwnedFrames)
              const LinearProgressIndicator(key: Key('deda_owned_frames_loading')),
            if (_ownedFramesUnavailable)
              Padding(
                key: const Key('deda_owned_frames_unavailable'),
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Row(children: [
                  Expanded(child: Text(dedaText(
                    'تعذّر تحميل مقتنياتك. أعد المحاولة.',
                    'Could not load your owned items. Try again.'))),
                  TextButton(
                    onPressed: _loadingOwnedFrames ? null : _loadOwnedFrames,
                    child: Text(dedaText('إعادة المحاولة', 'Retry')),
                  ),
                ]),
              ),
            Expanded(''',1)
    return source[:start]+page+source[end:]


def bind(output):
    path=Path(output)/'lib/main.dart'
    path.write_text(bind_source(path.read_text()))
