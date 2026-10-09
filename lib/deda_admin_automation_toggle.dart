import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'deda_backend.dart';

/// General-manager control UI for the two future server automations.
/// This widget NEVER performs the automation on the handset. Until a trusted
/// deployed worker sets its separate readiness marker, ON is disabled.
/// The existing manual workflow always remains available.
class DedaAdminAutomationToggle extends StatefulWidget {
  const DedaAdminAutomationToggle({
    super.key,
    required this.isArabic,
    required this.kind,
  });

  final bool isArabic;
  /// Either place_auto_approval or pin_auto_recovery.
  final String kind;

  @override
  State<DedaAdminAutomationToggle> createState() =>
      _DedaAdminAutomationToggleState();
}

class _DedaAdminAutomationToggleState
    extends State<DedaAdminAutomationToggle> {
  bool _loading = true;
  bool _saving = false;
  bool _enabled = false;
  bool _backendReady = false;
  int _revision = 0;
  String? _error;

  String t(String ar, String en) => widget.isArabic ? ar : en;
  bool get _place => widget.kind == 'place_auto_approval';

  DocumentReference<Map<String, dynamic>> get _config =>
      FirebaseFirestore.instance
          .collection('deda_automation_settings').doc(widget.kind);

  DocumentReference<Map<String, dynamic>> get _readiness =>
      FirebaseFirestore.instance
          .collection('deda_automation_status').doc(widget.kind);

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final profile = await DedaBackend.currentAdminProfile();
      if (DedaBackend.normalizeAdminRole(profile['role']) !=
          'general_manager') {
        throw StateError('strict-general-manager-required');
      }
      final docs = await Future.wait([
        _config.get(const GetOptions(source: Source.server)),
        _readiness.get(const GetOptions(source: Source.server)),
      ]);
      if (!mounted) return;
      setState(() {
        final value = docs.first.data();
        final readiness = docs.last.data();
        _enabled = value?['enabled'] == true;
        _revision = (value?['revision'] as num?)?.toInt() ?? 0;
        _backendReady = readiness?['ready'] == true;
        _error = null;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = t('تعذر قراءة إعدادات الأتمتة بأمان.',
            'Could not securely load automation settings.');
        _loading = false;
      });
    }
  }

  Future<void> _setEnabled(bool next) async {
    if (_saving || !_backendReady || _loading) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return;
    setState(() => _saving = true);
    try {
      final firestore = FirebaseFirestore.instance;
      final ref = _config;
      await firestore.runTransaction((tx) async {
        final snapshots = await Future.wait([
          tx.get(ref),
          tx.get(_readiness),
        ]);
        if (snapshots.last.data()?['ready'] != true) {
          throw StateError('worker-not-deployed');
        }
        final old = snapshots.first.data();
        final revision = (old?['revision'] as num?)?.toInt() ?? 0;
        if (_revision != revision) throw StateError('setting-changed');
        final data = <String, dynamic>{
          'enabled': next,
          'enabledAt': next ? FieldValue.serverTimestamp() : null,
          'revision': revision + 1,
          'updatedAt': FieldValue.serverTimestamp(),
          'changedByUid': uid,
        };
        if (snapshots.first.exists) {
          tx.update(ref, data);
        } else {
          tx.set(ref, data);
        }
      });
      await _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(t('تم تحديث إعداد الأتمتة على الخادم.',
              'Automation setting updated on server.')),
        ));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(t('لم يتغير الإعداد. تحقق من الصلاحية والاتصال بالخادم.',
              'Setting unchanged. Check permission and server connection.')),
        ));
      }
      await _refresh();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _place
        ? t('الاعتماد التلقائي للطلبات الجديدة فقط',
            'Auto-approve NEW place requests only')
        : t('استرجاع الرمز تلقائياً بعد 10 ثوانٍ',
            'Auto-reissue PIN after 10 seconds');
    final help = _place
        ? t('الطلبات الجديدة المكتملة تُنشر تلقائياً بعد 30 ثانية؛ القديمة تبقى يدوية.',
            'New complete requests publish after 30 seconds; old ones stay manual.')
        : t('يصل الرمز بعد 10 ثوانٍ لجهاز مسجّل سابقاً، دون موافقة موظف.',
            '10-second self-recovery for previously trusted devices, no staff step.');
    final blocked = !_backendReady
        ? t('خدمة التشغيل التلقائي لم تتفعّل بعد؛ النظام اليدوي مستمر.',
            'Server worker not active yet — manual workflow remains.')
        : t(_enabled ? 'مفعّل للطلبات الجديدة' : 'مطفأ — مراجعة يدوية',
            _enabled ? 'ON for new requests' : 'OFF — manual review');

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 12, 6),
      child: Card(
        color: const Color(0xFFEAF4EA),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF9FBDA3))),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: _loading
              ? const Center(child: Padding(padding: EdgeInsets.all(12),
                  child: CircularProgressIndicator()))
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: Text(title,
                        style: const TextStyle(fontWeight: FontWeight.w800,
                          fontSize: 15)),
                      subtitle: Text(help,
                        style: const TextStyle(fontSize: 12.5)),
                      value: _enabled,
                      onChanged: _saving || !_backendReady || _error != null
                          ? null : _setEnabled,
                    ),
                    Text(_error ?? blocked,
                      textAlign: TextAlign.start,
                      style: TextStyle(fontSize: 12,
                        color: _error == null
                            ? const Color(0xFF3B6043)
                            : const Color(0xFF9C3324))),
                    if (_error != null)
                      Align(alignment: AlignmentDirectional.centerEnd,
                        child: TextButton.icon(
                          onPressed: _refresh,
                          icon: const Icon(Icons.refresh, size: 18),
                          label: Text(t('إعادة المحاولة', 'Retry')),
                        )),
                  ],
                ),
        ),
      ),
    );
  }
}
