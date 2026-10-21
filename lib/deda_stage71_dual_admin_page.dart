import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'deda_backend.dart';
import 'deda_stage71_free_manager_200_service.dart';
import 'deda_stage71_free_owned_use_profile.dart';
import 'deda_qa32_manager_original_owner_proof.dart';
import 'main.dart' show DedaPremiumIdCard, DedaPremiumIdCardColor,
    DedaPoint10CandidateGroup002, DedaPreferences;

/// Original DEDA luxury artwork + exactly 2 equal-width vertical catalog
/// columns, 100 immutable original GM IDs each. No prices or color pickers.
class DedaStage71DualAdminPage extends StatefulWidget {
  final bool isArabic;
  const DedaStage71DualAdminPage({super.key, required this.isArabic});

  @override
  State<DedaStage71DualAdminPage> createState() =>
      _DedaStage71DualAdminPageState();
}

class _DedaStage71DualAdminPageState
    extends State<DedaStage71DualAdminPage> {
  static const navy = Color(0xFF092B40);
  static const turquoise = Color(0xFF1ED0C4);
  List<DedaStage71AdminId>? _rows;
  bool _loading = false;
  String? _error;
  String? _ownerUid;
  int _generation = 0;
  bool _committing = false;
  bool _importing = false;
  int _importProgress = 0;

  String _text(String ar, String en) => widget.isArabic ? ar : en;
  DedaPremiumIdCardColor _foil(DedaStage71AdminId row) {
    return DedaPremiumIdCardColor.values.firstWhere(
      (c) => c.name == row.baseColor,
    );
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _generation++;
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (_loading && uid == _ownerUid) return;
    setState(() {
      _loading = true;
      _rows = null;
      _error = null;
      _ownerUid = uid;
    });
    try {
      final rows = await DedaStage71Admin200.read();
      if (!mounted || generation != _generation ||
          FirebaseAuth.instance.currentUser?.uid != uid) return;
      setState(() => _rows = rows);
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _error = _text(
          'توقّف آمن: قائمة الـ200 الأصلية غير متاحة أو غير مكتملة. لم يتغير أي معرّف.',
          'Safe stop: the original 200 IDs are not authenticated or complete.',
        ));
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _importFromPrivateBackup() async {
    if (_importing || _committing || !DedaStage71Admin200.enabled) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final answer = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_text('تفعيل مجموعتي المعرّفات',
            'Activate both identifier groups')),
        content: Text(_text(
          'انسخ ملف DEDA_100_IDENTIFIERS_BACKUP.json الأصلي كاملًا. '
          'سأستورد الـ100 الحصرية من النسخة الخاصة، '
          'وأضيف 100 المجموعة الثانية من التطبيق. '
          'لا توجد أسعار أو ماسات، ولا يمكن إعادة تعيين أي معرّف ممنوح.',
          'Copy the complete original private 100 JSON backup. '
          'The app imports those plus the 100 former-sale identifiers. '
          'No diamonds and no reassignment of gifted IDs.',
        )),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(_text('إلغاء', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_text('استيراد من النسخة المنسوخة', 'Import clipboard')),
          ),
        ],
      ),
    );
    if (answer != true || !mounted ||
        FirebaseAuth.instance.currentUser?.uid != uid) return;
    setState(() { _importing=true; _importProgress=0; });
    try {
      final clipboard=await Clipboard.getData(Clipboard.kTextPlain);
      final text=clipboard?.text?.trim() ?? '';
      if (text.isEmpty) throw StateError('missing-original100-clipboard');
      await DedaStage71Admin200.importOwnerTwoGroups(
        ownerBackupJson: text,
        formerlySaleGroup002: DedaPoint10CandidateGroup002.identifiers,
        progress:(current, total) {
          if (mounted && FirebaseAuth.instance.currentUser?.uid==uid) {
            setState(()=>_importProgress=current);
          }
        },
      );
      await _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_text('تم تأكيد تسجيل الـ200 معرّف بأمان.',
          'All 200 IDs confirmed on the server.')),
      ));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_text('الاستيراد غير مكتمل؛ النسخة الأصلية محفوظة. '
            'أعد المحاولة بنفس الملف ولا تغيّر المعرفات.',
            'Import not complete. Retry with the same private backup.')),
      ));
    } finally {
      if (mounted) setState(()=>_importing=false);
    }
  }

  Future<String?> _recipient() async {
    final controller = TextEditingController();
    try {
      return await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(_text('المعرّف الأصلي للمستلم', 'Recipient original ID')),
          content: TextField(
            controller: controller,
            textCapitalization: TextCapitalization.characters,
            textDirection: TextDirection.ltr,
            maxLength: 12,
            decoration: const InputDecoration(hintText: '@DEDA-XXXXXX'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(_text('إلغاء', 'Cancel')),
            ),
            FilledButton(
              onPressed: () {
                final id = controller.text.trim().toUpperCase();
                if (RegExp(r'^@DEDA-[A-Z0-9]{6}$').hasMatch(id)) {
                  Navigator.pop(ctx, id);
                }
              },
              child: Text(_text('التالي', 'Next')),
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  Future<void> _assign(DedaStage71AdminId row,
      {required bool gift}) async {
    if (_committing || !row.available ||
        _rows == null || _ownerUid == null) return;
    String? target;
    if (gift) {
      target = await _recipient();
    } else {
      // QA32: fail visibly when the manager's original account isn't verified.
      // Never use a locally typed phone/name to assign a reserved identifier.
      try {
        final current = FirebaseAuth.instance.currentUser;
        if (current == null) throw StateError('manager-not-authenticated');
        final profile = await DedaBackend.currentAdminProfile(forceRefresh: true);
        if (profile == null ||
            DedaBackend.normalizeAdminRole(profile['role']) != 'general_manager' ||
            DedaBackend.normalizeAdminStatus(profile) != 'active') {
          throw StateError('manager-role-unverified');
        }
        final db = FirebaseFirestore.instance;
        final docs = await Future.wait([
          db.collection('users').doc(current.uid)
              .get(const GetOptions(source: Source.server)),
          db.collection('deda_sessions').doc(current.uid)
              .get(const GetOptions(source: Source.server)),
        ]);
        if (FirebaseAuth.instance.currentUser?.uid != current.uid) {
          throw StateError('session-changed');
        }
        final account = docs[0].data() ?? {};
        final session = docs[1].data() ?? {};
        // DEDA_QA32_MANAGER_SELF_USE_CANONICAL_ROUTE_OWNER_PROOF
        // Legacy accounts may have no sharePersonalId field. Verify the
        // server original route owner UID plus account/session accountKey.
        final originalId = DedaBackend.personalShareIdForPhone(
          DedaPreferences.phone,
        ).trim();
        if (!RegExp(r'^@DEDA-[A-Z0-9]{6}$').hasMatch(originalId)) {
          throw StateError('manager-original-id-invalid');
        }
        final routeSnap = await db.collection('deda_share_ids')
            .doc(originalId).get(const GetOptions(source: Source.server));
        if (!routeSnap.exists ||
            FirebaseAuth.instance.currentUser?.uid != current.uid ||
            !DedaQa32ManagerOriginalOwnerProof.authentic(
              expectedOriginal: originalId,
              authUid: current.uid,
              account: account,
              session: session,
              route: routeSnap.data() ?? <String, dynamic>{},
            )) {
          throw StateError('manager-original-id-unverified');
        }
        target = originalId;
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(_text(
              'تعذّر تأكيد حساب المدير من الخادم. لم يتغير أي معرّف؛ افحص الجلسة.',
              'Manager account verification failed; no identifier changed.',
            )),
          ));
        }
        return;
      }
    }
    if (!mounted || target == null ||
        !RegExp(r'^@DEDA-[A-Z0-9]{6}$').hasMatch(target)) return;
    final uid = _ownerUid;
    if (FirebaseAuth.instance.currentUser?.uid != uid) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_text('تأكيد المعرف المجاني', 'Confirm free identifier')),
        content: Text(row.identifier + '\n' +
            (gift ? _text('منح إلى: ', 'Gift to: ') : _text(
              'استخدام لنفسي: ', 'Use myself: ')) + target! +
            '\n' + _text(
              'اللون الأصلي ثابت. المعرف لا يمكن منحه مرتين، ولا توجد ماسات.',
              'Original color fixed, no double grants and no diamonds.',
            )),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(_text('إلغاء', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_text('تأكيد', 'Confirm')),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true || _committing ||
        FirebaseAuth.instance.currentUser?.uid != uid) return;
    setState(() => _committing = true);
    try {
      await DedaStage71Admin200.assign(
        row: row, recipientOriginalId: target, selfUse: !gift,
      );
      // A manager self-use must also mark their newly owned ID as active.
      // Once-only ownership remains valid even if the separate active
      // display update loses the network response.
      var activationConfirmed = gift;
      if (!gift) {
        try {
          await DedaStage71OwnedIdentifierService.use(
            target, row.identifier,
          );
          activationConfirmed = true;
        } catch (_) {
          activationConfirmed = false;
        }
      }
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(activationConfirmed
              ? _text('تم تأكيد الاستخدام أو المنح وحفظ الملكية',
                  'Grant and ownership confirmed')
              : _text('تم تثبيت الملكية. افتح معرّفاتي واضغط استخدام لتفعيله.',
                  'Ownership confirmed. Activate it in My IDs.')),
        ));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_text(
            'تعذّر تثبيت المنح. أعد تحديث القائمة للتحقق من النتيجة.',
            'Grant not confirmed. Refresh before retrying.',
          )),
        ));
      }
    } finally {
      if (mounted) setState(() => _committing = false);
    }
  }

  void _history() {
    final rows = (_rows ?? []).where((x) => !x.available).toList()
      ..sort((a, b) => b.grantedAt!.compareTo(a.grantedAt!));
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(ctx).height * .65,
          child: Column(children: [
            Text(_text('📜 سجل المنح والاستخدام', 'Grant/use history'),
                style: Theme.of(ctx).textTheme.titleMedium),
            Expanded(child: rows.isEmpty
                ? Center(child: Text(_text(
                    'لا توجد عمليات موثقة.', 'No verified history.')))
                : ListView.builder(
                    itemCount: rows.length,
                    itemBuilder: (_, i) {
                      final r = rows[i];
                      return ListTile(
                        title: Text(r.identifier,
                            textDirection: TextDirection.ltr),
                        subtitle: Text(
                          '${r.group} • ${r.recipientOriginalId} • ${r.grantedAt!.toUtc().toIso8601String()}',
                        ),
                        trailing: Icon(r.status == 'gifted'
                          ? Icons.card_giftcard : Icons.person_outline),
                      );
                    },
                  )),
          ]),
        ),
      ),
    );
  }

  Widget _item(DedaStage71AdminId row) {
    return Card(
      key: ValueKey<String>('deda_stage71_item_${row.identifier}'),
      margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('#${row.sequence.toString().padLeft(3, '0')}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            DedaPremiumIdCard(
              identifier: row.identifier,
              color: _foil(row),
              height: 50,
            ),
            const SizedBox(height: 4),
            if (row.available) ...[
              SizedBox(height: 30, child: OutlinedButton(
                onPressed: _committing ? null : () => _assign(row, gift: false),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 1),
                ),
                child: Text(_text('استخدام', 'Use'),
                    style: const TextStyle(fontSize: 11)),
              )),
              const SizedBox(height: 3),
              SizedBox(height: 30, child: FilledButton(
                onPressed: _committing ? null : () => _assign(row, gift: true),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 1),
                ),
                child: Text(_text('منح', 'Gift'),
                    style: const TextStyle(fontSize: 11)),
              )),
            ] else ...[
              Text(row.status == 'gifted'
                  ? _text('ممنوح', 'Gifted')
                  : _text('مستخدم', 'In use'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11)),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(row.recipientOriginalId ?? '',
                  textDirection: TextDirection.ltr),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _column(String group) {
    final rows = _rows!.where((r) => r.group == group).toList();
    final title = group == '001'
      ? _text('الـ100 الأصلية', 'Original 100')
      : _text('الـ100 الإضافية', 'Second 100');
    return Expanded(
      child: Column(children: [
        Container(
          key: Key('deda_stage71_group_${group}_header'),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 7),
          color: navy,
          child: Text(title, textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white,
              fontSize: 12, fontWeight: FontWeight.bold)),
        ),
        Expanded(
          child: ListView.builder(
            key: Key('deda_stage71_group_${group}_vertical'),
            itemCount: rows.length,
            itemBuilder: (_, i) => _item(rows[i]),
          ),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFE7F2F3),
    appBar: AppBar(
      backgroundColor: navy, foregroundColor: Colors.white,
      title: Text(_text('إدارة الـ200 معرّف', 'Manage 200 IDs')),
      actions: [
        IconButton(
          key: const Key('deda_stage71_private_two_groups_import'),
          icon: const Icon(Icons.file_upload_outlined),
          onPressed: _importing || _loading ||
                  !DedaStage71Admin200.enabled ? null : _importFromPrivateBackup,
          tooltip: _text('استيراد الـ200 من النسخة الخاصة',
              'Import original private 200'),
        ),
        IconButton(icon: const Icon(Icons.refresh),
          onPressed: _loading || _importing ? null : _load),
      ],
    ),
    body: Column(children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: const BoxDecoration(
          gradient: LinearGradient(colors: [navy, turquoise]),
        ),
        child: Row(children: [
          IconButton(
            key: const Key('deda_stage71_history_top_left'),
            onPressed: _rows == null ? null : _history,
            icon: const Icon(Icons.history_edu, color: Colors.white),
            tooltip: _text('سجل المنح والاستخدام', 'History'),
          ),
          Expanded(child: Text(
            _text('مجموعتان • 100 يمين و100 يسار • لون أصلي ثابت',
                'Two groups • 100 each • original fixed color'),
            style: const TextStyle(color: Colors.white, fontSize: 12),
            textAlign: TextAlign.center,
          )),
        ]),
      ),
      if (_loading || _importing) const LinearProgressIndicator(),
      if (_importing) Padding(
        padding: const EdgeInsets.all(4),
        child: Text('$_importProgress / 200',
          textAlign: TextAlign.center),
      ),
      Expanded(child: _rows == null
        ? Center(child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(_error ?? _text(
              'جاري التحقق من الإدارة والقائمتين',
              'Verifying manager role and both catalogs',
            ), textAlign: TextAlign.center),
          ))
        : Row(
            key: const Key('deda_stage71_two_equal_vertical_columns'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _column('001'),
              const VerticalDivider(width: 2, thickness: 1),
              _column('002'),
            ],
          )),
    ]),
  );
}
