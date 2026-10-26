import 'package:flutter/material.dart';
import 'deda_private_data_bridge.dart';
import 'deda_private_data_sync.dart';
import 'deda_section_state.dart';
import 'main.dart' show dedaText;

class DedaPrivateDataPage extends StatefulWidget {
  const DedaPrivateDataPage({super.key});
  @override
  State<DedaPrivateDataPage> createState() => _DedaPrivateDataPageState();
}
class _DedaPrivateDataPageState extends State<DedaPrivateDataPage>
    with DedaSectionState<DedaPrivateDataPage> {
  bool _busy = false;
  String? _message;
  Future<bool> _confirm(bool restore) async => await showDialog<bool>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: Text(dedaText(restore ? 'استرجاع بياناتي' : 'حفظ بياناتي للحساب',
        restore ? 'Restore my saved data' : 'Back up my data')),
      content: Text(dedaText(restore
        ? 'استرجاع النسخة المحفوظة لهذا الحساب؟ سنحتفظ بالبيانات الحالية قبل استبدالها.'
        : 'هل المفضلة والأماكن ومسودة التواصل المحفوظة على هذا الجهاز تخصك وتريد ربطها بحسابك؟',
        restore ? 'Restore this account’s saved copy? Your existing data will be preserved before replacement.'
        : 'Do the favorites, places and contact draft on this device belong to you, and should they be linked to your account?')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialog, false), child: Text(dedaText('إلغاء', 'Cancel'))),
        FilledButton(onPressed: () => Navigator.pop(dialog, true), child: Text(dedaText('تأكيد', 'Confirm'))),
      ],
    ),
  ) ?? false;
  Future<void> _run(bool restore) => dedaRunSectionVoid(() async {
    if (_busy || !await _confirm(restore) || !dedaSectionCurrent) return;
    setState(() { _busy = true; _message = null; });
    try {
      var result = restore ? await DedaPrivateDataBridge.restoreConfirmed()
          : await DedaPrivateDataBridge.backupConfirmed();
      if (!dedaSectionCurrent) return;
      if (restore && result.status == DedaPrivateDataStatus.conflict) {
        final replace = await _confirm(true);
        if (!dedaSectionCurrent || !replace) return;
        result = await DedaPrivateDataBridge.restoreConfirmed(discardPending: true);
      }
      if (!dedaSectionCurrent) return;
      setState(() => _message = switch (result.status) {
        DedaPrivateDataStatus.saved => dedaText(restore ? 'تم استرجاع بيانات الحساب.' : 'تم حفظ بياناتك للحساب.',
          restore ? 'Your account data was restored.' : 'Your account data was saved.'),
        DedaPrivateDataStatus.pending => dedaText('بقيت بياناتك محفوظة على الجهاز. أعد الحفظ عند توفر الاتصال.',
          'Your data remains on this device. Save again when connected.'),
        DedaPrivateDataStatus.conflict => dedaText('توجد نسخة أحدث للحساب. لم نستبدلها ببيانات هذا الجهاز.',
          'A newer account copy exists. This device has not replaced it.'),
        DedaPrivateDataStatus.absent => dedaText('لا توجد نسخة محفوظة لهذا الحساب بعد. بقيت بيانات الجهاز كما هي.',
          'This account has no saved copy yet. Device data was retained.'),
      });
    } catch (_) {
      if (dedaSectionCurrent) setState(() => _message = dedaText(
        'تعذّر إكمال العملية. بقيت بياناتك محفوظة؛ تحقق من الاتصال وأعد المحاولة.',
        'Could not finish. Your data was retained; check your connection and retry.'));
    } finally { if (dedaSectionCurrent) setState(() => _busy = false); }
  });
  @override
  Widget build(BuildContext context) {
    if (!dedaSectionCurrent) return dedaSectionExpiredView();
    return Scaffold(
      appBar: AppBar(title: Text(dedaText('بياناتي المحفوظة', 'My saved data'))),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Text(dedaText('المفضلة، الأماكن الأخيرة والشخصية، نص مسودة التواصل، وسجل الاختبار المروري.',
          'Favorites, recent and personal places, contact draft text and traffic quiz history.')),
        const SizedBox(height: 12),
        Text(dedaText('صور المرفقات تبقى على الجهاز الذي التُقطت عليه.',
          'Attached image files remain on the device where they were selected.')),
        const SizedBox(height: 20),
        FilledButton.icon(key: const Key('deda_private_data_backup'),
          onPressed: _busy || !dedaPrivateDataEnabled ? null : () => _run(false),
          icon: const Icon(Icons.cloud_upload_outlined), label: Text(dedaText('حفظ للحساب', 'Save to account'))),
        OutlinedButton.icon(key: const Key('deda_private_data_restore'),
          onPressed: _busy || !dedaPrivateDataEnabled ? null : () => _run(true),
          icon: const Icon(Icons.cloud_download_outlined), label: Text(dedaText('استرجاع بياناتي', 'Restore my data'))),
        if (_busy) const LinearProgressIndicator(),
        if (_message != null) Padding(padding: const EdgeInsets.only(top: 16), child: Text(_message!)),
      ]),
    );
  }
}
