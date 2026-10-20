import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'deda_backend.dart';

/// STAGE19 PRIVATE UI. Sensitive member names are NEVER embedded in the APK.
/// Only an authenticated, AppCheck-enforced server endpoint may supply records.
/// Null bridges intentionally fail closed; a visible preview is NOT a grant.
class DedaExclusiveAdminId {
  final int sequence;
  final String identifier;
  final String status; // available | gifted | self_used
  final String? permanentColor;
  final String? ownerOriginalId;
  const DedaExclusiveAdminId({
    required this.sequence,
    required this.identifier,
    required this.status,
    this.permanentColor,
    this.ownerOriginalId,
  });
  bool get available => status == 'available' && permanentColor == null;
}

class DedaExclusiveAdminGrant {
  final String identifier;
  final String recipientOriginalId;
  final String color;
  final DateTime grantedAt;
  final String kind; // gifted | self_used
  const DedaExclusiveAdminGrant({
    required this.identifier,
    required this.recipientOriginalId,
    required this.color,
    required this.grantedAt,
    required this.kind,
  });
}

class DedaExclusiveAdminSnapshot {
  final bool serverConfirmed;
  final int total;
  final List<DedaExclusiveAdminId> identifiers;
  final List<DedaExclusiveAdminGrant> history;
  const DedaExclusiveAdminSnapshot({
    required this.serverConfirmed,
    required this.total,
    required this.identifiers,
    required this.history,
  });
}

/// Validates untrusted server snapshots, without bundling the private 100.
class DedaExclusiveAdminSnapshotVerifier {
  static const colors = {'gold', 'diamond', 'royal', 'pink'};
  static final identifier = RegExp(r'^@DEDA-[A-Z0-9]{4,12}
  // Server callable is NOT currently deployed. Builds default to false:
  // the exclusive catalog remains hidden, never guess client-side data.
  static const bool serverReadFlag =
      bool.fromEnvironment('DEDA_STAGE19_MANAGER100_READ_LIVE',
          defaultValue: false);

  static void installReadOnlyBridgeIfApproved() {
    if (!serverReadFlag || readRemote != null) return;
    readRemote = () async {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null || uid.isEmpty) {
        throw StateError('verified-login-required');
      }
      final call = FirebaseFunctions.instance.httpsCallable(
        'dedaStage19Exclusive100Read',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 40)),
      );
      final response = await call.call(<String, dynamic>{});
      if (FirebaseAuth.instance.currentUser?.uid != uid) {
        throw StateError('manager-session-changed');
      }
      final data = response.data;
      if (data is! Map) throw StateError('verified-server-response-required');
      final map = Map<String, dynamic>.from(data);
      if (map['serverConfirmed'] != true ||
          map['total'] != 100 ||
          map['identifiers'] is! List ||
          map['history'] is! List) {
        throw StateError('unverified-admin100-response');
      }
      final rawRows = map['identifiers'] as List;
      final rawHistory = map['history'] as List;
      if (rawRows.length != 100) {
        throw StateError('admin100-count-mismatch');
      }
      final identifiers = <DedaExclusiveAdminId>[];
      for (final row in rawRows) {
        if (row is! Map) throw StateError('invalid-admin100-row');
        final id = Map<String, dynamic>.from(row);
        if (id['sequence'] is! int ||
            id['identifier'] is! String ||
            id['status'] is! String ||
            (id['permanentColor'] != null &&
                id['permanentColor'] is! String) ||
            (id['ownerOriginalId'] != null &&
                id['ownerOriginalId'] is! String)) {
          throw StateError('invalid-admin100-row');
        }
        identifiers.add(DedaExclusiveAdminId(
          sequence: id['sequence'] as int,
          identifier: id['identifier'] as String,
          status: id['status'] as String,
          permanentColor: id['permanentColor'] as String?,
          ownerOriginalId: id['ownerOriginalId'] as String?,
        ));
      }
      final history = <DedaExclusiveAdminGrant>[];
      for (final row in rawHistory) {
        if (row is! Map) throw StateError('invalid-admin100-history');
        final h = Map<String, dynamic>.from(row);
        if (h['identifier'] is! String ||
            h['recipientOriginalId'] is! String ||
            h['color'] is! String ||
            h['kind'] is! String ||
            h['grantedAt'] is! String) {
          throw StateError('invalid-admin100-history');
        }
        history.add(DedaExclusiveAdminGrant(
          identifier: h['identifier'] as String,
          recipientOriginalId: h['recipientOriginalId'] as String,
          color: h['color'] as String,
          kind: h['kind'] as String,
          grantedAt: DateTime.parse(h['grantedAt'] as String),
        ));
      }
      return DedaExclusiveAdminSnapshot(
        serverConfirmed: true,
        total: 100,
        identifiers: identifiers,
        history: history,
      );
    };
  }
  // Explicitly controlled by BOTH owner-reviewed server AND private APK
  // rollout. The signed 100359 APK does not set either action flag.
  static const bool serverActionsFlag =
      bool.fromEnvironment('DEDA_STAGE32_MANAGER100_ACTIONS_LIVE',
          defaultValue: false);

  static void installVerifiedActionsIfApproved() {
    if (!serverReadFlag || !serverActionsFlag || readRemote == null) return;
    useForManagerRemote ??= (identifier, color) async {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null || uid.isEmpty) throw StateError('verified-login-required');
      final result = await FirebaseFunctions.instance.httpsCallable(
        'dedaStage19Exclusive100SelfUse',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 40)),
      ).call(<String, dynamic>{'identifier': identifier, 'color': color});
      if (FirebaseAuth.instance.currentUser?.uid != uid ||
          result.data is! Map) throw StateError('manager-session-changed');
      final verified = Map<String, dynamic>.from(result.data as Map);
      if (verified['serverConfirmed'] != true ||
          verified['identifier'] != identifier ||
          verified['permanentColor'] != color ||
          verified['activeId'] != identifier) {
        throw StateError('unverified-admin-self-use');
      }
    };
    grantToUserRemote ??= (identifier, color, recipientOriginalId) async {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null || uid.isEmpty) throw StateError('verified-login-required');
      final result = await FirebaseFunctions.instance.httpsCallable(
        'dedaStage19Exclusive100Grant',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 40)),
      ).call(<String, dynamic>{
        'identifier': identifier,
        'color': color,
        'recipientOriginalId': recipientOriginalId,
      });
      if (FirebaseAuth.instance.currentUser?.uid != uid ||
          result.data is! Map) throw StateError('manager-session-changed');
      final verified = Map<String, dynamic>.from(result.data as Map);
      if (verified['serverConfirmed'] != true ||
          verified['identifier'] != identifier ||
          verified['permanentColor'] != color ||
          verified['recipientOriginalId'] != recipientOriginalId) {
        throw StateError('unverified-admin-grant');
      }
    };
  }

  // Inject ONLY real, authenticated Firebase Callable clients AFTER audited
  // server release. No raw Firestore client writes, local grant or test data.
  static Future<DedaExclusiveAdminSnapshot> Function()? readRemote;
  static Future<void> Function(String identifier, String color)?
      useForManagerRemote;
  static Future<void> Function(
    String identifier, String color, String recipientOriginalId
  )? grantToUserRemote;
}

class DedaExclusiveIdsAdminPage extends StatefulWidget {
  const DedaExclusiveIdsAdminPage({super.key, required this.isArabic});
  final bool isArabic;

  @override
  State<DedaExclusiveIdsAdminPage> createState() =>
      _DedaExclusiveIdsAdminPageState();
}

class _DedaExclusiveIdsAdminPageState
    extends State<DedaExclusiveIdsAdminPage> {
  static const Color _navy = Color(0xFF092B40);
  static const Color _turquoise = Color(0xFF1ED0C4);
  static const Color _background = Color(0xFFE7F2F3);
  static const List<String> _colors = ['gold', 'diamond', 'royal', 'pink'];
  final Map<String, String> _draftColors = <String, String>{};
  bool? _allowed;
  bool _busy = false;
  int _loadGeneration = 0;
  String? _snapshotOwnerUid;
  StreamSubscription<User?>? _authSubscription;
  String? _error;
  DedaExclusiveAdminSnapshot? _snapshot;

  String _t(String ar, String en) => widget.isArabic ? ar : en;

  String _colorName(String color) {
    switch (color) {
      case 'gold': return _t('ذهبي', 'Gold');
      case 'diamond': return _t('ماسي', 'Diamond');
      case 'royal': return _t('ملكي', 'Royal');
      case 'pink': return _t('وردي', 'Pink');
      default: return _t('غير معروف', 'Unknown');
    }
  }

  Color _cardColor(String color) {
    switch (color) {
      case 'gold': return const Color(0xFF5A3510);
      case 'diamond': return const Color(0xFF315775);
      case 'royal': return const Color(0xFF542B73);
      case 'pink': return const Color(0xFFB96387);
      default: return _navy;
    }
  }

  @override
  void initState() {
    super.initState();
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (!mounted || _snapshotOwnerUid == null ||
          user?.uid == _snapshotOwnerUid) return;
      _loadGeneration++;
      setState(() {
        _snapshotOwnerUid = null;
        _snapshot = null;
        _allowed = false;
        _error = null;
        _draftColors.clear();
      });
    });
    _load();
  }

  @override
  void dispose() {
    _loadGeneration++;
    _authSubscription?.cancel();
    super.dispose();
  }

  Future<bool> _isVerifiedManager() async {
    try {
      final profile =
          await DedaBackend.currentAdminProfile(forceRefresh: true);
      return profile != null &&
          DedaBackend.normalizeAdminRole(profile['role']) ==
              'general_manager' &&
          DedaBackend.normalizeAdminStatus(profile) == 'active';
    } catch (_) {
      return false;
    }
  }

  bool _snapshotIsSafe(DedaExclusiveAdminSnapshot snap) =>
      DedaExclusiveAdminSnapshotVerifier.isSafe(snap);

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    final expectedUid = FirebaseAuth.instance.currentUser?.uid;
    final allowed = expectedUid != null && await _isVerifiedManager();
    if (!mounted || generation != _loadGeneration) return;
    if (FirebaseAuth.instance.currentUser?.uid != expectedUid) {
      setState(() {
        _allowed = false;
        _snapshotOwnerUid = null;
        _snapshot = null;
        _draftColors.clear();
      });
      return;
    }
    setState(() {
      _allowed = allowed;
      _snapshotOwnerUid = null;
      _snapshot = null;
      _error = null;
      _draftColors.clear();
    });
    if (!allowed) return;
    DedaExclusiveAdminBridge.installReadOnlyBridgeIfApproved();
    DedaExclusiveAdminBridge.installVerifiedActionsIfApproved();
    final read = DedaExclusiveAdminBridge.readRemote;
    if (read == null) {
      setState(() {
        _error = _t(
          'القائمة الحصرية محمية. يتطلب عرضها تفعيل القراءة الموثقة من الخادم.',
          'The exclusive catalog is protected until verified server read is available.',
        );
      });
      return;
    }
    try {
      final snapshot = await read();
      if (!mounted || generation != _loadGeneration) return;
      final sameUid = FirebaseAuth.instance.currentUser?.uid == expectedUid;
      final managerNow = sameUid && await _isVerifiedManager();
      if (!mounted || generation != _loadGeneration) return;
      if (!managerNow || FirebaseAuth.instance.currentUser?.uid != expectedUid) {
        setState(() {
          _allowed = false;
          _snapshotOwnerUid = null;
          _snapshot = null;
          _draftColors.clear();
          _error = null;
        });
        return;
      }
      if (!_snapshotIsSafe(snapshot)) {
        setState(() => _error = _t(
          'توقف آمن: بيانات القائمة غير مكتملة أو غير موثقة.',
          'Safe stop: the server catalog is incomplete or unverified.',
        ));
        return;
      }
      setState(() {
        _snapshotOwnerUid = expectedUid;
        _snapshot = snapshot;
      });
    } catch (_) {
      if (mounted && generation == _loadGeneration) {
        setState(() => _error = _t(
          'تعذر التحقق من القائمة من الخادم. لم تتغير أي ملكية.',
          'Server verification failed. No ownership changed.',
        ));
      }
    }
  }

  String _colorFor(DedaExclusiveAdminId item) =>
      item.permanentColor ??
      _draftColors[item.identifier] ??
      'gold';

  void _openHistory() {
    final history = _snapshot?.history;
    if (_allowed != true || history == null) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(ctx).height * 0.7,
          child: Column(
            children: [
              Text(
                _t('📜 سجل المعرّفات الممنوحة', '📜 Exclusive ID grants'),
                style: Theme.of(ctx).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Expanded(
                child: history.isEmpty
                    ? Center(child: Text(_t(
                        'لا يوجد منح موثق حتى الآن.',
                        'No server-verified grants yet.',
                      )))
                    : ListView.builder(
                        itemCount: history.length,
                        itemBuilder: (context, i) {
                          final record = history[i];
                          final utc = record.grantedAt.toUtc().toIso8601String();
                          return ListTile(
                            title: Text(record.identifier),
                            subtitle: Text(
                              (record.kind == 'self_used'
                                  ? _t('استخدام المدير العام', 'Manager self-use')
                                  : _t('مُنح إلى ', 'Gifted to ') +
                                      record.recipientOriginalId) +
                                  ' • ' + _colorName(record.color) +
                                  '\n' + utc,
                            ),
                            leading: const Icon(Icons.history_edu),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<String?> _askRecipient() async {
    final controller = TextEditingController();
    try {
      return await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(_t('معرّف المستلم الأصلي', 'Recipient original ID')),
          content: TextField(
            controller: controller,
            maxLength: 18,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              hintText: '@DEDA-XXXXXX',
              helperText: _t('لا تستخدم رقم الهاتف أو UID',
                'Do not enter a phone or account UID'),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(_t('إلغاء', 'Cancel')),
            ),
            TextButton(
              onPressed: () {
                final id = controller.text.trim().toUpperCase();
                if (RegExp(r'^@DEDA-[A-Z0-9]{6}$').hasMatch(id)) {
                  Navigator.pop(dialogContext, id);
                }
              },
              child: Text(_t('التالي', 'Next')),
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  Future<void> _commit(DedaExclusiveAdminId item, {required bool gift}) async {
    if (_busy || _allowed != true || !item.available ||
        _snapshot == null || !_snapshot!.serverConfirmed) return;
    final actionSelf = DedaExclusiveAdminBridge.useForManagerRemote;
    final actionGift = DedaExclusiveAdminBridge.grantToUserRemote;
    if ((gift && actionGift == null) || (!gift && actionSelf == null)) return;
    final color = _colorFor(item);
    final identifier = item.identifier;
    final recipient = gift ? await _askRecipient() : null;
    if (!mounted || (gift && recipient == null)) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_t('تثبيت اللون نهائيًا', 'Permanently lock the color')),
        content: Text(
          identifier + '\n' + _colorName(color) + '\n' +
          (gift ? _t('منح إلى: ', 'Gift to: ') + recipient!
              : _t('استخدام المدير العام', 'Manager self-use')) +
          '\n' + _t('بعد التأكيد لا يمكن تغيير اللون مدى الحياة.',
            'Once confirmed, this color cannot be changed for life.'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(_t('إلغاء', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_t('تأكيد نهائي', 'Confirm permanently')),
          ),
        ],
      ),
    );
    if (!mounted || confirm != true || _busy ||
        !await _isVerifiedManager()) return;
    setState(() => _busy = true);
    try {
      if (gift) {
        await actionGift!(identifier, color, recipient!);
      } else {
        await actionSelf!(identifier, color);
      }
      // A successful button press never grants local ownership. All state
      // comes from the next server-confirmed catalog read.
      await _load();
      if (!mounted) return;
      final verified = _snapshot?.identifiers.where(
        (x) => x.identifier == identifier && !x.available &&
            x.permanentColor == color,
      ).isNotEmpty ?? false;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(verified
            ? _t('تم إثبات التثبيت من الخادم', 'Server confirmed permanent lock')
            : _t('بانتظار تأكيد حالة المعرّف من الخادم',
                'Awaiting confirmed server state')),
      ));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_t('فشل التحقق؛ لم نثبت أي لون محليًا.',
            'Verification failed; no color was locked locally.')),
        ));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _preview(DedaExclusiveAdminId item, String color) {
    final base = _cardColor(color);
    return Container(
      key: ValueKey<String>('deda_stage19_one_preview_' + item.identifier),
      height: 50,
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          base.withOpacity(0.85), base, base.withOpacity(0.92),
        ]),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: const Color(0xFFCFB77A), width: 1.7),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          const Icon(Icons.diamond_outlined,
              size: 17, color: Color(0xFFFFE5A0)),
          const SizedBox(width: 8),
          Expanded(child: FittedBox(
            alignment: AlignmentDirectional.centerStart,
            fit: BoxFit.scaleDown,
            child: Text(item.identifier,
              maxLines: 1,
              style: const TextStyle(color: Colors.white,
                  fontWeight: FontWeight.w900, fontSize: 22),
            ),
          )),
          const SizedBox(width: 7),
          const Icon(Icons.workspace_premium,
              size: 19, color: Color(0xFFFFE5A0)),
        ],
      ),
    );
  }

  Widget _exclusiveItem(DedaExclusiveAdminId item) {
    final color = _colorFor(item);
    final available = item.available;
    return Container(
      key: ValueKey<String>('deda_stage19_exclusive_item_' + item.sequence.toString()),
      padding: const EdgeInsets.all(11),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.92),
        border: Border.all(color: const Color(0xFF9DC7CB)),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Text('#' + item.sequence.toString().padLeft(3, '0'),
                style: const TextStyle(fontWeight: FontWeight.bold,
                    color: _navy)),
            const Spacer(),
            Text(available
                ? _t('متاح للإدارة', 'Available to manager')
                : _t('🔒 اللون مثبت مدى الحياة', '🔒 Color permanently locked'),
                style: const TextStyle(fontSize: 12, color: _navy)),
          ]),
          const SizedBox(height: 7),
          _preview(item, color),
          const SizedBox(height: 9),
          if (available) ...[
            Wrap(spacing: 5, runSpacing: 5, children: [
              for (final choice in _colors)
                ChoiceChip(
                  key: ValueKey<String>('deda_stage19_color_' +
                      item.sequence.toString() + '_' + choice),
                  label: Text(_colorName(choice)),
                  selected: color == choice,
                  onSelected: _busy ? null : (_) {
                    setState(() => _draftColors[item.identifier] = choice);
                  },
                  visualDensity: VisualDensity.compact,
                ),
            ]),
            const SizedBox(height: 7),
            Wrap(spacing: 8, runSpacing: 6, children: [
              OutlinedButton.icon(
                onPressed: _busy ||
                    DedaExclusiveAdminBridge.useForManagerRemote == null
                    ? null : () => _commit(item, gift: false),
                icon: const Icon(Icons.person_outline),
                label: Text(_t('استخدام لنفسي', 'Use for manager')),
              ),
              FilledButton.icon(
                onPressed: _busy ||
                    DedaExclusiveAdminBridge.grantToUserRemote == null
                    ? null : () => _commit(item, gift: true),
                icon: const Icon(Icons.card_giftcard),
                label: Text(_t('منح هدية', 'Gift identifier')),
              ),
            ]),
          ] else Text(
            _t('مثبت: ', 'Fixed: ') + _colorName(color) +
              (item.ownerOriginalId == null ? '' :
                ' • ' + item.ownerOriginalId!),
            style: const TextStyle(color: _navy, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_allowed == false) {
      return Scaffold(
        backgroundColor: _background,
        appBar: AppBar(title: Text(_t(
          'إدارة المعرّفات الحصرية', 'Exclusive ID administration'))),
        body: Center(child: Text(_t(
          'هذه الصفحة مخصصة للمدير العام المخوّل فقط.',
          'Authorized general managers only.',
        ))),
      );
    }
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _navy,
        foregroundColor: Colors.white,
        title: Text(_t('إدارة المعرّفات الحصرية',
          'Exclusive ID administration')),
      ),
      body: _allowed == null
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Container(
                  key: const Key('deda_stage19_navy_turquoise_header'),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [_navy, Color(0xFF125D67), _turquoise],
                      begin: AlignmentDirectional.topStart,
                      end: AlignmentDirectional.bottomEnd,
                    ),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: _turquoise, width: 1.3),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                        alignment: Alignment.topLeft,
                        child: IconButton(
                          key: const Key('deda_stage19_grant_log_top_left'),
                          onPressed: _snapshot == null ? null : _openHistory,
                          tooltip: _t('📜 سجل المعرّفات الممنوحة',
                            'Grant history'),
                          icon: const Icon(Icons.history_edu,
                            color: Colors.white),
                        ),
                      ),
                      Text(_t('الـ100 معرّف الحصرية',
                          '100 exclusive identifiers'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white,
                          fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        _snapshot == null
                          ? _t('حماية قائمة الإدارة • بانتظار توثيق الخادم',
                            'Private catalog • awaiting verified server read')
                          : _t('المجموع: ', 'Total: ') +
                              _snapshot!.total.toString() +
                              '  •  ' + _t('المتاحة: ', 'Available: ') +
                              _snapshot!.identifiers.where((x) =>
                                x.available).length.toString(),
                        style: const TextStyle(color: Colors.white),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: _snapshot == null
                  ? Center(child: Padding(
                      padding: const EdgeInsets.all(22),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.lock_outline,
                              color: _navy, size: 38),
                          const SizedBox(height: 12),
                          Text(_error ?? _t('جاري التحقق من القائمة.',
                            'Verifying the catalog.'),
                            textAlign: TextAlign.center),
                          const SizedBox(height: 12),
                          OutlinedButton(
                            onPressed: _load,
                            child: Text(_t('إعادة المحاولة', 'Retry')),
                          ),
                        ],
                      ),
                    ))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        itemCount: _snapshot!.identifiers.length,
                        itemBuilder: (context, index) =>
                            _exclusiveItem(_snapshot!.identifiers[index]),
                      ),
                    ),
              ),
            ]),
    );
  }
}
);
  static final originalId = RegExp(r'^@DEDA-[A-Z0-9]{6}
  // Server callable is NOT currently deployed. Builds default to false:
  // the exclusive catalog remains hidden, never guess client-side data.
  static const bool serverReadFlag =
      bool.fromEnvironment('DEDA_STAGE19_MANAGER100_READ_LIVE',
          defaultValue: false);

  static void installReadOnlyBridgeIfApproved() {
    if (!serverReadFlag || readRemote != null) return;
    readRemote = () async {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null || uid.isEmpty) {
        throw StateError('verified-login-required');
      }
      final call = FirebaseFunctions.instance.httpsCallable(
        'dedaStage19Exclusive100Read',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 40)),
      );
      final response = await call.call(<String, dynamic>{});
      if (FirebaseAuth.instance.currentUser?.uid != uid) {
        throw StateError('manager-session-changed');
      }
      final data = response.data;
      if (data is! Map) throw StateError('verified-server-response-required');
      final map = Map<String, dynamic>.from(data);
      if (map['serverConfirmed'] != true ||
          map['total'] != 100 ||
          map['identifiers'] is! List ||
          map['history'] is! List) {
        throw StateError('unverified-admin100-response');
      }
      final rawRows = map['identifiers'] as List;
      final rawHistory = map['history'] as List;
      if (rawRows.length != 100) {
        throw StateError('admin100-count-mismatch');
      }
      final identifiers = <DedaExclusiveAdminId>[];
      for (final row in rawRows) {
        if (row is! Map) throw StateError('invalid-admin100-row');
        final id = Map<String, dynamic>.from(row);
        if (id['sequence'] is! int ||
            id['identifier'] is! String ||
            id['status'] is! String ||
            (id['permanentColor'] != null &&
                id['permanentColor'] is! String) ||
            (id['ownerOriginalId'] != null &&
                id['ownerOriginalId'] is! String)) {
          throw StateError('invalid-admin100-row');
        }
        identifiers.add(DedaExclusiveAdminId(
          sequence: id['sequence'] as int,
          identifier: id['identifier'] as String,
          status: id['status'] as String,
          permanentColor: id['permanentColor'] as String?,
          ownerOriginalId: id['ownerOriginalId'] as String?,
        ));
      }
      final history = <DedaExclusiveAdminGrant>[];
      for (final row in rawHistory) {
        if (row is! Map) throw StateError('invalid-admin100-history');
        final h = Map<String, dynamic>.from(row);
        if (h['identifier'] is! String ||
            h['recipientOriginalId'] is! String ||
            h['color'] is! String ||
            h['kind'] is! String ||
            h['grantedAt'] is! String) {
          throw StateError('invalid-admin100-history');
        }
        history.add(DedaExclusiveAdminGrant(
          identifier: h['identifier'] as String,
          recipientOriginalId: h['recipientOriginalId'] as String,
          color: h['color'] as String,
          kind: h['kind'] as String,
          grantedAt: DateTime.parse(h['grantedAt'] as String),
        ));
      }
      return DedaExclusiveAdminSnapshot(
        serverConfirmed: true,
        total: 100,
        identifiers: identifiers,
        history: history,
      );
    };
  }
  // Explicitly controlled by BOTH owner-reviewed server AND private APK
  // rollout. The signed 100359 APK does not set either action flag.
  static const bool serverActionsFlag =
      bool.fromEnvironment('DEDA_STAGE32_MANAGER100_ACTIONS_LIVE',
          defaultValue: false);

  static void installVerifiedActionsIfApproved() {
    if (!serverReadFlag || !serverActionsFlag || readRemote == null) return;
    useForManagerRemote ??= (identifier, color) async {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null || uid.isEmpty) throw StateError('verified-login-required');
      final result = await FirebaseFunctions.instance.httpsCallable(
        'dedaStage19Exclusive100SelfUse',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 40)),
      ).call(<String, dynamic>{'identifier': identifier, 'color': color});
      if (FirebaseAuth.instance.currentUser?.uid != uid ||
          result.data is! Map) throw StateError('manager-session-changed');
      final verified = Map<String, dynamic>.from(result.data as Map);
      if (verified['serverConfirmed'] != true ||
          verified['identifier'] != identifier ||
          verified['permanentColor'] != color ||
          verified['activeId'] != identifier) {
        throw StateError('unverified-admin-self-use');
      }
    };
    grantToUserRemote ??= (identifier, color, recipientOriginalId) async {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null || uid.isEmpty) throw StateError('verified-login-required');
      final result = await FirebaseFunctions.instance.httpsCallable(
        'dedaStage19Exclusive100Grant',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 40)),
      ).call(<String, dynamic>{
        'identifier': identifier,
        'color': color,
        'recipientOriginalId': recipientOriginalId,
      });
      if (FirebaseAuth.instance.currentUser?.uid != uid ||
          result.data is! Map) throw StateError('manager-session-changed');
      final verified = Map<String, dynamic>.from(result.data as Map);
      if (verified['serverConfirmed'] != true ||
          verified['identifier'] != identifier ||
          verified['permanentColor'] != color ||
          verified['recipientOriginalId'] != recipientOriginalId) {
        throw StateError('unverified-admin-grant');
      }
    };
  }

  // Inject ONLY real, authenticated Firebase Callable clients AFTER audited
  // server release. No raw Firestore client writes, local grant or test data.
  static Future<DedaExclusiveAdminSnapshot> Function()? readRemote;
  static Future<void> Function(String identifier, String color)?
      useForManagerRemote;
  static Future<void> Function(
    String identifier, String color, String recipientOriginalId
  )? grantToUserRemote;
}

class DedaExclusiveIdsAdminPage extends StatefulWidget {
  const DedaExclusiveIdsAdminPage({super.key, required this.isArabic});
  final bool isArabic;

  @override
  State<DedaExclusiveIdsAdminPage> createState() =>
      _DedaExclusiveIdsAdminPageState();
}

class _DedaExclusiveIdsAdminPageState
    extends State<DedaExclusiveIdsAdminPage> {
  static const Color _navy = Color(0xFF092B40);
  static const Color _turquoise = Color(0xFF1ED0C4);
  static const Color _background = Color(0xFFE7F2F3);
  static const List<String> _colors = ['gold', 'diamond', 'royal', 'pink'];
  final Map<String, String> _draftColors = <String, String>{};
  bool? _allowed;
  bool _busy = false;
  int _loadGeneration = 0;
  String? _snapshotOwnerUid;
  StreamSubscription<User?>? _authSubscription;
  String? _error;
  DedaExclusiveAdminSnapshot? _snapshot;

  String _t(String ar, String en) => widget.isArabic ? ar : en;

  String _colorName(String color) {
    switch (color) {
      case 'gold': return _t('ذهبي', 'Gold');
      case 'diamond': return _t('ماسي', 'Diamond');
      case 'royal': return _t('ملكي', 'Royal');
      case 'pink': return _t('وردي', 'Pink');
      default: return _t('غير معروف', 'Unknown');
    }
  }

  Color _cardColor(String color) {
    switch (color) {
      case 'gold': return const Color(0xFF5A3510);
      case 'diamond': return const Color(0xFF315775);
      case 'royal': return const Color(0xFF542B73);
      case 'pink': return const Color(0xFFB96387);
      default: return _navy;
    }
  }

  @override
  void initState() {
    super.initState();
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (!mounted || _snapshotOwnerUid == null ||
          user?.uid == _snapshotOwnerUid) return;
      _loadGeneration++;
      setState(() {
        _snapshotOwnerUid = null;
        _snapshot = null;
        _allowed = false;
        _error = null;
        _draftColors.clear();
      });
    });
    _load();
  }

  @override
  void dispose() {
    _loadGeneration++;
    _authSubscription?.cancel();
    super.dispose();
  }

  Future<bool> _isVerifiedManager() async {
    try {
      final profile =
          await DedaBackend.currentAdminProfile(forceRefresh: true);
      return profile != null &&
          DedaBackend.normalizeAdminRole(profile['role']) ==
              'general_manager' &&
          DedaBackend.normalizeAdminStatus(profile) == 'active';
    } catch (_) {
      return false;
    }
  }

  bool _snapshotIsSafe(DedaExclusiveAdminSnapshot snap) =>
      DedaExclusiveAdminSnapshotVerifier.isSafe(snap);

  Future<void> _load() async {
    final allowed = await _isVerifiedManager();
    if (!mounted) return;
    setState(() {
      _allowed = allowed;
      _snapshot = null;
      _error = null;
      _draftColors.clear();
    });
    if (!allowed) return;
    DedaExclusiveAdminBridge.installReadOnlyBridgeIfApproved();
    DedaExclusiveAdminBridge.installVerifiedActionsIfApproved();
    final read = DedaExclusiveAdminBridge.readRemote;
    if (read == null) {
      setState(() {
        _error = _t(
          'القائمة الحصرية محمية. يتطلب عرضها تفعيل القراءة الموثقة من الخادم.',
          'The exclusive catalog is protected until verified server read is available.',
        );
      });
      return;
    }
    try {
      final snapshot = await read();
      if (!mounted) return;
      if (!_snapshotIsSafe(snapshot)) {
        setState(() => _error = _t(
          'توقف آمن: بيانات القائمة غير مكتملة أو غير موثقة.',
          'Safe stop: the server catalog is incomplete or unverified.',
        ));
        return;
      }
      setState(() => _snapshot = snapshot);
    } catch (_) {
      if (mounted) {
        setState(() => _error = _t(
          'تعذر التحقق من القائمة من الخادم. لم تتغير أي ملكية.',
          'Server verification failed. No ownership changed.',
        ));
      }
    }
  }

  String _colorFor(DedaExclusiveAdminId item) =>
      item.permanentColor ??
      _draftColors[item.identifier] ??
      'gold';

  void _openHistory() {
    final history = _snapshot?.history;
    if (_allowed != true || history == null) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(ctx).height * 0.7,
          child: Column(
            children: [
              Text(
                _t('📜 سجل المعرّفات الممنوحة', '📜 Exclusive ID grants'),
                style: Theme.of(ctx).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Expanded(
                child: history.isEmpty
                    ? Center(child: Text(_t(
                        'لا يوجد منح موثق حتى الآن.',
                        'No server-verified grants yet.',
                      )))
                    : ListView.builder(
                        itemCount: history.length,
                        itemBuilder: (context, i) {
                          final record = history[i];
                          final utc = record.grantedAt.toUtc().toIso8601String();
                          return ListTile(
                            title: Text(record.identifier),
                            subtitle: Text(
                              (record.kind == 'self_used'
                                  ? _t('استخدام المدير العام', 'Manager self-use')
                                  : _t('مُنح إلى ', 'Gifted to ') +
                                      record.recipientOriginalId) +
                                  ' • ' + _colorName(record.color) +
                                  '\n' + utc,
                            ),
                            leading: const Icon(Icons.history_edu),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<String?> _askRecipient() async {
    final controller = TextEditingController();
    try {
      return await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(_t('معرّف المستلم الأصلي', 'Recipient original ID')),
          content: TextField(
            controller: controller,
            maxLength: 18,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              hintText: '@DEDA-XXXXXX',
              helperText: _t('لا تستخدم رقم الهاتف أو UID',
                'Do not enter a phone or account UID'),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(_t('إلغاء', 'Cancel')),
            ),
            TextButton(
              onPressed: () {
                final id = controller.text.trim().toUpperCase();
                if (RegExp(r'^@DEDA-[A-Z0-9]{6}$').hasMatch(id)) {
                  Navigator.pop(dialogContext, id);
                }
              },
              child: Text(_t('التالي', 'Next')),
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  Future<void> _commit(DedaExclusiveAdminId item, {required bool gift}) async {
    if (_busy || _allowed != true || !item.available ||
        _snapshot == null || !_snapshot!.serverConfirmed) return;
    final actionSelf = DedaExclusiveAdminBridge.useForManagerRemote;
    final actionGift = DedaExclusiveAdminBridge.grantToUserRemote;
    if ((gift && actionGift == null) || (!gift && actionSelf == null)) return;
    final color = _colorFor(item);
    final identifier = item.identifier;
    final recipient = gift ? await _askRecipient() : null;
    if (!mounted || (gift && recipient == null)) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_t('تثبيت اللون نهائيًا', 'Permanently lock the color')),
        content: Text(
          identifier + '\n' + _colorName(color) + '\n' +
          (gift ? _t('منح إلى: ', 'Gift to: ') + recipient!
              : _t('استخدام المدير العام', 'Manager self-use')) +
          '\n' + _t('بعد التأكيد لا يمكن تغيير اللون مدى الحياة.',
            'Once confirmed, this color cannot be changed for life.'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(_t('إلغاء', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_t('تأكيد نهائي', 'Confirm permanently')),
          ),
        ],
      ),
    );
    if (!mounted || confirm != true || _busy ||
        !await _isVerifiedManager()) return;
    setState(() => _busy = true);
    try {
      if (gift) {
        await actionGift!(identifier, color, recipient!);
      } else {
        await actionSelf!(identifier, color);
      }
      // A successful button press never grants local ownership. All state
      // comes from the next server-confirmed catalog read.
      await _load();
      if (!mounted) return;
      final verified = _snapshot?.identifiers.where(
        (x) => x.identifier == identifier && !x.available &&
            x.permanentColor == color,
      ).isNotEmpty ?? false;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(verified
            ? _t('تم إثبات التثبيت من الخادم', 'Server confirmed permanent lock')
            : _t('بانتظار تأكيد حالة المعرّف من الخادم',
                'Awaiting confirmed server state')),
      ));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_t('فشل التحقق؛ لم نثبت أي لون محليًا.',
            'Verification failed; no color was locked locally.')),
        ));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _preview(DedaExclusiveAdminId item, String color) {
    final base = _cardColor(color);
    return Container(
      key: ValueKey<String>('deda_stage19_one_preview_' + item.identifier),
      height: 50,
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          base.withOpacity(0.85), base, base.withOpacity(0.92),
        ]),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: const Color(0xFFCFB77A), width: 1.7),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          const Icon(Icons.diamond_outlined,
              size: 17, color: Color(0xFFFFE5A0)),
          const SizedBox(width: 8),
          Expanded(child: FittedBox(
            alignment: AlignmentDirectional.centerStart,
            fit: BoxFit.scaleDown,
            child: Text(item.identifier,
              maxLines: 1,
              style: const TextStyle(color: Colors.white,
                  fontWeight: FontWeight.w900, fontSize: 22),
            ),
          )),
          const SizedBox(width: 7),
          const Icon(Icons.workspace_premium,
              size: 19, color: Color(0xFFFFE5A0)),
        ],
      ),
    );
  }

  Widget _exclusiveItem(DedaExclusiveAdminId item) {
    final color = _colorFor(item);
    final available = item.available;
    return Container(
      key: ValueKey<String>('deda_stage19_exclusive_item_' + item.sequence.toString()),
      padding: const EdgeInsets.all(11),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.92),
        border: Border.all(color: const Color(0xFF9DC7CB)),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Text('#' + item.sequence.toString().padLeft(3, '0'),
                style: const TextStyle(fontWeight: FontWeight.bold,
                    color: _navy)),
            const Spacer(),
            Text(available
                ? _t('متاح للإدارة', 'Available to manager')
                : _t('🔒 اللون مثبت مدى الحياة', '🔒 Color permanently locked'),
                style: const TextStyle(fontSize: 12, color: _navy)),
          ]),
          const SizedBox(height: 7),
          _preview(item, color),
          const SizedBox(height: 9),
          if (available) ...[
            Wrap(spacing: 5, runSpacing: 5, children: [
              for (final choice in _colors)
                ChoiceChip(
                  key: ValueKey<String>('deda_stage19_color_' +
                      item.sequence.toString() + '_' + choice),
                  label: Text(_colorName(choice)),
                  selected: color == choice,
                  onSelected: _busy ? null : (_) {
                    setState(() => _draftColors[item.identifier] = choice);
                  },
                  visualDensity: VisualDensity.compact,
                ),
            ]),
            const SizedBox(height: 7),
            Wrap(spacing: 8, runSpacing: 6, children: [
              OutlinedButton.icon(
                onPressed: _busy ||
                    DedaExclusiveAdminBridge.useForManagerRemote == null
                    ? null : () => _commit(item, gift: false),
                icon: const Icon(Icons.person_outline),
                label: Text(_t('استخدام لنفسي', 'Use for manager')),
              ),
              FilledButton.icon(
                onPressed: _busy ||
                    DedaExclusiveAdminBridge.grantToUserRemote == null
                    ? null : () => _commit(item, gift: true),
                icon: const Icon(Icons.card_giftcard),
                label: Text(_t('منح هدية', 'Gift identifier')),
              ),
            ]),
          ] else Text(
            _t('مثبت: ', 'Fixed: ') + _colorName(color) +
              (item.ownerOriginalId == null ? '' :
                ' • ' + item.ownerOriginalId!),
            style: const TextStyle(color: _navy, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_allowed == false) {
      return Scaffold(
        backgroundColor: _background,
        appBar: AppBar(title: Text(_t(
          'إدارة المعرّفات الحصرية', 'Exclusive ID administration'))),
        body: Center(child: Text(_t(
          'هذه الصفحة مخصصة للمدير العام المخوّل فقط.',
          'Authorized general managers only.',
        ))),
      );
    }
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _navy,
        foregroundColor: Colors.white,
        title: Text(_t('إدارة المعرّفات الحصرية',
          'Exclusive ID administration')),
      ),
      body: _allowed == null
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Container(
                  key: const Key('deda_stage19_navy_turquoise_header'),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [_navy, Color(0xFF125D67), _turquoise],
                      begin: AlignmentDirectional.topStart,
                      end: AlignmentDirectional.bottomEnd,
                    ),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: _turquoise, width: 1.3),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                        alignment: Alignment.topLeft,
                        child: IconButton(
                          key: const Key('deda_stage19_grant_log_top_left'),
                          onPressed: _snapshot == null ? null : _openHistory,
                          tooltip: _t('📜 سجل المعرّفات الممنوحة',
                            'Grant history'),
                          icon: const Icon(Icons.history_edu,
                            color: Colors.white),
                        ),
                      ),
                      Text(_t('الـ100 معرّف الحصرية',
                          '100 exclusive identifiers'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white,
                          fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        _snapshot == null
                          ? _t('حماية قائمة الإدارة • بانتظار توثيق الخادم',
                            'Private catalog • awaiting verified server read')
                          : _t('المجموع: ', 'Total: ') +
                              _snapshot!.total.toString() +
                              '  •  ' + _t('المتاحة: ', 'Available: ') +
                              _snapshot!.identifiers.where((x) =>
                                x.available).length.toString(),
                        style: const TextStyle(color: Colors.white),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: _snapshot == null
                  ? Center(child: Padding(
                      padding: const EdgeInsets.all(22),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.lock_outline,
                              color: _navy, size: 38),
                          const SizedBox(height: 12),
                          Text(_error ?? _t('جاري التحقق من القائمة.',
                            'Verifying the catalog.'),
                            textAlign: TextAlign.center),
                          const SizedBox(height: 12),
                          OutlinedButton(
                            onPressed: _load,
                            child: Text(_t('إعادة المحاولة', 'Retry')),
                          ),
                        ],
                      ),
                    ))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        itemCount: _snapshot!.identifiers.length,
                        itemBuilder: (context, index) =>
                            _exclusiveItem(_snapshot!.identifiers[index]),
                      ),
                    ),
              ),
            ]),
    );
  }
}
);

  static bool isSafe(DedaExclusiveAdminSnapshot snap) {
    if (!snap.serverConfirmed || snap.total != 100 ||
        snap.identifiers.length != 100) return false;
    final rows = <String, DedaExclusiveAdminId>{};
    var assigned = 0;
    for (var i = 0; i < snap.identifiers.length; i++) {
      final row = snap.identifiers[i];
      if (row.sequence != i + 1 || !identifier.hasMatch(row.identifier) ||
          rows.containsKey(row.identifier) ||
          !const {'available', 'gifted', 'self_used'}.contains(row.status)) {
        return false;
      }
      if (row.status == 'available') {
        if (row.permanentColor != null || row.ownerOriginalId != null) {
          return false;
        }
      } else {
        assigned++;
        if (!colors.contains(row.permanentColor) ||
            !originalId.hasMatch(row.ownerOriginalId ?? '')) return false;
      }
      rows[row.identifier] = row;
    }
    if (snap.history.length != assigned) return false;
    final seen = <String>{};
    DateTime? previous;
    for (final event in snap.history) {
      final row = rows[event.identifier];
      if (row == null || row.status == 'available' ||
          !seen.add(event.identifier) || event.kind != row.status ||
          event.color != row.permanentColor ||
          event.recipientOriginalId != row.ownerOriginalId ||
          !colors.contains(event.color) ||
          !originalId.hasMatch(event.recipientOriginalId)) return false;
      if (previous != null && event.grantedAt.isAfter(previous)) return false;
      previous = event.grantedAt;
    }
    return true;
  }
}

class DedaExclusiveAdminBridge {
  // Server callable is NOT currently deployed. Builds default to false:
  // the exclusive catalog remains hidden, never guess client-side data.
  static const bool serverReadFlag =
      bool.fromEnvironment('DEDA_STAGE19_MANAGER100_READ_LIVE',
          defaultValue: false);

  static void installReadOnlyBridgeIfApproved() {
    if (!serverReadFlag || readRemote != null) return;
    readRemote = () async {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null || uid.isEmpty) {
        throw StateError('verified-login-required');
      }
      final call = FirebaseFunctions.instance.httpsCallable(
        'dedaStage19Exclusive100Read',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 40)),
      );
      final response = await call.call(<String, dynamic>{});
      if (FirebaseAuth.instance.currentUser?.uid != uid) {
        throw StateError('manager-session-changed');
      }
      final data = response.data;
      if (data is! Map) throw StateError('verified-server-response-required');
      final map = Map<String, dynamic>.from(data);
      if (map['serverConfirmed'] != true ||
          map['total'] != 100 ||
          map['identifiers'] is! List ||
          map['history'] is! List) {
        throw StateError('unverified-admin100-response');
      }
      final rawRows = map['identifiers'] as List;
      final rawHistory = map['history'] as List;
      if (rawRows.length != 100) {
        throw StateError('admin100-count-mismatch');
      }
      final identifiers = <DedaExclusiveAdminId>[];
      for (final row in rawRows) {
        if (row is! Map) throw StateError('invalid-admin100-row');
        final id = Map<String, dynamic>.from(row);
        if (id['sequence'] is! int ||
            id['identifier'] is! String ||
            id['status'] is! String ||
            (id['permanentColor'] != null &&
                id['permanentColor'] is! String) ||
            (id['ownerOriginalId'] != null &&
                id['ownerOriginalId'] is! String)) {
          throw StateError('invalid-admin100-row');
        }
        identifiers.add(DedaExclusiveAdminId(
          sequence: id['sequence'] as int,
          identifier: id['identifier'] as String,
          status: id['status'] as String,
          permanentColor: id['permanentColor'] as String?,
          ownerOriginalId: id['ownerOriginalId'] as String?,
        ));
      }
      final history = <DedaExclusiveAdminGrant>[];
      for (final row in rawHistory) {
        if (row is! Map) throw StateError('invalid-admin100-history');
        final h = Map<String, dynamic>.from(row);
        if (h['identifier'] is! String ||
            h['recipientOriginalId'] is! String ||
            h['color'] is! String ||
            h['kind'] is! String ||
            h['grantedAt'] is! String) {
          throw StateError('invalid-admin100-history');
        }
        history.add(DedaExclusiveAdminGrant(
          identifier: h['identifier'] as String,
          recipientOriginalId: h['recipientOriginalId'] as String,
          color: h['color'] as String,
          kind: h['kind'] as String,
          grantedAt: DateTime.parse(h['grantedAt'] as String),
        ));
      }
      return DedaExclusiveAdminSnapshot(
        serverConfirmed: true,
        total: 100,
        identifiers: identifiers,
        history: history,
      );
    };
  }
  // Explicitly controlled by BOTH owner-reviewed server AND private APK
  // rollout. The signed 100359 APK does not set either action flag.
  static const bool serverActionsFlag =
      bool.fromEnvironment('DEDA_STAGE32_MANAGER100_ACTIONS_LIVE',
          defaultValue: false);

  static void installVerifiedActionsIfApproved() {
    if (!serverReadFlag || !serverActionsFlag || readRemote == null) return;
    useForManagerRemote ??= (identifier, color) async {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null || uid.isEmpty) throw StateError('verified-login-required');
      final result = await FirebaseFunctions.instance.httpsCallable(
        'dedaStage19Exclusive100SelfUse',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 40)),
      ).call(<String, dynamic>{'identifier': identifier, 'color': color});
      if (FirebaseAuth.instance.currentUser?.uid != uid ||
          result.data is! Map) throw StateError('manager-session-changed');
      final verified = Map<String, dynamic>.from(result.data as Map);
      if (verified['serverConfirmed'] != true ||
          verified['identifier'] != identifier ||
          verified['permanentColor'] != color ||
          verified['activeId'] != identifier) {
        throw StateError('unverified-admin-self-use');
      }
    };
    grantToUserRemote ??= (identifier, color, recipientOriginalId) async {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null || uid.isEmpty) throw StateError('verified-login-required');
      final result = await FirebaseFunctions.instance.httpsCallable(
        'dedaStage19Exclusive100Grant',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 40)),
      ).call(<String, dynamic>{
        'identifier': identifier,
        'color': color,
        'recipientOriginalId': recipientOriginalId,
      });
      if (FirebaseAuth.instance.currentUser?.uid != uid ||
          result.data is! Map) throw StateError('manager-session-changed');
      final verified = Map<String, dynamic>.from(result.data as Map);
      if (verified['serverConfirmed'] != true ||
          verified['identifier'] != identifier ||
          verified['permanentColor'] != color ||
          verified['recipientOriginalId'] != recipientOriginalId) {
        throw StateError('unverified-admin-grant');
      }
    };
  }

  // Inject ONLY real, authenticated Firebase Callable clients AFTER audited
  // server release. No raw Firestore client writes, local grant or test data.
  static Future<DedaExclusiveAdminSnapshot> Function()? readRemote;
  static Future<void> Function(String identifier, String color)?
      useForManagerRemote;
  static Future<void> Function(
    String identifier, String color, String recipientOriginalId
  )? grantToUserRemote;
}

class DedaExclusiveIdsAdminPage extends StatefulWidget {
  const DedaExclusiveIdsAdminPage({super.key, required this.isArabic});
  final bool isArabic;

  @override
  State<DedaExclusiveIdsAdminPage> createState() =>
      _DedaExclusiveIdsAdminPageState();
}

class _DedaExclusiveIdsAdminPageState
    extends State<DedaExclusiveIdsAdminPage> {
  static const Color _navy = Color(0xFF092B40);
  static const Color _turquoise = Color(0xFF1ED0C4);
  static const Color _background = Color(0xFFE7F2F3);
  static const List<String> _colors = ['gold', 'diamond', 'royal', 'pink'];
  final Map<String, String> _draftColors = <String, String>{};
  bool? _allowed;
  bool _busy = false;
  int _loadGeneration = 0;
  String? _snapshotOwnerUid;
  StreamSubscription<User?>? _authSubscription;
  String? _error;
  DedaExclusiveAdminSnapshot? _snapshot;

  String _t(String ar, String en) => widget.isArabic ? ar : en;

  String _colorName(String color) {
    switch (color) {
      case 'gold': return _t('ذهبي', 'Gold');
      case 'diamond': return _t('ماسي', 'Diamond');
      case 'royal': return _t('ملكي', 'Royal');
      case 'pink': return _t('وردي', 'Pink');
      default: return _t('غير معروف', 'Unknown');
    }
  }

  Color _cardColor(String color) {
    switch (color) {
      case 'gold': return const Color(0xFF5A3510);
      case 'diamond': return const Color(0xFF315775);
      case 'royal': return const Color(0xFF542B73);
      case 'pink': return const Color(0xFFB96387);
      default: return _navy;
    }
  }

  @override
  void initState() {
    super.initState();
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (!mounted || _snapshotOwnerUid == null ||
          user?.uid == _snapshotOwnerUid) return;
      _loadGeneration++;
      setState(() {
        _snapshotOwnerUid = null;
        _snapshot = null;
        _allowed = false;
        _error = null;
        _draftColors.clear();
      });
    });
    _load();
  }

  @override
  void dispose() {
    _loadGeneration++;
    _authSubscription?.cancel();
    super.dispose();
  }

  Future<bool> _isVerifiedManager() async {
    try {
      final profile =
          await DedaBackend.currentAdminProfile(forceRefresh: true);
      return profile != null &&
          DedaBackend.normalizeAdminRole(profile['role']) ==
              'general_manager' &&
          DedaBackend.normalizeAdminStatus(profile) == 'active';
    } catch (_) {
      return false;
    }
  }

  bool _snapshotIsSafe(DedaExclusiveAdminSnapshot snap) =>
      DedaExclusiveAdminSnapshotVerifier.isSafe(snap);

  Future<void> _load() async {
    final allowed = await _isVerifiedManager();
    if (!mounted) return;
    setState(() {
      _allowed = allowed;
      _snapshot = null;
      _error = null;
      _draftColors.clear();
    });
    if (!allowed) return;
    DedaExclusiveAdminBridge.installReadOnlyBridgeIfApproved();
    DedaExclusiveAdminBridge.installVerifiedActionsIfApproved();
    final read = DedaExclusiveAdminBridge.readRemote;
    if (read == null) {
      setState(() {
        _error = _t(
          'القائمة الحصرية محمية. يتطلب عرضها تفعيل القراءة الموثقة من الخادم.',
          'The exclusive catalog is protected until verified server read is available.',
        );
      });
      return;
    }
    try {
      final snapshot = await read();
      if (!mounted) return;
      if (!_snapshotIsSafe(snapshot)) {
        setState(() => _error = _t(
          'توقف آمن: بيانات القائمة غير مكتملة أو غير موثقة.',
          'Safe stop: the server catalog is incomplete or unverified.',
        ));
        return;
      }
      setState(() => _snapshot = snapshot);
    } catch (_) {
      if (mounted) {
        setState(() => _error = _t(
          'تعذر التحقق من القائمة من الخادم. لم تتغير أي ملكية.',
          'Server verification failed. No ownership changed.',
        ));
      }
    }
  }

  String _colorFor(DedaExclusiveAdminId item) =>
      item.permanentColor ??
      _draftColors[item.identifier] ??
      'gold';

  void _openHistory() {
    final history = _snapshot?.history;
    if (_allowed != true || history == null) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(ctx).height * 0.7,
          child: Column(
            children: [
              Text(
                _t('📜 سجل المعرّفات الممنوحة', '📜 Exclusive ID grants'),
                style: Theme.of(ctx).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Expanded(
                child: history.isEmpty
                    ? Center(child: Text(_t(
                        'لا يوجد منح موثق حتى الآن.',
                        'No server-verified grants yet.',
                      )))
                    : ListView.builder(
                        itemCount: history.length,
                        itemBuilder: (context, i) {
                          final record = history[i];
                          final utc = record.grantedAt.toUtc().toIso8601String();
                          return ListTile(
                            title: Text(record.identifier),
                            subtitle: Text(
                              (record.kind == 'self_used'
                                  ? _t('استخدام المدير العام', 'Manager self-use')
                                  : _t('مُنح إلى ', 'Gifted to ') +
                                      record.recipientOriginalId) +
                                  ' • ' + _colorName(record.color) +
                                  '\n' + utc,
                            ),
                            leading: const Icon(Icons.history_edu),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<String?> _askRecipient() async {
    final controller = TextEditingController();
    try {
      return await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(_t('معرّف المستلم الأصلي', 'Recipient original ID')),
          content: TextField(
            controller: controller,
            maxLength: 18,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              hintText: '@DEDA-XXXXXX',
              helperText: _t('لا تستخدم رقم الهاتف أو UID',
                'Do not enter a phone or account UID'),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(_t('إلغاء', 'Cancel')),
            ),
            TextButton(
              onPressed: () {
                final id = controller.text.trim().toUpperCase();
                if (RegExp(r'^@DEDA-[A-Z0-9]{6}$').hasMatch(id)) {
                  Navigator.pop(dialogContext, id);
                }
              },
              child: Text(_t('التالي', 'Next')),
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  Future<void> _commit(DedaExclusiveAdminId item, {required bool gift}) async {
    if (_busy || _allowed != true || !item.available ||
        _snapshot == null || !_snapshot!.serverConfirmed) return;
    final actionSelf = DedaExclusiveAdminBridge.useForManagerRemote;
    final actionGift = DedaExclusiveAdminBridge.grantToUserRemote;
    if ((gift && actionGift == null) || (!gift && actionSelf == null)) return;
    final color = _colorFor(item);
    final identifier = item.identifier;
    final recipient = gift ? await _askRecipient() : null;
    if (!mounted || (gift && recipient == null)) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_t('تثبيت اللون نهائيًا', 'Permanently lock the color')),
        content: Text(
          identifier + '\n' + _colorName(color) + '\n' +
          (gift ? _t('منح إلى: ', 'Gift to: ') + recipient!
              : _t('استخدام المدير العام', 'Manager self-use')) +
          '\n' + _t('بعد التأكيد لا يمكن تغيير اللون مدى الحياة.',
            'Once confirmed, this color cannot be changed for life.'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(_t('إلغاء', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_t('تأكيد نهائي', 'Confirm permanently')),
          ),
        ],
      ),
    );
    if (!mounted || confirm != true || _busy ||
        !await _isVerifiedManager()) return;
    setState(() => _busy = true);
    try {
      if (gift) {
        await actionGift!(identifier, color, recipient!);
      } else {
        await actionSelf!(identifier, color);
      }
      // A successful button press never grants local ownership. All state
      // comes from the next server-confirmed catalog read.
      await _load();
      if (!mounted) return;
      final verified = _snapshot?.identifiers.where(
        (x) => x.identifier == identifier && !x.available &&
            x.permanentColor == color,
      ).isNotEmpty ?? false;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(verified
            ? _t('تم إثبات التثبيت من الخادم', 'Server confirmed permanent lock')
            : _t('بانتظار تأكيد حالة المعرّف من الخادم',
                'Awaiting confirmed server state')),
      ));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_t('فشل التحقق؛ لم نثبت أي لون محليًا.',
            'Verification failed; no color was locked locally.')),
        ));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _preview(DedaExclusiveAdminId item, String color) {
    final base = _cardColor(color);
    return Container(
      key: ValueKey<String>('deda_stage19_one_preview_' + item.identifier),
      height: 50,
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          base.withOpacity(0.85), base, base.withOpacity(0.92),
        ]),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: const Color(0xFFCFB77A), width: 1.7),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          const Icon(Icons.diamond_outlined,
              size: 17, color: Color(0xFFFFE5A0)),
          const SizedBox(width: 8),
          Expanded(child: FittedBox(
            alignment: AlignmentDirectional.centerStart,
            fit: BoxFit.scaleDown,
            child: Text(item.identifier,
              maxLines: 1,
              style: const TextStyle(color: Colors.white,
                  fontWeight: FontWeight.w900, fontSize: 22),
            ),
          )),
          const SizedBox(width: 7),
          const Icon(Icons.workspace_premium,
              size: 19, color: Color(0xFFFFE5A0)),
        ],
      ),
    );
  }

  Widget _exclusiveItem(DedaExclusiveAdminId item) {
    final color = _colorFor(item);
    final available = item.available;
    return Container(
      key: ValueKey<String>('deda_stage19_exclusive_item_' + item.sequence.toString()),
      padding: const EdgeInsets.all(11),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.92),
        border: Border.all(color: const Color(0xFF9DC7CB)),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Text('#' + item.sequence.toString().padLeft(3, '0'),
                style: const TextStyle(fontWeight: FontWeight.bold,
                    color: _navy)),
            const Spacer(),
            Text(available
                ? _t('متاح للإدارة', 'Available to manager')
                : _t('🔒 اللون مثبت مدى الحياة', '🔒 Color permanently locked'),
                style: const TextStyle(fontSize: 12, color: _navy)),
          ]),
          const SizedBox(height: 7),
          _preview(item, color),
          const SizedBox(height: 9),
          if (available) ...[
            Wrap(spacing: 5, runSpacing: 5, children: [
              for (final choice in _colors)
                ChoiceChip(
                  key: ValueKey<String>('deda_stage19_color_' +
                      item.sequence.toString() + '_' + choice),
                  label: Text(_colorName(choice)),
                  selected: color == choice,
                  onSelected: _busy ? null : (_) {
                    setState(() => _draftColors[item.identifier] = choice);
                  },
                  visualDensity: VisualDensity.compact,
                ),
            ]),
            const SizedBox(height: 7),
            Wrap(spacing: 8, runSpacing: 6, children: [
              OutlinedButton.icon(
                onPressed: _busy ||
                    DedaExclusiveAdminBridge.useForManagerRemote == null
                    ? null : () => _commit(item, gift: false),
                icon: const Icon(Icons.person_outline),
                label: Text(_t('استخدام لنفسي', 'Use for manager')),
              ),
              FilledButton.icon(
                onPressed: _busy ||
                    DedaExclusiveAdminBridge.grantToUserRemote == null
                    ? null : () => _commit(item, gift: true),
                icon: const Icon(Icons.card_giftcard),
                label: Text(_t('منح هدية', 'Gift identifier')),
              ),
            ]),
          ] else Text(
            _t('مثبت: ', 'Fixed: ') + _colorName(color) +
              (item.ownerOriginalId == null ? '' :
                ' • ' + item.ownerOriginalId!),
            style: const TextStyle(color: _navy, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_allowed == false) {
      return Scaffold(
        backgroundColor: _background,
        appBar: AppBar(title: Text(_t(
          'إدارة المعرّفات الحصرية', 'Exclusive ID administration'))),
        body: Center(child: Text(_t(
          'هذه الصفحة مخصصة للمدير العام المخوّل فقط.',
          'Authorized general managers only.',
        ))),
      );
    }
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _navy,
        foregroundColor: Colors.white,
        title: Text(_t('إدارة المعرّفات الحصرية',
          'Exclusive ID administration')),
      ),
      body: _allowed == null
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Container(
                  key: const Key('deda_stage19_navy_turquoise_header'),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [_navy, Color(0xFF125D67), _turquoise],
                      begin: AlignmentDirectional.topStart,
                      end: AlignmentDirectional.bottomEnd,
                    ),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: _turquoise, width: 1.3),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                        alignment: Alignment.topLeft,
                        child: IconButton(
                          key: const Key('deda_stage19_grant_log_top_left'),
                          onPressed: _snapshot == null ? null : _openHistory,
                          tooltip: _t('📜 سجل المعرّفات الممنوحة',
                            'Grant history'),
                          icon: const Icon(Icons.history_edu,
                            color: Colors.white),
                        ),
                      ),
                      Text(_t('الـ100 معرّف الحصرية',
                          '100 exclusive identifiers'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white,
                          fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        _snapshot == null
                          ? _t('حماية قائمة الإدارة • بانتظار توثيق الخادم',
                            'Private catalog • awaiting verified server read')
                          : _t('المجموع: ', 'Total: ') +
                              _snapshot!.total.toString() +
                              '  •  ' + _t('المتاحة: ', 'Available: ') +
                              _snapshot!.identifiers.where((x) =>
                                x.available).length.toString(),
                        style: const TextStyle(color: Colors.white),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: _snapshot == null
                  ? Center(child: Padding(
                      padding: const EdgeInsets.all(22),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.lock_outline,
                              color: _navy, size: 38),
                          const SizedBox(height: 12),
                          Text(_error ?? _t('جاري التحقق من القائمة.',
                            'Verifying the catalog.'),
                            textAlign: TextAlign.center),
                          const SizedBox(height: 12),
                          OutlinedButton(
                            onPressed: _load,
                            child: Text(_t('إعادة المحاولة', 'Retry')),
                          ),
                        ],
                      ),
                    ))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        itemCount: _snapshot!.identifiers.length,
                        itemBuilder: (context, index) =>
                            _exclusiveItem(_snapshot!.identifiers[index]),
                      ),
                    ),
              ),
            ]),
    );
  }
}
