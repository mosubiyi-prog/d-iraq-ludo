import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'deda_stage2_isolated_admin_identity_2026_11_21.dart';
import 'deda_launch_feature_gates.dart';
import 'deda_stage2_isolated_exclusive_ids_admin_2026_11_23.dart';
import 'deda_stage2_isolated_league_admin_2026_11_23.dart';
import 'deda_stage2_isolated_tasks_admin_2026_11_23.dart';
import 'deda_stage2_isolated_support_trash_2026_11_23.dart';
import 'deda_admin_compact_card.dart';
import 'admin_place_map.dart';
import 'admin_team_pages.dart' show dedaAdminGovernorates,
    dedaAdminRoleLabel, dedaAdminTimestamp;

/// Reuses the original three manual owner-notice choices, but the sender
/// is the verified secondary admin session. No public Firebase objects.
Future<void> _showIsolatedOwnerNoticeComposer({
  required BuildContext context,
  required bool isArabic,
  required DedaIsolatedAdminIdentity admin,
  required String dedaPhone,
  required String sourceCollection,
  required String sourceId,
  required String placeName,
  required String accountKey,
}) async {
  String t(String ar, String en) => isArabic ? ar : en;
  final title = TextEditingController();
  final body = TextEditingController();
  var type = 'place_report';

  void applyTemplate(String selected) {
    type = selected;
    if (selected == 'place_report') {
      title.text = t('ورد بلاغ بخصوص مكانك',
          'A report was received about your place');
      body.text = t(
        'ورد إلى إدارة DEDA بلاغ بخصوص مكانك. تمت مراجعة البلاغ ونطلب منك مراجعة بيانات المكان والتأكد من صحتها. ستتواصل الإدارة عند الحاجة.',
        'DEDA administration received and reviewed a report about your place. Please review the place information and make sure it is accurate. Administration will contact you when needed.',
      );
    } else if (selected == 'admin_alert') {
      title.text = t('تنبيه إداري بخصوص مكانك',
          'Administration notice about your place');
      body.text = t('يرجى مراجعة بيانات مكانك في DEDA والتأكد من صحتها.',
          'Please review your place information in DEDA and make sure it is accurate.');
    } else {
      title.text = t('رسالة من إدارة DEDA', 'Message from DEDA administration');
      body.clear();
    }
  }

  applyTemplate(type);
  try {
    final draft = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, updateDialog) => AlertDialog(
          title: Text(t('إرسال إشعار لصاحب المكان',
              'Send notification to place owner')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(t('المكان: ', 'Place: ') + placeName,
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 5),
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: Text(t('حساب صاحب المكان: ', 'Owner account: ') +
                      accountKey),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: type,
                  decoration: InputDecoration(
                    labelText: t('نوع الإشعار', 'Notification type'),
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    DropdownMenuItem(value: 'place_report',
                        child: Text(t('ورد بلاغ بخصوص مكانك', 'Place report'))),
                    DropdownMenuItem(value: 'admin_alert',
                        child: Text(t('تنبيه إداري', 'Administration alert'))),
                    DropdownMenuItem(value: 'custom',
                        child: Text(t('رسالة مخصصة', 'Custom message'))),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    updateDialog(() => applyTemplate(value));
                  },
                ),
                const SizedBox(height: 12),
                TextField(controller: title, maxLength: 180,
                  decoration: InputDecoration(
                    labelText: t('عنوان الإشعار', 'Notification title'),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(controller: body, maxLength: 4000,
                  minLines: 4, maxLines: 7,
                  decoration: InputDecoration(
                    labelText: t('نص الإشعار', 'Notification message'),
                    border: const OutlineInputBorder(),
                  ),
                ),
                Text(t('سيظهر الإشعار داخل جرس إشعارات صاحب المكان للقراءة فقط، بدون إمكانية الرد.',
                    'The owner sees this in the read-only notification bell.')),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext),
                child: Text(t('إلغاء', 'Cancel'))),
            FilledButton.icon(
              onPressed: () => Navigator.pop(dialogContext, <String, String>{
                'type': type, 'title': title.text.trim(), 'body': body.text.trim(),
              }),
              icon: const Icon(Icons.arrow_forward_outlined),
              label: Text(t('مراجعة قبل الإرسال', 'Review before sending')),
            ),
          ],
        ),
      ),
    );
    if (draft == null || !context.mounted) return;
    final selectedTitle = (draft['title'] ?? '').trim();
    final selectedBody = (draft['body'] ?? '').trim();
    if (selectedTitle.isEmpty || selectedBody.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(t('اكتب العنوان ونص الإشعار قبل الإرسال.',
            'Enter the notification title and message.')),
      ));
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(t('تأكيد الإشعار', 'Confirm notification')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(placeName, style: const TextStyle(fontWeight: FontWeight.w800)),
              Directionality(
                textDirection: TextDirection.ltr, child: Text(accountKey)),
              const Divider(height: 20),
              Text(selectedTitle, style: const TextStyle(
                  fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              Text(selectedBody),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(t('رجوع', 'Back'))),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.send_outlined),
            label: Text(t('إرسال الإشعار', 'Send notification')),
          ),
        ],
      ),
    ) ?? false;
    if (!confirm || !context.mounted) return;
    try {
      await admin.sendScopedOwnerPlaceNotification(
        dedaPhone: dedaPhone,
        sourceCollection: sourceCollection,
        sourceId: sourceId,
        expectedAccountKey: accountKey,
        type: draft['type'] ?? 'custom',
        title: selectedTitle,
        body: selectedBody,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(t('تم إرسال الإشعار وتسجيله إدارياً.',
              'Notice sent and audited.')),
        ));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(t('تعذر الإرسال: تحقق من صلاحية الإدارة وملكية المكان.',
              'Send denied: verify admin permission and place ownership.')),
        ));
      }
    }
  } finally {
    title.dispose();
    body.dispose();
  }
}

/// Shared read-only place detail rows; never touches a Firebase principal.
Widget _isolatedPlaceField(String title, dynamic raw, {bool ltr = false}) {
  final value = (raw ?? '').toString().trim();
  if (value.isEmpty) return const SizedBox.shrink();
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title + ': ', style: const TextStyle(fontWeight: FontWeight.w700)),
      Expanded(child: ltr
          ? Directionality(textDirection: TextDirection.ltr,
              child: Text(value))
          : Text(value)),
    ]),
  );
}

bool _isolatedValidPlaceCoords(dynamic latitude, dynamic longitude) =>
    latitude is num && longitude is num &&
    latitude.toDouble().isFinite && longitude.toDouble().isFinite &&
    latitude >= -90 && latitude <= 90 &&
    longitude >= -180 && longitude <= 180;

Future<void> _openIsolatedPlaceMap({
  required BuildContext context,
  required bool isArabic,
  required String placeName,
  required num latitude,
  required num longitude,
}) async {
  if (!_isolatedValidPlaceCoords(latitude, longitude)) return;
  await Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => DedaAdminPlaceMapPage(
      isArabic: isArabic, placeName: placeName,
      latitude: latitude.toDouble(), longitude: longitude.toDouble(),
    ),
  ));
}

// Read-only support images keep the original three-image legacy formats.
// The viewer uses the EXISTING native saveImage channel, no Firebase writes.
class _DedaIsolatedSupportAttachment {
  final String url;
  final String base64Data;
  final String mimeType;
  const _DedaIsolatedSupportAttachment({
    this.url = '', this.base64Data = '', this.mimeType = 'image/jpeg',
  });
  bool get isNetwork => url.isNotEmpty;
}

List<_DedaIsolatedSupportAttachment> _isolatedSupportAttachments(
    Map<String, dynamic> data) {
  final images = <_DedaIsolatedSupportAttachment>[];
  final seen = <String>{};
  final urls = data['imageUrls'];
  final mimeTypes = data['imageMimeTypes'];
  if (urls is List) {
    for (var i = 0; i < urls.length && images.length < 3; i++) {
      final url = (urls[i] ?? '').toString().trim();
      if (url.isEmpty || !seen.add(url)) continue;
      final mime = mimeTypes is List && i < mimeTypes.length
          ? (mimeTypes[i] ?? '').toString().trim() : '';
      images.add(_DedaIsolatedSupportAttachment(
        url: url, mimeType: mime.isEmpty ? 'image/jpeg' : mime,
      ));
    }
  }
  final oldUrl = (data['imageUrl'] ?? '').toString().trim();
  if (oldUrl.isNotEmpty && images.length < 3 && seen.add(oldUrl)) {
    final mime = (data['imageMimeType'] ?? '').toString().trim();
    images.add(_DedaIsolatedSupportAttachment(
      url: oldUrl, mimeType: mime.isEmpty ? 'image/jpeg' : mime,
    ));
  }
  final oldBase64 = (data['imageBase64'] ?? '').toString().trim();
  if (images.isEmpty && oldBase64.isNotEmpty) {
    final mime = (data['imageMimeType'] ?? '').toString().trim();
    images.add(_DedaIsolatedSupportAttachment(
      base64Data: oldBase64, mimeType: mime.isEmpty ? 'image/jpeg' : mime,
    ));
  }
  return images;
}

Widget _isolatedSupportImage(
  _DedaIsolatedSupportAttachment photo, {
  required bool isArabic,
  required BoxFit fit,
}) {
  String t(String ar, String en) => isArabic ? ar : en;
  Widget missing() => Center(child: Text(
    t('تعذر عرض الصورة.', 'Could not display image.'),
  ));
  if (photo.isNetwork) {
    final uri = Uri.tryParse(photo.url);
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) {
      return missing();
    }
    return Image.network(
      photo.url,
      fit: fit,
      loadingBuilder: (_, child, progress) => progress == null
          ? child : const Center(child: CircularProgressIndicator()),
      errorBuilder: (_, __, ___) => missing(),
    );
  }
  try {
    return Image.memory(base64Decode(photo.base64Data), fit: fit,
      errorBuilder: (_, __, ___) => missing());
  } catch (_) {
    return missing();
  }
}

Widget _isolatedSupportPhotoGallery({
  required BuildContext context,
  required bool isArabic,
  required Map<String, dynamic> data,
}) {
  String t(String ar, String en) => isArabic ? ar : en;
  final photos = _isolatedSupportAttachments(data);
  if (photos.isEmpty) return const SizedBox.shrink();
  return Padding(
    padding: const EdgeInsets.all(12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(photos.length == 1
              ? t('الصورة المرفقة', 'Attached image')
              : t('الصور المرفقة', 'Attached images') +
                  ' (' + photos.length.toString() + '/3)',
          style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: photos.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: photos.length == 1 ? 1 : 3,
            childAspectRatio: photos.length == 1 ? 1.8 : 1,
            crossAxisSpacing: 8, mainAxisSpacing: 8,
          ),
          itemBuilder: (_, index) => InkWell(
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => _DedaIsolatedSupportAttachmentViewer(
                images: photos, initialIndex: index, isArabic: isArabic),
            )),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Stack(fit: StackFit.expand, children: [
                _isolatedSupportImage(photos[index],
                    isArabic: isArabic, fit: BoxFit.cover),
                PositionedDirectional(
                  bottom: 6, end: 6,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(20)),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
                      child: Text((index + 1).toString() + '/' +
                          photos.length.toString(),
                        style: const TextStyle(
                            color: Colors.white, fontSize: 11),
                        textDirection: TextDirection.ltr),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ),
        const SizedBox(height: 5),
        Text(t('اضغط على الصورة للتكبير أو الحفظ.',
            'Tap an image to zoom or save.'),
            textAlign: TextAlign.center),
      ],
    ),
  );
}

class _DedaIsolatedSupportAttachmentViewer extends StatefulWidget {
  final List<_DedaIsolatedSupportAttachment> images;
  final int initialIndex;
  final bool isArabic;
  const _DedaIsolatedSupportAttachmentViewer({
    required this.images, required this.initialIndex, required this.isArabic,
  });
  @override
  State<_DedaIsolatedSupportAttachmentViewer> createState() =>
      _DedaIsolatedSupportAttachmentViewerState();
}

class _DedaIsolatedSupportAttachmentViewerState
    extends State<_DedaIsolatedSupportAttachmentViewer> {
  static const _mediaChannel = MethodChannel('com.diraq.ludo/media');
  late final PageController _controller;
  late int _index;
  bool _saving = false;
  String t(String ar, String en) => widget.isArabic ? ar : en;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.images.length - 1).toInt();
    _controller = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _ext(String mime) => switch (mime.toLowerCase()) {
    'image/png' => 'png',
    'image/webp' => 'webp',
    'image/gif' => 'gif',
    _ => 'jpg',
  };

  Future<Uint8List> _photoBytes(
      _DedaIsolatedSupportAttachment image) async {
    if (!image.isNetwork) return base64Decode(image.base64Data);
    final uri = Uri.tryParse(image.url);
    if (uri == null || !(uri.scheme == 'https' || uri.scheme == 'http')) {
      throw const FormatException('unsupported-image-url');
    }
    final http = HttpClient();
    try {
      final request = await http.getUrl(uri);
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('image-not-available');
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response) {
        builder.add(chunk);
        if (builder.length > 16 * 1024 * 1024) {
          throw const FormatException('image-size-cap');
        }
      }
      return builder.takeBytes();
    } finally {
      http.close(force: true);
    }
  }

  Future<void> _save() async {
    if (_saving || widget.images.isEmpty) return;
    setState(() => _saving = true);
    try {
      final selected = widget.images[_index];
      final bytes = await _photoBytes(selected);
      await _mediaChannel.invokeMethod<String>(
        'saveImage', <String, dynamic>{
          'bytes': bytes,
          'fileName': 'DEDA_support_' +
              DateTime.now().millisecondsSinceEpoch.toString() +
              '_' + (_index + 1).toString() + '.' + _ext(selected.mimeType),
          'mimeType': selected.mimeType,
        },
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(t('تم حفظ الصورة في صور الجهاز داخل مجلد DEDA.',
              'Image saved to the DEDA folder in device pictures.')),
        ));
      }
    } on PlatformException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(error.code == 'permission_required'
              ? t('اسمح بحفظ الصور ثم أعد المحاولة.',
                  'Allow photo storage, then try again.')
              : t('تعذر حفظ الصورة.', 'Could not save image.')),
        ));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(t('تعذر حفظ الصورة.', 'Could not save image.')),
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      title: Text(t('صورة', 'Image') + ' ' + (_index + 1).toString() +
          '/' + widget.images.length.toString()),
      actions: [
        IconButton(
          tooltip: t('حفظ الصورة', 'Save image'),
          onPressed: _saving ? null : _save,
          icon: _saving ? const SizedBox(
              height: 20, width: 20,
              child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.download_outlined),
        ),
      ],
    ),
    body: PageView.builder(
      controller: _controller,
      itemCount: widget.images.length,
      onPageChanged: (index) => setState(() => _index = index),
      itemBuilder: (_, index) => InteractiveViewer(
        minScale: 0.8,
        maxScale: 5.0,
        boundaryMargin: const EdgeInsets.all(48),
        child: SizedBox.expand(
          child: Center(child: _isolatedSupportImage(
            widget.images[index], isArabic: widget.isArabic,
            fit: BoxFit.contain)),
        ),
      ),
    ),
  );
}

/// Stage2 migration bridge, NOT the complete administrative Dashboard.
/// It never calls DedaBackend, the public Auth, or the public Firestore.
/// The stage flag remains OFF until all original admin operations are ported.
class DedaStage2IsolatedDashboardPage extends StatefulWidget {
  final DedaIsolatedAdminIdentity admin;
  final String dedaPhone;
  final Map<String, dynamic> profile;
  final bool isArabic;

  const DedaStage2IsolatedDashboardPage({
    super.key,
    required this.admin,
    required this.dedaPhone,
    required this.profile,
    required this.isArabic,
  });

  @override
  State<DedaStage2IsolatedDashboardPage> createState() =>
      _DedaStage2IsolatedDashboardPageState();
}

class _DedaStage2IsolatedDashboardPageState
    extends State<DedaStage2IsolatedDashboardPage> {
  String t(String ar, String en) => widget.isArabic ? ar : en;

  bool _exiting = false;
  bool _refreshing = false;
  bool _refreshProofFailed = false;
  int _refreshEpoch = 0;
  Map<String, dynamic>? _freshVerifiedProfile;
  late Stream<int> _staffRecoveryStream;

  @override
  void initState() {
    super.initState();
    _staffRecoveryStream = widget.admin.watchScopedPendingStaffRecoveryCount(
      dedaPhone: widget.dedaPhone,
    );
  }

  Future<void> _refreshDashboard() async {
    if (_refreshing || _exiting) return;
    setState(() => _refreshing = true);
    try {
      // Refresh the actual server profile before rebuilding ALL destinations.
      final verified = await widget.admin.readVerifiedAdminProfile(
        dedaPhone: widget.dedaPhone,
      );
      if (!mounted) return;
      setState(() {
        _freshVerifiedProfile = verified;
        _refreshEpoch++;
        _refreshProofFailed = false;
        _staffRecoveryStream =
            widget.admin.watchScopedPendingStaffRecoveryCount(
          dedaPhone: widget.dedaPhone,
        );
      });
    } catch (_) {
      if (!mounted) return;
      // A revoked role/network failure must never leave old privileged
      // cards visible as though a fresh authorization succeeded.
      setState(() => _refreshProofFailed = true);
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _exit() async {
    if (_exiting) return;
    _exiting = true;
    try {
      await widget.admin.signOutSecondaryAdmin();
    } finally {
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!dedaIsolatedAdminIdentityEnabled) {
      return const Scaffold(body: Center(child: Text('Admin stage disabled')));
    }
    if (_refreshProofFailed) {
      return Scaffold(
        appBar: AppBar(title: Text(t('إدارة DEDA', 'DEDA administration')),
          actions: [
            IconButton(
              onPressed: _refreshing ? null : _refreshDashboard,
              icon: const Icon(Icons.refresh),
              tooltip: t('إعادة التحقق', 'Recheck access'),
            ),
            IconButton(
              onPressed: _exit, icon: const Icon(Icons.logout),
              tooltip: t('تسجيل خروج الإدارة', 'Admin sign out'),
            ),
          ]),
        body: Center(child: Text(t(
          'تعذر إثبات صلاحيات الإدارة من الخادم. أعد المحاولة.',
          'Could not confirm administrator privileges. Retry.',
        ))),
      );
    }
    final profile = _freshVerifiedProfile ?? widget.profile;
    // Fresh server proof controls the refreshed card grid.
    bool can(String permission) => DedaIsolatedAdminProofPolicy.allowsPermission(
          admin: profile,
          permission: permission,
        );
    // Keep the accepted legacy tile design without duplicating its widget.
    // Every visible card is registered with its already-isolated destination
    // in one operation; no route to DedaBackend or public Firebase is added.
    final tabs = <Tab>[];
    final pages = <Widget>[];
    final cardIcons = <IconData>[];
    final cardSubtitles = <String>[];
    final cardColors = <Color>[];
    final cardExclusivePalettes = <bool>[];
    int? staffRecoveryTabIndex;
    void addDestination({
      required String title,
      required String subtitle,
      required IconData icon,
      required Color accentColor,
      bool exclusiveNavyTurquoise = false,
      required Widget page,
    }) {
      tabs.add(Tab(text: title));
      pages.add(page);
      cardIcons.add(icon);
      cardSubtitles.add(subtitle);
      cardColors.add(accentColor);
      cardExclusivePalettes.add(exclusiveNavyTurquoise);
    }

    if (can('supportRead')) {
      addDestination(
        title: t('الدعم', 'Support'),
        subtitle: t('رسائل المستخدمين والردود', 'User messages and replies'),
        icon: Icons.support_agent,
        accentColor: const Color(0xFF00796B),
        page: _DedaIsolatedRequestTab(
          admin: widget.admin,
          dedaPhone: widget.dedaPhone,
          isArabic: widget.isArabic,
          profile: profile,
          collection: 'support_requests',
        ),
      );
    }
    if (can('viewPlaceRequests')) {
      addDestination(
        title: t('طلبات الأماكن', 'Place requests'),
        subtitle: t('المراجعة والاعتماد حسب الصلاحية',
            'Review according to permission'),
        icon: Icons.storefront_outlined,
        accentColor: const Color(0xFF2E7D32),
        page: _DedaIsolatedRequestTab(
          admin: widget.admin,
          dedaPhone: widget.dedaPhone,
          isArabic: widget.isArabic,
          profile: profile,
          collection: 'place_requests',
        ),
      );
    }
    // ORIGINAL public-user recovery, distinct from staff recovery requests.
    if (profile['role'] == 'general_manager') {
      addDestination(
        title: t('استرجاع الدخول', 'Recovery'),
        subtitle: t('طلبات استرجاع الحساب الحساسة',
            'Sensitive account recovery requests'),
        icon: Icons.lock_reset,
        accentColor: const Color(0xFF9A6700),
        page: _DedaIsolatedUserRecoveryTab(
          admin: widget.admin,
          dedaPhone: widget.dedaPhone,
          isArabic: widget.isArabic,
        ),
      );
    }
    if (can('viewUsers')) {
      addDestination(
        title: t('المستخدمون', 'Users'),
        subtitle: t('قراءة فقط', 'Read only'),
        icon: Icons.people_alt_outlined,
        accentColor: const Color(0xFF4F5AA8),
        page: _DedaIsolatedReadOnlyTab(
          admin: widget.admin,
          dedaPhone: widget.dedaPhone,
          isArabic: widget.isArabic,
          collection: 'users',
        ),
      );
    }
    if (can('viewAudit')) {
      addDestination(
        title: t('سجل الإدارة', 'Admin audit'),
        subtitle: t('من قام بماذا ومتى', 'Who did what and when'),
        icon: Icons.fact_check_outlined,
        accentColor: const Color(0xFF476A78),
        page: _DedaIsolatedReadOnlyTab(
          admin: widget.admin,
          dedaPhone: widget.dedaPhone,
          isArabic: widget.isArabic,
          collection: 'admin_audit',
        ),
      );
    }
    if (can('viewTeam')) {
      addDestination(
        title: t('فريق الإدارة', 'Admin team'),
        subtitle: t('الأعضاء والصلاحيات', 'Members and permissions'),
        icon: Icons.groups_2_outlined,
        accentColor: const Color(0xFF2F6B8A),
        page: _DedaIsolatedReadOnlyTab(
          admin: widget.admin,
          dedaPhone: widget.dedaPhone,
          isArabic: widget.isArabic,
          collection: 'admins',
        ),
      );
      addDestination(
        title: t('الدعوات الإدارية', 'Admin invitations'),
        subtitle: t('الدعوات والتفعيل والإلغاء', 'Invites and activation'),
        icon: Icons.mail_outline,
        accentColor: const Color(0xFF17652F),
        page: _DedaIsolatedReadOnlyTab(
          admin: widget.admin,
          dedaPhone: widget.dedaPhone,
          isArabic: widget.isArabic,
          collection: 'admin_invites',
        ),
      );
      staffRecoveryTabIndex = tabs.length + 1;
      addDestination(
        title: t('طلبات استرجاع الموظفين', 'Staff recovery'),
        subtitle: t('مراجعة الطلبات الموثوقة', 'Review verified requests'),
        icon: Icons.lock_reset,
        accentColor: const Color(0xFF9A6700),
        page: _DedaIsolatedReadOnlyTab(
          admin: widget.admin,
          dedaPhone: widget.dedaPhone,
          isArabic: widget.isArabic,
          collection: 'admin_recovery_requests',
        ),
      );
      addDestination(
        title: t('أرقام دخول المدير', 'Manager entry phones'),
        subtitle: t('البوابات المصرح بها', 'Approved access gateways'),
        icon: Icons.phonelink_lock,
        accentColor: const Color(0xFF6A4C93),
        page: _DedaIsolatedManagerGatewaysTab(
          admin: widget.admin,
          dedaPhone: widget.dedaPhone,
          isArabic: widget.isArabic,
        ),
      );
    }
    if (can('managePlaceArchives')) {
      for (final config in <(String, String, String)>[
        ('published_places', 'أماكن منشورة', 'Published places'),
        ('admin_trash_place_requests', 'محذوفات الطلبات', 'Request trash'),
        ('admin_trash_places', 'محذوفات الأماكن', 'Place trash'),
      ]) {
        addDestination(
          title: t(config.$2, config.$3),
          subtitle: t('إدارة الأماكن والسجلات', 'Places and records'),
          icon: config.$1 == 'published_places'
              ? Icons.place_outlined : Icons.delete_outline,
          accentColor: const Color(0xFF7A5A2B),
          page: _DedaIsolatedManagerPlacesTab(
            admin: widget.admin,
            dedaPhone: widget.dedaPhone,
            isArabic: widget.isArabic,
            sourceCollection: config.$1,
          ),
        );
      }
    }
    if (can('viewReports')) {
      addDestination(
        title: t('التقارير', 'Analytics'),
        subtitle: t('البلاغات النشطة ونطاق الصلاحيات',
            'Active road reports and access scope'),
        icon: Icons.analytics_outlined,
        accentColor: const Color(0xFF6F4E8C),
        page: _DedaIsolatedAdminReportsTab(
          admin: widget.admin,
          dedaPhone: widget.dedaPhone,
          isArabic: widget.isArabic,
        ),
      );
    }
    // Historical Road Reports: list, refresh, and privileged deletion.
    if (can('viewReports')) {
      addDestination(
        title: t('البلاغات', 'Reports'),
        subtitle: t('بلاغات الطريق الحالية', 'Current road reports'),
        icon: Icons.report_gmailerrorred_outlined,
        accentColor: const Color(0xFFB35C00),
        page: _DedaIsolatedRoadReportsTab(
          admin: widget.admin,
          dedaPhone: widget.dedaPhone,
          isArabic: widget.isArabic,
          profile: profile,
        ),
      );
    }
    // Historical Governorates: read-only coverage and account scope.
    if (can('viewGovernorates')) {
      addDestination(
        title: t('المحافظات', 'Governorates'),
        subtitle: t('نطاق عمل الوكلاء', 'Agent coverage'),
        icon: Icons.map_outlined,
        accentColor: const Color(0xFF5F6F2E),
        page: _DedaIsolatedGovernoratesTab(
          admin: widget.admin,
          dedaPhone: widget.dedaPhone,
          isArabic: widget.isArabic,
        ),
      );
    }
    // Private owner 100-ID card: no public Auth or local catalog.
    if (can('managePlaceArchives') &&
        profile['role'] == 'general_manager') {
      addDestination(
        title: t('إدارة المعرّفات الحصرية', 'Exclusive ID management'),
        subtitle: t('الـ100 • الألوان • المنح • السجل',
            '100 IDs • colors • grants • history'),
        icon: Icons.verified_user_outlined,
        // Original Stage19 palette (navy/turquoise), not generic teal.
        accentColor: const Color(0xFF103E50),
        exclusiveNavyTurquoise: true,
        page: DedaStage2IsolatedExclusiveIdsAdminPage(
          admin:widget.admin,dedaPhone:widget.dedaPhone,
          isArabic:widget.isArabic),
      );
    }
    // Original \"🏆 الرابحون معنا\" (not the weekly-league payout report).
    if (can('reviewPrizeWinners') &&
        profile['role'] == 'general_manager') {
      addDestination(
        title: t('🏆 الرابحون معنا', '🏆 Prize winners'),
        subtitle: t('طلبات الفوز والتدقيق وتسليم الجوائز',
            'Prize claims, review and delivery'),
        icon: Icons.emoji_events_outlined,
        accentColor: const Color(0xFF9A7415),
        page: _DedaIsolatedPrizeWinnersTab(
          admin:widget.admin, dedaPhone:widget.dedaPhone,
          isArabic:widget.isArabic,
        ),
      );
    }
    // Original weekly league card, never prize_v1 winners.
    // One destination with independently authorized actions and read-only prizes.
    if (can('manageLeague') &&
        profile['role'] == 'general_manager') {
      addDestination(
        title: t('إدارة الدوري', 'League management'),
        subtitle: t('المتصدرون • التحكم • الأرشيف • الجوائز',
            'Standings • controls • archive • prizes'),
        icon: Icons.leaderboard_outlined,
        accentColor: const Color(0xFF133F65),
        page: DedaStage2IsolatedLeagueAdminPage(
          admin: widget.admin, dedaPhone: widget.dedaPhone,
          isArabic: widget.isArabic),
      );
    }
    // Original 1D7690 manager task tile; same eight slots and local login
    // offers, backed only by the independent administrator identity.
    if (can('viewTeam') && profile['role'] == 'general_manager') {
      addDestination(
        title:t('إدارة المهام والمكافآت','Tasks & rewards'),
        subtitle:t('المهام اليومية فقط','Daily tasks only'),
        icon:Icons.assignment_outlined,
        accentColor:const Color(0xFF1D7690),
        page:DedaStage2IsolatedTasksAdminPage(
          admin:widget.admin,dedaPhone:widget.dedaPhone,
          isArabic:widget.isArabic),
      );
    }
    // Original owner place deletion: archive, removal, notice and audit.
    if (can('managePlaceArchives') &&
        profile['role'] == 'general_manager') {
      addDestination(
        title: t('طلبات حذف الأماكن', 'Place deletion requests'),
        subtitle: t('المالك • المحذوفات • الإشعار • التدقيق',
            'Owner • archive • notice • audit'),
        icon: Icons.location_off_outlined,
        accentColor: const Color(0xFF9D4035),
        page: _DedaIsolatedPlaceDeletionTab(
          admin: widget.admin,
          dedaPhone: widget.dedaPhone,
          isArabic: widget.isArabic,
        ),
      );
    }
    // Account deletion requests: review status only, not user deletion.
    if (can('reviewAccountDeletions') &&
        profile['role'] == 'general_manager') {
      addDestination(
        title: t('طلبات حذف الحساب', 'Account deletion'),
        subtitle: t('الطلبات والقرارات المسجلة', 'Requests and audited decisions'),
        icon: Icons.person_remove_alt_1_outlined,
        accentColor: const Color(0xFFA3463C),
        page: _DedaIsolatedAccountDeletionTab(
          admin: widget.admin, dedaPhone: widget.dedaPhone,
          isArabic: widget.isArabic,
        ),
      );
    }
    // Settings belongs to every server-verified admin, not to viewTeam
    // or another elevated permission. Its destination re-checks Auth + UID.
    addDestination(
      title: t('الإعدادات', 'Settings'),
      subtitle: t('بيانات الحساب الإداري وتعديل الاسم',
          'Admin profile and name'),
      icon: Icons.settings_outlined,
      accentColor: const Color(0xFF5B6770),
      page: _DedaIsolatedAdminSettingsTab(
        admin: widget.admin,
        dedaPhone: widget.dedaPhone,
        isArabic: widget.isArabic,
      ),
    );
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop) await _exit();
      },
      child: DefaultTabController(
        key: ValueKey('deda_stage2_admin_refresh_$_refreshEpoch'),
        length: tabs.isEmpty ? 0 : tabs.length + 1,
        child: Scaffold(
          appBar: AppBar(
            title: Text(t('إدارة DEDA', 'DEDA administration')),
            actions: [
              if (staffRecoveryTabIndex != null &&
                  profile['role'] == 'general_manager')
                Builder(builder: (headerContext) => StreamBuilder<int>(
                  stream: _staffRecoveryStream,
                  builder: (context, snapshot) {
                    // Unknown/error isn't zero; show no count until server
                    // confirms the exact pending request count.
                    final count = snapshot.hasData ? snapshot.data : null;
                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        IconButton(
                          tooltip: t('طلبات استرجاع دخول الموظفين',
                              'Staff sign-in recovery requests'),
                          icon: const Icon(Icons.mail_outline),
                          onPressed: () => DefaultTabController.of(
                            headerContext,
                          ).animateTo(staffRecoveryTabIndex!),
                        ),
                        if (count != null && count > 0)
                          PositionedDirectional(
                            top: 5, end: 4,
                            child: Container(
                              constraints: const BoxConstraints(
                                minWidth: 18, minHeight: 18,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              decoration: const BoxDecoration(
                                color: Color(0xFFB3261E),
                                shape: BoxShape.circle,
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                count > 99 ? '99+' : count.toString(),
                                style: const TextStyle(
                                  color: Colors.white, fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                )),
              IconButton(
                tooltip: t('تحديث', 'Refresh'),
                icon: _refreshing
                    ? const Icon(Icons.sync) : const Icon(Icons.refresh),
                onPressed: _refreshing ? null : _refreshDashboard,
              ),
              IconButton(
                tooltip: t('تسجيل خروج الإدارة', 'Admin sign out'),
                icon: const Icon(Icons.logout),
                onPressed: _exit,
              ),
            ],
            bottom: tabs.isEmpty
                ? null
                : TabBar(
                    isScrollable: true,
                    tabs: [Tab(text: t('الرئيسية', 'Overview')), ...tabs],
                  ),
          ),
          body: tabs.isEmpty
              ? Center(child: Text(t(
                  'لا توجد صلاحيات إدارية متاحة لهذا الحساب.',
                  'No available administrative permissions.',
                )))
              : TabBarView(children: [
                  // One overview, using the EXACT legacy compact-card widget.
                  // Tap selects the already registered tab; it never bypasses
                  // that tab's server-side reauthorization.
                  Builder(builder: (overviewContext) =>
                    LayoutBuilder(builder: (context, constraints) {
                      final width = constraints.maxWidth;
                      final count = width >= 980 ? 6
                          : width >= 740 ? 5
                          : width >= 590 ? 4 : 3;
                      final extent =
                          (126 * MediaQuery.textScalerOf(context).scale(1.0))
                              .clamp(126.0, 240.0).toDouble();
                      return GridView.builder(
                        key: const Key('deda_stage2_admin_card_hub'),
                        padding: const EdgeInsets.all(10),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: count,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                          mainAxisExtent: extent,
                        ),
                        itemCount: tabs.length,
                        itemBuilder: (context, index) => DedaAdminCompactCard(
                          key: ValueKey('deda_stage2_admin_card_$index'),
                          icon: cardIcons[index],
                          title: tabs[index].text ?? '',
                          subtitle: cardSubtitles[index],
                          accentColor: cardColors[index],
                          exclusiveNavyTurquoise: cardExclusivePalettes[index],
                          onTap: () => DefaultTabController.of(overviewContext)
                              .animateTo(index + 1),
                        ),
                      );
                    }),
                  ),
                  ...pages,
                ]),
        ),
      ),
    );
  }
}

/// Complete original Governorates card: one fresh permission-scoped
/// account profile, same canonical province list (not a duplicated list).
class _DedaIsolatedGovernoratesTab extends StatefulWidget {
  final DedaIsolatedAdminIdentity admin;
  final String dedaPhone;
  final bool isArabic;

  const _DedaIsolatedGovernoratesTab({
    required this.admin,
    required this.dedaPhone,
    required this.isArabic,
  });

  @override
  State<_DedaIsolatedGovernoratesTab> createState() =>
      _DedaIsolatedGovernoratesTabState();
}

class _DedaIsolatedGovernoratesTabState
    extends State<_DedaIsolatedGovernoratesTab> {
  late Future<Map<String, dynamic>> _profile;

  String t(String ar, String en) => widget.isArabic ? ar : en;

  @override
  void initState() {
    super.initState();
    _profile = widget.admin.readScopedAdminGovernorateScope(
      dedaPhone: widget.dedaPhone,
    );
  }

  void _refresh() => setState(() => _profile =
      widget.admin.readScopedAdminGovernorateScope(
        dedaPhone: widget.dedaPhone,
      ));

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _profile,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: TextButton.icon(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
            label: Text(t('تعذر تأكيد نطاق المحافظة، أعد المحاولة',
                'Cannot verify governorate scope, retry')),
          ));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final profile = snapshot.data!;
        final province = (profile['governorate'] ?? '').toString().trim();
        final restricted = profile['role'] == 'province_agent';
        // Fail closed instead of listing every province to a malformed agent.
        if (restricted && province.isEmpty) {
          return Center(child: Text(t('نطاق المحافظة غير مثبت.',
              'Governorate scope is not verified.')));
        }
        final names = restricted ? <String>[province] : dedaAdminGovernorates;
        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: IconButton(
                tooltip: t('تحديث من الخادم', 'Refresh from server'),
                onPressed: _refresh,
                icon: const Icon(Icons.refresh),
              ),
            ),
            if (restricted)
              Card(
                color: const Color(0xFFE6F1E4),
                child: ListTile(
                  leading: const Icon(Icons.location_on_outlined),
                  title: Text(t('نطاق حسابك', 'Your account scope')),
                  subtitle: Text(province),
                ),
              ),
            ...names.map((name) => Card(
              child: ListTile(
                leading: const Icon(Icons.location_city_outlined),
                title: Text(name),
                trailing: restricted && name == province
                    ? const Icon(Icons.verified, color: Color(0xFF17652F))
                    : null,
              ),
            )),
          ],
        );
      },
    );
  }
}

/// Complete original Road Reports card: original row counts and reasoned
/// deletion. All operations use the isolated identity and re-check the
/// server role; the visible button is never the authorization boundary.
class _DedaIsolatedRoadReportsTab extends StatefulWidget {
  final DedaIsolatedAdminIdentity admin;
  final String dedaPhone;
  final bool isArabic;
  final Map<String, dynamic> profile;

  const _DedaIsolatedRoadReportsTab({
    required this.admin,
    required this.dedaPhone,
    required this.isArabic,
    required this.profile,
  });

  @override
  State<_DedaIsolatedRoadReportsTab> createState() =>
      _DedaIsolatedRoadReportsTabState();
}

class _DedaIsolatedRoadReportsTabState
    extends State<_DedaIsolatedRoadReportsTab> {
  late Future<List<Map<String, dynamic>>> _reports;
  bool _busy = false;

  String t(String ar, String en) => widget.isArabic ? ar : en;

  @override
  void initState() {
    super.initState();
    _reports = _load();
  }

  Future<List<Map<String, dynamic>>> _load() =>
      widget.admin.readScopedAdminRoadReports(
        dedaPhone: widget.dedaPhone,
      );

  void _refresh() {
    if (_busy) return;
    setState(() => _reports = _load());
  }

  Future<void> _delete(Map<String, dynamic> item) async {
    if (_busy) return;
    final id = (item['id'] ?? '').toString();
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(t('حذف البلاغ', 'Delete report')),
        content: TextField(
          controller: controller,
          maxLength: 500,
          minLines: 1,
          maxLines: 4,
          decoration: InputDecoration(
            labelText: t('سبب الحذف', 'Reason'),
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: Text(t('إلغاء', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, controller.text),
            child: Text(t('حذف', 'Delete')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (reason == null || !mounted) return;
    if (reason.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(t('سبب الحذف مطلوب.', 'Deletion reason required.')),
      ));
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.admin.deleteScopedRoadHazardAsAdmin(
        dedaPhone: widget.dedaPhone,
        id: id,
        reason: reason,
      );
      if (mounted) {
        setState(() => _reports = _load());
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(t('تعذر حذف البلاغ أو تأكيد الصلاحية.',
              'Could not delete report or verify permission.')),
        ));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canManage = DedaIsolatedAdminProofPolicy.allowsPermission(
      admin: widget.profile,
      permission: 'manageReports',
    ) && widget.profile['role'] != 'province_agent';
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _reports,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: TextButton.icon(
            onPressed: _busy ? null : _refresh,
            icon: const Icon(Icons.refresh),
            label: Text(t('تعذر تحميل البلاغات، أعد المحاولة',
                'Could not load reports, retry')),
          ));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final rows = snapshot.data!;
        return Column(children: [
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: IconButton(
              tooltip: t('تحديث', 'Refresh'),
              onPressed: _busy ? null : _refresh,
              icon: const Icon(Icons.refresh),
            ),
          ),
          Expanded(
            child: rows.isEmpty
                ? Center(child: Text(t('لا توجد بلاغات نشطة.',
                    'No active reports.')))
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: rows.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final item = rows[index];
                      return Card(child: ListTile(
                        leading: const Icon(Icons.warning_amber_rounded),
                        title: Text((item['type'] ??
                            t('بلاغ طريق', 'Road report')).toString()),
                        subtitle: Text(
                          '${t('التأكيدات: ', 'Confirmations: ')}'
                          '${item['confirmations'] ?? 0}'
                          ' • ${t('طلبات الإلغاء: ', 'Resolve reports: ')}'
                          '${item['resolvedReports'] ?? 0}',
                        ),
                        trailing: canManage ? IconButton(
                          tooltip: t('حذف البلاغ', 'Delete report'),
                          onPressed: _busy ? null : () => _delete(item),
                          icon: const Icon(Icons.delete_outline),
                        ) : null,
                      ));
                    },
                  ),
          ),
        ]);
      },
    );
  }
}

/// Isolated equivalent of legacy Analytics (two original read-only tiles).
/// It never reads road hazards through the public account.
class _DedaIsolatedAdminReportsTab extends StatefulWidget {
  final DedaIsolatedAdminIdentity admin;
  final String dedaPhone;
  final bool isArabic;

  const _DedaIsolatedAdminReportsTab({
    required this.admin,
    required this.dedaPhone,
    required this.isArabic,
  });

  @override
  State<_DedaIsolatedAdminReportsTab> createState() =>
      _DedaIsolatedAdminReportsTabState();
}

class _DedaIsolatedAdminReportsTabState
    extends State<_DedaIsolatedAdminReportsTab> {
  late Future<Map<String, dynamic>> _summary;

  String t(String ar, String en) => widget.isArabic ? ar : en;

  @override
  void initState() {
    super.initState();
    _summary = _load();
  }

  Future<Map<String, dynamic>> _load() =>
      widget.admin.readScopedAdminRoadReportSummary(
        dedaPhone: widget.dedaPhone,
      );

  void _refresh() => setState(() => _summary = _load());

  String _scope(Map<String, dynamic> summary) {
    final role = (summary['role'] ?? '').toString();
    if (role == 'province_agent') {
      final province = (summary['governorate'] ?? '—').toString();
      return t('محافظة: ', 'Province: ') + province;
    }
    switch (role) {
      case 'general_manager':
        return t('المدير العام', 'General manager');
      case 'deputy_manager':
        return t('معاون المدير', 'Deputy manager');
      case 'employee':
        return t('موظف', 'Employee');
      default:
        return role.isEmpty ? '—' : role;
    }
  }

  @override
  Widget build(BuildContext context) {
    // This tab is constructed only by the original Stage2 flag-closed
    // dashboard. The isolated reader fails closed until enabled.
    return FutureBuilder<Map<String, dynamic>>(
      future: _summary,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: TextButton.icon(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
            label: Text(t('تعذر تأكيد صلاحية التقارير، أعد المحاولة',
                'Report permission verification failed, retry')),
          ));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final summary = snapshot.data!;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: IconButton(
                tooltip: t('تحديث من الخادم', 'Refresh from server'),
                onPressed: _refresh,
                icon: const Icon(Icons.refresh),
              ),
            ),
            Card(child: ListTile(
              leading: const Icon(Icons.report_outlined,
                  color: Color(0xFF17652F)),
              title: Text(t('البلاغات النشطة', 'Active road reports')),
              trailing: Text(
                (summary['activeReports'] ?? 0).toString(),
                style: const TextStyle(
                    fontWeight: FontWeight.w900, fontSize: 22),
              ),
            )),
            Card(child: ListTile(
              leading: const Icon(Icons.security_outlined,
                  color: Color(0xFF17652F)),
              title: Text(t('نطاق صلاحياتك', 'Your access scope')),
              subtitle: Text(_scope(summary)),
            )),
          ],
        );
      },
    );
  }
}

/// Faithful isolated counterpart of the existing Admin Settings tile:
/// name edit + email/role/status/last-login, without public Auth/Firestore or
/// SharedPreferences writes. All reads and writes re-check secondary Auth.
class _DedaIsolatedAdminSettingsTab extends StatefulWidget {
  final DedaIsolatedAdminIdentity admin;
  final String dedaPhone;
  final bool isArabic;

  const _DedaIsolatedAdminSettingsTab({
    required this.admin,
    required this.dedaPhone,
    required this.isArabic,
  });

  @override
  State<_DedaIsolatedAdminSettingsTab> createState() =>
      _DedaIsolatedAdminSettingsTabState();
}

class _DedaIsolatedAdminSettingsTabState
    extends State<_DedaIsolatedAdminSettingsTab> {
  late Future<Map<String, dynamic>> _freshProfile;
  bool _busy = false;

  String t(String ar, String en) => widget.isArabic ? ar : en;

  @override
  void initState() {
    super.initState();
    _freshProfile = _read();
  }

  Future<Map<String, dynamic>> _read() =>
      widget.admin.readVerifiedAdminProfile(dedaPhone: widget.dedaPhone);

  void _refresh() {
    if (_busy) return;
    setState(() => _freshProfile = _read());
  }

  String _role(dynamic role) {
    switch ((role ?? '').toString()) {
      case 'general_manager':
        return t('المدير العام', 'General manager');
      case 'deputy_manager':
        return t('معاون المدير', 'Deputy manager');
      case 'province_agent':
        return t('وكيل محافظة', 'Province agent');
      case 'employee':
        return t('موظف', 'Employee');
      default:
        return (role ?? '').toString();
    }
  }

  String _status(dynamic status) {
    switch ((status ?? '').toString()) {
      case 'active':
        return t('نشط', 'Active');
      case 'temporarily_stopped':
        return t('متوقف مؤقتاً', 'Temporarily stopped');
      case 'disabled':
        return t('معطّل', 'Disabled');
      default:
        return (status ?? '').toString();
    }
  }

  String _timestamp(dynamic raw) {
    final DateTime? value = raw is Timestamp ? raw.toDate()
        : raw is DateTime ? raw : null;
    return value == null
        ? '—' : value.toLocal().toString().split('.').first;
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _editName(Map<String, dynamic> verified) async {
    if (_busy) return;
    final name = (verified['displayName'] ??
        verified['name'] ?? '').toString().trim();
    final controller = TextEditingController(text: name);
    final candidate = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(t('تعديل الاسم الإداري', 'Edit admin name')),
        content: TextField(
          controller: controller,
          maxLength: 100,
          autofocus: true,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            labelText: t('الاسم الكامل', 'Full name'),
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (value) => Navigator.of(dialog).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(),
            child: Text(t('إلغاء', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialog).pop(controller.text),
            child: Text(t('حفظ', 'Save')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (!mounted || candidate == null) return;
    final clean = candidate.trim();
    if (clean.length < 2 || clean.length > 100) {
      _message(t('اكتب اسماً واضحاً من حرفين إلى 100 حرف.',
          'Use a name of 2 to 100 characters.'));
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.admin.updateScopedOwnAdminDisplayName(
        dedaPhone: widget.dedaPhone,
        displayName: clean,
      );
      if (!mounted) return;
      // Do not persist a local optimistic profile. Fetch fresh proof again.
      setState(() => _freshProfile = _read());
      _message(t('تم تحديث الاسم الإداري.', 'Admin name updated.'));
    } catch (_) {
      _message(t('تعذر تحديث الاسم أو التحقق من صلاحية الإدارة.',
          'Could not update name or verify admin access.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // This private tab exists only under the already flag-gated Dashboard.
    // The isolated identity's read/write methods independently enforce OFF.
    return FutureBuilder<Map<String, dynamic>>(
      future: _freshProfile,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: TextButton.icon(
            onPressed: _busy ? null : _refresh,
            icon: const Icon(Icons.refresh),
            label: Text(t('تعذر تأكيد الحساب، أعد المحاولة',
                'Profile verification failed, retry')),
          ));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final profile = snapshot.data!;
        final email = (profile['email'] ?? '').toString().trim();
        final name = (profile['displayName'] ??
            profile['name'] ?? '').toString().trim();
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: IconButton(
                tooltip: t('تحديث من الخادم', 'Refresh from server'),
                onPressed: _busy ? null : _refresh,
                icon: const Icon(Icons.refresh),
              ),
            ),
            Card(child: Column(children: [
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: Text(t('الاسم', 'Name')),
                subtitle: Text(name.isEmpty ? '—' : name),
                trailing: IconButton(
                  tooltip: t('تعديل الاسم', 'Edit name'),
                  onPressed: _busy ? null : () => _editName(profile),
                  icon: const Icon(Icons.edit_outlined),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.email_outlined),
                title: Text(t('البريد', 'Email')),
                subtitle: Directionality(
                  textDirection: TextDirection.ltr,
                  child: Text(email.isEmpty ? '—' : email),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.badge_outlined),
                title: Text(t('الدور', 'Role')),
                subtitle: Text(_role(profile['role'])),
              ),
              ListTile(
                leading: const Icon(Icons.toggle_on_outlined),
                title: Text(t('حالة الحساب', 'Account status')),
                subtitle: Text(_status(profile['status'])),
              ),
              ListTile(
                leading: const Icon(Icons.schedule),
                title: Text(t('آخر دخول', 'Last sign-in')),
                subtitle: Text(_timestamp(profile['lastLoginAt'] ??
                    profile['lastSeenAt'])),
              ),
            ])),
          ],
        );
      },
    );
  }
}

/// GM queue using only isolated Auth. Does not delete Firebase user accounts.
class _DedaIsolatedAccountDeletionTab extends StatefulWidget {
  final DedaIsolatedAdminIdentity admin;
  final String dedaPhone;
  final bool isArabic;
  const _DedaIsolatedAccountDeletionTab({
    required this.admin, required this.dedaPhone, required this.isArabic,
  });
  @override
  State<_DedaIsolatedAccountDeletionTab> createState() =>
      _DedaIsolatedAccountDeletionTabState();
}

class _DedaIsolatedAccountDeletionTabState
    extends State<_DedaIsolatedAccountDeletionTab> {
  late Future<DedaIsolatedManagerPage> _page;
  QueryDocumentSnapshot<Map<String, dynamic>>? _cursor;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>?> _back = [];
  bool _busy = false;
  String _filter = 'all';
  String t(String ar, String en) => widget.isArabic ? ar : en;
  String _statusLabel(String status) => switch (status) {
    'new' => t('جديد', 'New'),
    'reviewing' => t('قيد المراجعة', 'Under review'),
    'deleted' => t('تم تسجيل الحذف', 'Deletion recorded'),
    'cancelled' => t('ملغي', 'Cancelled'),
    'rejected' => t('مرفوض', 'Rejected'),
    _ => t('حالة غير معروفة', 'Unknown status'),
  };
  bool _matchesStatus(String status) =>
      _filter == 'all' ||
      (_filter == 'closed' &&
        (status == 'cancelled' || status == 'rejected')) ||
      _filter == status;
  Widget _filterChip(String value, String ar, String en) => ChoiceChip(
    label: Text(t(ar, en)), selected: _filter == value,
    onSelected: _busy ? null : (_) => setState(() => _filter = value),
  );
  @override
  void initState() { super.initState(); _page = _load(); }
  Future<DedaIsolatedManagerPage> _load() =>
      widget.admin.readScopedAccountDeletionPage(
        dedaPhone: widget.dedaPhone, startAfter: _cursor);
  void _refresh() {
    setState(() { _cursor = null; _back.clear(); _page = _load(); });
  }
  Future<void> _review(Map<String, dynamic> row) async {
    if (_busy) return;
    final id = (row['id'] ?? '').toString();
    final choices = DedaIsolatedAdminProofPolicy
        .accountDeletionAllowedTransitions(
          (row['status'] ?? '').toString());
    if (choices.isEmpty) return;
    String status = choices.first;
    final reason = TextEditingController();
    final confirmation = TextEditingController();
    final picked = await showDialog<({String status, String reason})>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (dialog, update) => AlertDialog(
          title: Text(t('مراجعة طلب حذف الحساب', 'Review deletion request')),
          content: SingleChildScrollView(child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(id),
              DropdownButtonFormField<String>(
                initialValue: status,
                items: choices.map((s) => DropdownMenuItem(
                  value: s, child: Text(_statusLabel(s)),
                )).toList(),
                onChanged: (value) {
                  if (value != null) update(() => status = value);
                },
              ),
              TextField(
                controller: reason, maxLength: 500,
                onChanged: (_) => update(() {}),
                decoration: InputDecoration(labelText:
                    t('سبب القرار (3 أحرف على الأقل)', 'Reason (3+ characters)')),
              ),
              if (status == 'deleted') ...[
                Text(t(
                    'سجّل «تم الحذف» فقط بعد تنفيذ حذف الحساب فعلياً '
                    'خارج هذه الشاشة. هنا نسجّل حالة الطلب فقط ولا نحذف '
                    'المستخدم. اكتب معرّف الطلب للتأكيد.',
                    'Only mark Deleted after actual account deletion outside '
                    'this screen. This records request status only and does '
                    'not delete the user. Type request ID to confirm.')),
                TextField(controller: confirmation,
                  onChanged: (_) => update(() {}),
                  decoration: InputDecoration(labelText: t(
                      'تأكيد معرّف الطلب', 'Confirm request ID'))),
              ],
            ],
          )),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialog),
              child: Text(t('إلغاء', 'Cancel'))),
            FilledButton(
              onPressed: reason.text.trim().length < 3 ||
                  status == row['status'] ||
                  (status == 'deleted' && confirmation.text.trim() != id)
                  ? null : () => Navigator.pop(dialog,
                      (status: status, reason: reason.text.trim())),
              child: Text(t('تسجيل القرار', 'Record decision')),
            ),
          ],
        ),
      ),
    );
    reason.dispose();
    confirmation.dispose();
    if (!mounted || picked == null || _busy) return;
    setState(() => _busy = true);
    try {
      await widget.admin.reviewScopedAccountDeletionRequest(
        dedaPhone: widget.dedaPhone, requestId: id,
        status: picked.status, reason: picked.reason);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(t('تم تسجيل القرار', 'Decision recorded'))));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(t('تعذر القرار أو تغيرت الصلاحية',
              'Decision denied or permissions changed'))));
      }
    } finally {
      if (mounted) { setState(() => _busy = false); _refresh(); }
    }
  }
  @override
  Widget build(BuildContext context) => FutureBuilder<DedaIsolatedManagerPage>(
    future: _page,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Center(child: CircularProgressIndicator());
      }
      if (snapshot.hasError || !snapshot.hasData) {
        return Center(child: TextButton(onPressed: _busy ? null : _refresh,
          child: Text(t('تعذر تأكيد الصلاحية، أعد المحاولة',
              'Access denied, retry'))));
      }
      final page = snapshot.data!;
      final visible = page.rows.where((record) => _matchesStatus(
          (record['status'] ?? 'new').toString())).toList(growable: false);
      return Column(children: [
        Padding(
          padding: const EdgeInsets.all(10),
          child: Text(t(
            'تنبيه: لا تسجّل «تم الحذف» إلا بعد تنفيذ حذف الحساب '
            'فعلياً. هذه البطاقة للمراجعة والتوثيق فقط.',
            'Only mark Deleted after the account was actually removed. '
            'This card records review decisions only.',
          )),
        ),
        Wrap(spacing: 6, children: [
          _filterChip('all', 'الكل', 'All'),
          _filterChip('new', 'جديد', 'New'),
          _filterChip('reviewing', 'قيد المراجعة', 'Reviewing'),
          _filterChip('deleted', 'تم الحذف', 'Deleted'),
          _filterChip('closed', 'مغلق/مرفوض', 'Closed'),
        ]),
        Align(alignment: AlignmentDirectional.centerEnd,
          child: IconButton(
            onPressed: _busy ? null : _refresh,
            icon: const Icon(Icons.refresh))),
        Expanded(child: ListView.builder(
          itemCount: visible.length,
          itemBuilder: (context, index) {
            final row = visible[index];
            return Card(child: ListTile(
              title: Text((row['name'] ?? '').toString()),
              subtitle: Text(
                '${row['id'] ?? ''} • ${row['phone'] ?? ''} • '
                '${_statusLabel((row['status'] ?? '').toString())}\n'
                '${row['reason'] ?? ''}\n${row['reviewNote'] ?? ''}',
              ),
              trailing: IconButton(icon: const Icon(Icons.fact_check_outlined),
                onPressed: _busy || DedaIsolatedAdminProofPolicy
                    .accountDeletionAllowedTransitions(
                      (row['status'] ?? '').toString()).isEmpty
                    ? null : () => _review(row)),
            ));
          },
        )),
        Row(children: [
          Text((_back.length + 1).toString()),
          const Spacer(),
          TextButton(
            onPressed: !_busy && _back.isNotEmpty ? () {
              setState(() {
                _cursor = _back.removeLast();
                _page = _load();
              });
            } : null,
            child: Text(t('السابق', 'Previous'))),
          TextButton(
            onPressed: !_busy && page.nextCursor != null ? () {
              setState(() {
                _back.add(_cursor);
                _cursor = page.nextCursor;
                _page = _load();
              });
            } : null,
            child: Text(t('التالي', 'Next'))),
        ]),
      ]);
    },
  );
}

/// The original owner-requested place deletion card under isolated admin Auth.
class _DedaIsolatedPlaceDeletionTab extends StatefulWidget {
  final DedaIsolatedAdminIdentity admin;
  final String dedaPhone;
  final bool isArabic;
  const _DedaIsolatedPlaceDeletionTab({
    required this.admin, required this.dedaPhone, required this.isArabic,
  });
  @override
  State<_DedaIsolatedPlaceDeletionTab> createState() =>
      _DedaIsolatedPlaceDeletionTabState();
}

class _DedaIsolatedPlaceDeletionTabState
    extends State<_DedaIsolatedPlaceDeletionTab> {
  late Future<DedaIsolatedManagerPage> _page;
  QueryDocumentSnapshot<Map<String, dynamic>>? _cursor;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>?> _back = [];
  bool _busy = false;
  String _filter = 'all';
  String t(String ar, String en) => widget.isArabic ? ar : en;
  String _label(String status) => switch (status) {
    'new' => t('جديد', 'New'),
    'reviewing' => t('قيد المراجعة', 'Reviewing'),
    'deleted' => t('تم حذف المكان', 'Place deleted'),
    'rejected' => t('مرفوض', 'Rejected'),
    'cancelled' => t('ملغي', 'Cancelled'),
    _ => t('غير معروف', 'Unknown'),
  };
  bool _matches(Map<String, dynamic> row) {
    final status = (row['status'] ?? 'new').toString();
    return _filter == 'all' || status == _filter ||
        (_filter == 'closed' &&
          (status == 'rejected' || status == 'cancelled'));
  }
  @override
  void initState() { super.initState(); _page = _fetch(); }
  Future<DedaIsolatedManagerPage> _fetch() =>
      widget.admin.readScopedPlaceDeletionPage(
        dedaPhone: widget.dedaPhone, startAfter: _cursor);
  void _refresh() {
    if (_busy) return;
    setState(() { _cursor = null; _back.clear(); _page = _fetch(); });
  }
  void _previous() {
    if (_busy || _back.isEmpty) return;
    setState(() { _cursor = _back.removeLast(); _page = _fetch(); });
  }
  void _next(DedaIsolatedManagerPage page) {
    if (_busy || page.nextCursor == null) return;
    setState(() { _back.add(_cursor); _cursor = page.nextCursor;
      _page = _fetch(); });
  }
  Future<void> _decide(Map<String, dynamic> row, String status) async {
    if (_busy) return;
    final id = (row['id'] ?? '').toString();
    if (!DedaIsolatedAdminProofPolicy.placeDeletionAllowedTransitions(
        (row['status'] ?? '').toString()).contains(status)) {
      return;
    }
    final reason = TextEditingController();
    final confirm = TextEditingController();
    final destructive = status == 'deleted';
    final choice = await showDialog<String>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (dialog, update) => AlertDialog(
          title: Text(destructive
              ? t('اعتماد وحذف المكان', 'Approve place deletion')
              : status == 'rejected'
                  ? t('رفض طلب الحذف', 'Reject request')
                  : t('بدء مراجعة الطلب', 'Start review')),
          content: SingleChildScrollView(child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('${t('معرّف المكان', 'Place ID')}: $id'),
              Text('${row['placeName'] ?? ''} • ${row['approvalNumber'] ?? ''}'),
              if (destructive) ...[
                Text(t(
                  'هذا الحذف ينقل المكان إلى محذوفات المدير العام ويزيله '
                  'من الخريطة ويبلغ المالك، دون حذف حسابه. '
                  'اكتب معرّف المكان للتأكيد.',
                  'This archives and removes the place, notifies the owner, '
                  'but does not delete their account. Type the place ID.',
                )),
                TextField(controller: confirm, onChanged: (_) => update(() {}),
                  decoration: InputDecoration(labelText: t(
                    'تأكيد معرّف المكان', 'Confirm place ID'))),
              ],
              TextField(controller: reason, maxLength: 500,
                onChanged: (_) => update(() {}),
                decoration: InputDecoration(labelText: t(
                    'سبب القرار (3 أحرف على الأقل)', 'Reason (at least 3 characters)'))),
            ],
          )),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialog),
                child: Text(t('إلغاء', 'Cancel'))),
            FilledButton(
              onPressed: reason.text.trim().length < 3 ||
                  (destructive && confirm.text.trim() != id)
                  ? null : () => Navigator.pop(dialog, reason.text.trim()),
              child: Text(t('تأكيد', 'Confirm')),
            ),
          ],
        ),
      ),
    );
    reason.dispose();
    confirm.dispose();
    if (!mounted || choice == null || _busy) return;
    setState(() => _busy = true);
    try {
      await widget.admin.reviewScopedPlaceDeletionRequest(
        dedaPhone: widget.dedaPhone, requestId: id,
        status: status, note: choice,
        confirmation: destructive ? id : null,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(status == 'deleted'
              ? t('تم الحذف والأرشفة وإشعار المالك والتدقيق',
                  'Removed, archived, owner notified and audited')
              : t('تم تدقيق القرار', 'Decision audited')),
        ));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(t('تعذرت العملية، راجع الصلاحية وحالة المكان',
              'Action denied; verify permissions and place state')),
        ));
      }
    } finally {
      if (mounted) { setState(() => _busy = false); _refresh(); }
    }
  }
  Widget _item(Map<String, dynamic> row) {
    final status = (row['status'] ?? 'new').toString();
    final options = DedaIsolatedAdminProofPolicy
        .placeDeletionAllowedTransitions(status);
    return Card(child: ExpansionTile(
      leading: const Icon(Icons.location_off_outlined),
      title: Text((row['placeName'] ?? row['id'] ?? '').toString()),
      subtitle: Text('${_label(status)} • ${row['approvalNumber'] ?? ''}'),
      childrenPadding: const EdgeInsets.all(12),
      children: [
        Text('${t('معرّف المكان', 'Place ID')}: ${row['id'] ?? ''}'),
        Text('${t('المحافظة', 'Governorate')}: ${row['governorate'] ?? ''}'),
        Text('${t('العنوان', 'Address')}: ${row['address'] ?? ''}'),
        Text('${t('الهاتف', 'Phone')}: ${row['phone'] ?? ''}'),
        if (row['latitude'] != null && row['longitude'] != null)
          Text('${t('الإحداثيات', 'Coordinates')}: '
              '${row['latitude']}, ${row['longitude']}'),
        if ((row['reason'] ?? '').toString().isNotEmpty)
          Text('${t('سبب المالك', 'Owner reason')}: ${row['reason']}'),
        if ((row['reviewNote'] ?? '').toString().isNotEmpty)
          Text('${t('ملاحظة الإدارة', 'Admin note')}: ${row['reviewNote']}'),
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (options.contains('reviewing'))
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _decide(row, 'reviewing'),
              icon: const Icon(Icons.manage_search_outlined),
              label: Text(t('مراجعة', 'Review'))),
          if (options.contains('deleted'))
            FilledButton.icon(
              onPressed: _busy ? null : () => _decide(row, 'deleted'),
              icon: const Icon(Icons.delete_forever_outlined),
              label: Text(t('اعتماد وحذف المكان', 'Approve & delete'))),
          if (options.contains('rejected'))
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _decide(row, 'rejected'),
              icon: const Icon(Icons.cancel_outlined),
              label: Text(t('رفض', 'Reject'))),
        ]),
      ],
    ));
  }
  @override
  Widget build(BuildContext context) => FutureBuilder<DedaIsolatedManagerPage>(
    future: _page,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Center(child: CircularProgressIndicator());
      }
      if (snapshot.hasError || !snapshot.hasData) {
        return Center(child: TextButton(onPressed: _busy ? null : _refresh,
          child: Text(t('تعذر إثبات صلاحية المدير من الخادم',
              'Could not verify manager permission'))));
      }
      final page = snapshot.data!;
      final visible = page.rows.where(_matches).toList(growable: false);
      return Column(children: [
        Padding(padding: const EdgeInsets.all(8),
          child: Text(t('الموافقة تنقل المكان للمحذوفات وتزيله '
              'من الخريطة وتبلغ المالك، ولا تحذف حسابه.',
              'Approval archives and removes the place and notifies '
              'the owner, without deleting their account.'))),
        Wrap(spacing: 6, children: [
          for (final item in <(String, String, String)>[
            ('all','الكل','All'),('new','جديد','New'),
            ('reviewing','قيد المراجعة','Reviewing'),
            ('deleted','تم الحذف','Deleted'),('closed','مغلق','Closed'),
          ]) ChoiceChip(
            label: Text(t(item.$2,item.$3)),
            selected: _filter == item.$1,
            onSelected: _busy ? null :
                (_) => setState(() => _filter = item.$1),
          ),
        ]),
        Align(alignment: AlignmentDirectional.centerEnd,
          child: IconButton(onPressed: _busy ? null : _refresh,
            icon: const Icon(Icons.refresh))),
        Expanded(child: visible.isEmpty
            ? Center(child: Text(t('لا توجد طلبات في هذه الصفحة',
                'No requests on this page')))
            : ListView.builder(itemCount: visible.length,
                itemBuilder: (context, index) => _item(visible[index]))),
        Row(children: [
          Text('${t('صفحة', 'Page')} ${_back.length + 1}'),
          const Spacer(),
          TextButton(onPressed: !_busy && _back.isNotEmpty ? _previous : null,
            child: Text(t('السابق', 'Previous'))),
          TextButton(onPressed: !_busy && page.nextCursor != null
              ? () => _next(page) : null,
            child: Text(t('التالي', 'Next'))),
        ]),
      ]);
    },
  );
}

/// Full legacy \"🏆 الرابحون معنا\" queue under independent admin Auth.
/// Never pays diamonds, deducts points or marks a winner-confirmed receipt.
class _DedaIsolatedPrizeWinnersTab extends StatefulWidget {
  final DedaIsolatedAdminIdentity admin;
  final String dedaPhone;
  final bool isArabic;
  const _DedaIsolatedPrizeWinnersTab({
    required this.admin,required this.dedaPhone,required this.isArabic,
  });
  @override
  State<_DedaIsolatedPrizeWinnersTab> createState() =>
      _DedaIsolatedPrizeWinnersTabState();
}

class _DedaIsolatedPrizeWinnersTabState
    extends State<_DedaIsolatedPrizeWinnersTab> {
  late Future<List<Map<String,dynamic>>> _requests;
  final _search=TextEditingController();
  String _query='';
  final bool _busy=false;
  String t(String ar,String en)=>widget.isArabic?ar:en;
  String statusName(String value)=>switch(value) {
    'new'=>t('جديد','New'),
    'reviewing'=>t('قيد التدقيق','Under review'),
    'needs_info'=>t('نحتاج معلومات','Needs information'),
    'approved'=>t('تم اعتماد الفوز','Approved'),
    'prize_sent'=>t('بانتظار تأكيد الفائز','Awaiting winner confirmation'),
    'delivered'=>t('تم التسليم بتأكيد الفائز','Winner confirmed receipt'),
    'rejected'=>t('مرفوض','Rejected'),
    _=>value,
  };
  String displayId(String value) {
    final clean=value.trim().replaceAll('@','');
    return clean.isEmpty?'—':'@$clean';
  }
  int createdMillis(Map<String,dynamic> item) {
    final date=item['createdAt'];
    return date is Timestamp?date.millisecondsSinceEpoch:0;
  }
  Future<List<Map<String,dynamic>>> load()=>widget.admin
      .readScopedPrizeWinnerRequests(dedaPhone:widget.dedaPhone);
  @override
  void initState() {super.initState();_requests=load();}
  @override
  void dispose() {_search.dispose();super.dispose();}
  void refresh() {
    if(_busy)return;
    setState(()=>_requests=load());
  }
  Future<void> openRequest(Map<String,dynamic> record,int serial) async {
    if(_busy)return;
    final updated=await showDialog<bool>(context:context,
      builder:(ctx)=>_DedaIsolatedPrizeWinnerReviewDialog(
        admin:widget.admin,dedaPhone:widget.dedaPhone,
        isArabic:widget.isArabic,record:record,serial:serial));
    if(mounted && updated==true)refresh();
  }
  @override
  Widget build(BuildContext context) =>
      FutureBuilder<List<Map<String,dynamic>>>(
    future:_requests,builder:(context,snapshot) {
      if(snapshot.connectionState!=ConnectionState.done) {
        return const Center(child:CircularProgressIndicator());
      }
      if(snapshot.hasError || !snapshot.hasData) {
        return Center(child:TextButton(onPressed:refresh,
          child:Text(t('تعذر إثبات صلاحية المدير من الخادم، أعد المحاولة',
              'Could not verify manager permissions; retry'))));
      }
      final rows=snapshot.data!;
      final oldest=rows.toList()..sort((a,b)=>
          createdMillis(a).compareTo(createdMillis(b)));
      final numbers=<String,int>{
        for(var i=0;i<oldest.length;i++)
          oldest[i]['id'].toString():i+1,
      };
      final q=_query.trim().toLowerCase();
      final visible=rows.where((item){
        final id=(item['id']??'').toString();
        final serial=numbers[id]??0;
        final haystack=<String>[
          id,(item['name']??'').toString(),(item['dedaId']??'').toString(),
          (item['phone']??'').toString(),(item['rewardCode']??'').toString(),
          statusName((item['status']??'new').toString()),
          serial.toString(),'#${serial.toString().padLeft(3,'0')}',
        ].join(' ').toLowerCase();
        return haystack.contains(q);
      }).toList(growable:false);
      return Column(children:[
        Padding(padding:const EdgeInsets.all(10),
          child:TextField(controller:_search,
            onChanged:(value)=>setState(()=>_query=value),
            decoration:InputDecoration(
              prefixIcon:const Icon(Icons.search_rounded),
              hintText:t('ابحث بالاسم أو المعرّف أو الهاتف أو رقم الفائز',
                  'Search name, ID, phone or winner number'),
              suffixIcon:_query.isEmpty?null:IconButton(
                onPressed:(){_search.clear();setState(()=>_query='');},
                icon:const Icon(Icons.close_rounded)),
            ),
          ),
        ),
        Align(alignment:AlignmentDirectional.centerEnd,
          child:IconButton(onPressed:refresh,
              icon:const Icon(Icons.refresh))),
        Expanded(child:visible.isEmpty
          ?Center(child:Text(rows.isEmpty
            ?t('لا توجد طلبات فوز حالياً','No prize requests yet')
            :t('لا توجد نتائج مطابقة','No matching winners')))
          :ListView.builder(itemCount:visible.length,
            itemBuilder:(ctx,i){
              final item=visible[i];
              final id=(item['id']??'').toString();
              final serial=numbers[id]??0;
              final identifier=displayId((item['dedaId']??'').toString());
              final rewardCode=(item['rewardCode']??'—').toString();
              final state=statusName((item['status']??'new').toString());
              return Card(child:ListTile(
                leading:const Icon(Icons.emoji_events_outlined,
                    color:Color(0xFF9A7415)),
                title:Text((item['name']??'—').toString()),
                subtitle:Text('$identifier • $rewardCode\n$state'),
                trailing:Text('#${serial.toString().padLeft(3,'0')}'),
                onTap:()=>openRequest(item,serial),
              ));
            })),
      ]);
    },
  );
}

class _DedaIsolatedPrizeWinnerReviewDialog extends StatefulWidget {
  final DedaIsolatedAdminIdentity admin;
  final String dedaPhone;
  final bool isArabic;
  final Map<String,dynamic> record;
  final int serial;
  const _DedaIsolatedPrizeWinnerReviewDialog({
    required this.admin,required this.dedaPhone,required this.isArabic,
    required this.record,required this.serial,
  });
  @override
  State<_DedaIsolatedPrizeWinnerReviewDialog> createState()=>
      _DedaIsolatedPrizeWinnerReviewDialogState();
}
class _DedaIsolatedPrizeWinnerReviewDialogState
    extends State<_DedaIsolatedPrizeWinnerReviewDialog> {
  late String _status;
  late String _initialStatus;
  late final TextEditingController _message;
  late final TextEditingController _prize;
  bool _saving=false;
  String t(String ar,String en)=>widget.isArabic?ar:en;
  String statusLabel(String value)=>switch(value) {
    'new'=>t('جديد','New'),
    'reviewing'=>t('قيد التدقيق','Under review'),
    'needs_info'=>t('طلب معلومات إضافية','Request more information'),
    'approved'=>t('اعتماد الفوز','Approve win'),
    'prize_sent'=>t('إرسال الجائزة / انتظار تأكيد الفائز',
        'Mark sent / await winner'),
    'delivered'=>t('تم التسليم بتأكيد الفائز','Winner confirmed receipt'),
    'rejected'=>t('مرفوض','Rejected'),_=>value,
  };
  @override
  void initState(){
    super.initState();
    _status=(widget.record['status']??'new').toString();
    _initialStatus=_status;
    _message=TextEditingController(
      text:(widget.record['adminMessage']??'').toString());
    _prize=TextEditingController(
      text:(widget.record['prizeDetails']??'').toString());
  }
  @override
  void dispose(){_message.dispose();_prize.dispose();super.dispose();}
  String dateText(dynamic value)=>value is Timestamp
      ? value.toDate().toUtc().toIso8601String()
      : value?.toString()??'—';
  Widget dataRow(String title,dynamic data) => Padding(
    padding:const EdgeInsets.symmetric(vertical:3),
    child:Text('$title: ${data?.toString()??'—'}'),
  );
  Future<void> save() async {
    if(_saving)return;
    final note=_message.text.trim();
    final details=_prize.text.trim();
    if((_status=='needs_info' && note.isEmpty) ||
        (_status=='prize_sent' && details.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content:Text(t('اكتب المعلومات اللازمة قبل الحفظ.',
            'Complete the required information before saving.'))));
      return;
    }
    // An approval WITH details auto-advances to prize_sent in the legacy UI.
    // Require an explicit confirmation so it cannot imply diamond payout.
    if(_status=='approved' && details.isNotEmpty ||
        _status=='prize_sent' && _initialStatus!='prize_sent') {
      final yes=await showDialog<bool>(context:context,
        builder:(ctx)=>AlertDialog(
          title:Text(t('تأكيد تسجيل إرسال الجائزة',
              'Confirm recording prize sent')),
          content:Text(t('يسجل التطبيق حالة إرسال الجائزة فقط، '
              'ولا يحول ماسات. الفائز وحده يؤكد استلامها.',
              'This records prize-sent status only; no diamonds are '
              'transferred. Only the winner confirms receipt.')),
          actions:[
            TextButton(onPressed:()=>Navigator.pop(ctx,false),
              child:Text(t('إلغاء','Cancel'))),
            FilledButton(onPressed:()=>Navigator.pop(ctx,true),
              child:Text(t('تأكيد','Confirm'))),
          ],
        ));
      if(!mounted||yes!=true)return;
    }
    setState(()=>_saving=true);
    try {
      await widget.admin.reviewScopedPrizeWinnerRequest(
        dedaPhone:widget.dedaPhone,
        requestId:(widget.record['id']??'').toString(),
        status:_status,adminMessage:note,prizeDetails:details);
      if(mounted)Navigator.pop(context,true);
    }catch(_){
      if(mounted){
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:Text(t('تعذر الحفظ أو تغيّرت حالة الطلب وصلاحية المدير.',
            'Update denied: request state or permission changed.'))));
      }
    }finally{
      if(mounted)setState(()=>_saving=false);
    }
  }
  @override
  Widget build(BuildContext context){
    final item=widget.record;
    final options=DedaIsolatedAdminProofPolicy
        .prizeWinnerAllowedTransitions(_initialStatus);
    final serial=widget.serial.toString().padLeft(3,'0');
    return AlertDialog(
      title:Text(t('تفاصيل الفائز','Winner details')),
      content:SizedBox(width:480,child:SingleChildScrollView(
        child:Column(mainAxisSize:MainAxisSize.min,
          crossAxisAlignment:CrossAxisAlignment.stretch,children:[
          dataRow(t('الاسم','Name'),item['name']),
          dataRow(t('رقم الفائز','Winner number'),'#$serial'),
          dataRow(t('معرّف DEDA','DEDA ID'),item['dedaId']),
          dataRow(t('الهاتف','Phone'),item['phone']),
          dataRow(t('الرمز الكامل','Full code'),item['rewardCode']),
          dataRow(t('الرصيد عند الفوز','Balance at win'),
              item['pointsAtCompletion']),
          dataRow(t('النقاط المستقطعة نهائياً','Reserved points'),
              item['finalReservedPoints']),
          dataRow(t('رد الفائز','Winner reply'),item['userReply']),
          if(item['createdAt']!=null)
            dataRow(t('تاريخ الفوز','Won at'),dateText(item['createdAt'])),
          if(item['prizeSentAt']!=null)
            dataRow(t('وقت إرسال الجائزة','Prize sent at'),
                dateText(item['prizeSentAt'])),
          if(item['winnerConfirmedAt']!=null)
            dataRow(t('تأكيد الفائز','Winner confirmed at'),
                dateText(item['winnerConfirmedAt'])),
          const SizedBox(height:12),
          DropdownButtonFormField<String>(
            initialValue:_status,
            decoration:InputDecoration(
              labelText:t('حالة الطلب','Request status')),
            items:options.map((v)=>DropdownMenuItem<String>(
              value:v,child:Text(statusLabel(v)))).toList(),
            onChanged:_saving||_initialStatus=='delivered'||
                  _initialStatus=='prize_sent'
                ?null:(v){if(v!=null)setState(()=>_status=v);},
          ),
          const SizedBox(height:8),
          if(_initialStatus=='prize_sent')
            Text(t('بانتظار أن يؤكد الفائز الاستلام بنفسه.',
                'Waiting for winner to confirm receipt.')),
          if(_initialStatus=='delivered')
            Text(t('الفائز أكد الاستلام؛ أُغلقت دورة الجوائز.',
                'Winner confirmed receipt; prize cycle closed.')),
          TextField(controller:_message,maxLength:800,minLines:2,maxLines:4,
            decoration:InputDecoration(
              labelText:t('رسالة الإدارة للفائز','Admin message'))),
          TextField(controller:_prize,maxLength:800,minLines:2,maxLines:4,
            decoration:InputDecoration(
              labelText:t('تفاصيل الجائزة المخصصة','Assigned prize details'))),
          Text(t('هذه البطاقة لا تحول ماسات ولا تخصم نقاطاً.',
              'This card never transfers diamonds or deducts points.')),
        ]))),
      actions:[
        TextButton(onPressed:_saving?null:()=>Navigator.pop(context,false),
          child:Text(t('إلغاء','Cancel'))),
        FilledButton(onPressed:_saving||options.isEmpty?null:save,
          child:Text(t('حفظ وإرسال التحديث','Save and update'))),
      ],
    );
  }
}

/// User recovery (recovery_requests), not staff recovery. Original card
/// colors and manually reviewed workflow, with credential mutation blocked.
class _DedaIsolatedUserRecoveryTab extends StatefulWidget {
  final DedaIsolatedAdminIdentity admin;
  final String dedaPhone;
  final bool isArabic;

  const _DedaIsolatedUserRecoveryTab({
    required this.admin, required this.dedaPhone, required this.isArabic,
  });

  @override
  State<_DedaIsolatedUserRecoveryTab> createState() =>
      _DedaIsolatedUserRecoveryTabState();
}

class _DedaIsolatedUserRecoveryTabState
    extends State<_DedaIsolatedUserRecoveryTab> {
  late Future<DedaIsolatedManagerPage> _page;
  QueryDocumentSnapshot<Map<String, dynamic>>? _cursor;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>?> _back = [];
  bool _busy = false;

  String t(String ar, String en) => widget.isArabic ? ar : en;

  @override
  void initState() {
    super.initState();
    _page = _load();
  }

  Future<DedaIsolatedManagerPage> _load() =>
      widget.admin.readScopedUserRecoveryPage(
        dedaPhone: widget.dedaPhone, startAfter: _cursor,
      );

  void _refresh() {
    if (_busy) return;
    setState(() => _page = _load());
  }

  void _next(DedaIsolatedManagerPage page) {
    if (_busy || page.nextCursor == null) return;
    setState(() {
      _back.add(_cursor);
      _cursor = page.nextCursor;
      _page = _load();
    });
  }

  void _previous() {
    if (_busy || _back.isEmpty) return;
    setState(() {
      _cursor = _back.removeLast();
      _page = _load();
    });
  }

  String _status(String status) {
    switch (status) {
      case 'new': return t('بانتظار المراجعة', 'Pending review');
      case 'review': return t('قيد التدقيق', 'Under review');
      case 'ready': return t('تم إصدار رمز سابقاً', 'Previously processed');
      case 'rejected': return t('مرفوض', 'Rejected');
      case 'error': return t('تحتاج معالجة', 'Needs reconciliation');
      default: return status;
    }
  }

  String _date(dynamic value) {
    if (value is! Timestamp) return '';
    final at = value.toDate().toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return two(at.day) + '/' + two(at.month) + '/' +
        at.year.toString() + ' ' + two(at.hour) + ':' + two(at.minute);
  }

  Future<void> _check(Map<String, dynamic> request) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final info = await widget.admin.readScopedUserRecoveryAccountCheck(
        dedaPhone: widget.dedaPhone,
        accountKey: (request['accountKey'] ?? '').toString(),
        requestedName: (request['fullName'] ?? '').toString(),
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(t('تدقيق حساب المستخدم', 'Check user account')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(info.directoryActive
                  ? t('الحساب مسجل وفعّال', 'Directory: active')
                  : t('الحساب غير مؤكد', 'Directory: unverified')),
              Text(info.profileExists
                  ? t('الملف القديم موجود', 'Old profile: found')
                  : t('ملف الحساب القديم مفقود', 'Old profile: missing')),
              Text(info.nameMatches
                  ? t('الاسم مطابق', 'Name matches')
                  : t('الاسم يحتاج تدقيق', 'Name needs review')),
              const SizedBox(height: 12),
              Text(t(
                'مطابقة الاسم ليست إثبات ملكية UID. لا إصدار رمز جديد '
                'بدون تحقق مستقل يحفظ الحساب وتقدمه.',
                'A matching name is NOT proof of UID ownership. No PIN '
                'issuance without independent identity and progress proof.',
              )),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext),
              child: Text(t('إغلاق', 'Close'))),
          ],
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(t('تعذر تدقيق بيانات الحساب والصلاحية.',
              'Account verification unavailable or permission denied.')),
        ));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _decide(String id, String action) async {
    if (_busy || !DedaIsolatedAdminProofPolicy.validScopedDocumentId(id)) {
      return;
    }
    final controller = TextEditingController();
    try {
      final reason = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(action == 'review'
              ? t('تسجيل مراجعة', 'Mark for review')
              : t('رفض طلب الاسترجاع', 'Reject recovery request')),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(action == 'review'
                ? t('المراجعة لا تصدر رمزاً ولا تغير حساب المستخدم.',
                    'Review never issues a PIN or changes a user account.')
                : t('سيُرفض هذا الطلب فقط دون تغيير الحساب.',
                    'Only this request is rejected, not the account.')),
            TextField(
              controller: controller,
              minLines: 2, maxLines: 4, maxLength: 250,
              decoration: InputDecoration(
                labelText: t('السبب (5 أحرف على الأقل)',
                    'Reason (at least 5 characters)'),
              ),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext),
              child: Text(t('إلغاء', 'Cancel'))),
            FilledButton(
              onPressed: () {
                final value = controller.text.trim();
                if (value.length >= 5 && value.length <= 250) {
                  Navigator.pop(dialogContext, value);
                }
              },
              child: Text(t('تأكيد القرار', 'Confirm decision')),
            ),
          ],
        ),
      );
      if (reason == null || !mounted) return;
      setState(() => _busy = true);
      try {
        await widget.admin.decideScopedUserRecoveryReview(
          dedaPhone: widget.dedaPhone,
          requestId: id, action: action, reason: reason,
        );
        if (mounted) {
          setState(() => _page = _load());
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(t('تم تدقيق القرار دون تعديل الحساب.',
                'Decision audited; user account unchanged.')),
          ));
        }
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(t('تعذر القرار؛ تحقق من حالة الطلب والصلاحية.',
                'Decision denied; check request and permission.')),
          ));
        }
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    } finally {
      controller.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Card(
        color: const Color(0xFFEAF4EA),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF9FBDA3)),
        ),
        child: SwitchListTile.adaptive(
          value: false, onChanged: null,
          title: Text(t('استرجاع الرمز تلقائياً بعد 10 ثوانٍ',
              'Auto-reissue PIN after 10 seconds')),
          subtitle: Text(t('الخدمة مؤجلة حتى إثبات توافق UID والرمز بالخادم.',
              'Disabled until original UID/PIN compatibility is verified.')),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(children: [
          Expanded(child: Text(t(
            'المراجعة والرفض فقط؛ إصدار رمز جديد محجوب لحماية المستخدم.',
            'Review/reject only; PIN issuance blocked to protect users.',
          ), style: const TextStyle(fontSize: 12))),
          IconButton(
            onPressed: _busy ? null : _refresh,
            tooltip: t('تحديث من الخادم', 'Refresh from server'),
            icon: const Icon(Icons.refresh),
          ),
        ]),
      ),
      Expanded(child: FutureBuilder<DedaIsolatedManagerPage>(
        future: _page,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text(t(
              'تعذرت قراءة طلبات الاسترجاع بالصلاحية الحالية.',
              'Recovery requests unavailable with current privileges.',
            )));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final page = snapshot.data!;
          return Column(children: [
            Expanded(
              child: page.rows.isEmpty
                  ? Center(child: Text(t('لا توجد طلبات استرجاع.',
                      'No recovery requests.')))
                  : ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: page.rows.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final item = page.rows[index];
                        final id = (item['id'] ?? '').toString();
                        final status = (item['status'] ?? 'new').toString();
                        final review = status == 'new';
                        final reject = const <String>{'new', 'review'}
                            .contains(status);
                        return Card(child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(children: [
                                const Icon(Icons.lock_reset,
                                    color: Color(0xFF17652F)),
                                const SizedBox(width: 8),
                                Expanded(child: Text(
                                  (item['fullName'] ?? '').toString(),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800, fontSize: 16,
                                  ),
                                )),
                                Text(_status(status)),
                              ]),
                              const SizedBox(height: 8),
                              SelectableText(
                                t('الهاتف: ', 'Phone: ') +
                                (item['phone'] ?? '').toString(),
                                textDirection: TextDirection.ltr,
                              ),
                              Text(t('وقت الطلب: ', 'Requested: ') +
                                  _date(item['createdAt'])),
                              const SizedBox(height: 10),
                              Wrap(spacing: 8, children: [
                                OutlinedButton.icon(
                                  onPressed: _busy ? null : () => _check(item),
                                  icon: const Icon(Icons.fact_check_outlined),
                                  label: Text(t('تدقيق الحساب',
                                      'Check account')),
                                ),
                                if (review)
                                  OutlinedButton.icon(
                                    onPressed: _busy
                                        ? null : () => _decide(id, 'review'),
                                    icon: const Icon(Icons.visibility_outlined),
                                    label: Text(t('قيد المراجعة', 'Review')),
                                  ),
                                if (reject)
                                  OutlinedButton.icon(
                                    onPressed: _busy
                                        ? null : () => _decide(id, 'reject'),
                                    icon: const Icon(Icons.close),
                                    label: Text(t('رفض', 'Reject')),
                                  ),
                                if (reject)
                                  Tooltip(
                                    message: t('بانتظار إثبات ملكية UID '
                                        'وتوافق الرمز بالخادم.',
                                        'Awaiting server UID/PIN proof.'),
                                    child: FilledButton.icon(
                                      onPressed: null,
                                      icon: const Icon(Icons.key_off_outlined),
                                      label: Text(t('إصدار الرمز محجوب',
                                          'PIN issuance locked')),
                                    ),
                                  ),
                              ]),
                            ],
                          ),
                        ));
                      },
                    ),
            ),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              TextButton.icon(
                onPressed: !_busy && _back.isNotEmpty ? _previous : null,
                icon: const Icon(Icons.chevron_left),
                label: Text(t('السابق', 'Previous')),
              ),
              TextButton.icon(
                onPressed: !_busy && page.nextCursor != null
                    ? () => _next(page) : null,
                icon: const Icon(Icons.chevron_right),
                label: Text(t('التالي', 'Next')),
              ),
            ]),
          ]);
        },
      )),
    ]);
  }
}

class _DedaIsolatedReadOnlyTab extends StatefulWidget {
  final DedaIsolatedAdminIdentity admin;
  final String dedaPhone;
  final String collection;
  final bool isArabic;

  const _DedaIsolatedReadOnlyTab({
    required this.admin,
    required this.dedaPhone,
    required this.collection,
    required this.isArabic,
  });

  @override
  State<_DedaIsolatedReadOnlyTab> createState() =>
      _DedaIsolatedReadOnlyTabState();
}

class _DedaIsolatedReadOnlyTabState
    extends State<_DedaIsolatedReadOnlyTab> {
  late Future<List<Map<String, dynamic>>> _rows;
  bool _mutating = false;
  bool _openingUser = false;
  final _userSearch = TextEditingController();

  String t(String ar, String en) => widget.isArabic ? ar : en;

  @override
  void initState() {
    super.initState();
    _rows = _fetch();
  }

  @override
  void dispose() {
    _userSearch.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _fetch() =>
      widget.collection == 'users'
          ? widget.admin.readScopedAdminUserDirectory(
              dedaPhone: widget.dedaPhone,
            )
          : widget.admin.readScopedAdminList(
              dedaPhone: widget.dedaPhone,
              collection: widget.collection,
              maxItems: widget.collection == 'admin_audit' ? 300 : 25,
            );

  void _refresh() => setState(() => _rows = _fetch());

  Widget _userInfoRow(String label, dynamic value, {bool ltr = false}) {
    final raw = (value ?? '').toString().trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label + ': ', style: const TextStyle(
          fontWeight: FontWeight.w700)),
        Expanded(child: Directionality(
          textDirection: ltr ? TextDirection.ltr : Directionality.of(context),
          child: Text(raw.isEmpty ? t('غير محدد', 'Not provided') : raw),
        )),
      ]),
    );
  }

  Future<void> _openUser(String userUid) async {
    if (widget.collection != 'users' || _openingUser ||
        !DedaIsolatedAdminProofPolicy.validScopedDocumentId(userUid)) return;
    setState(() => _openingUser = true);
    try {
      final snapshot = await widget.admin.readScopedUserAccountSnapshot(
        dedaPhone: widget.dedaPhone, userUid: userUid,
      );
      if (!mounted) return;
      final profile = Map<String, dynamic>.from(
        snapshot['profile'] as Map? ?? const <String, dynamic>{},
      );
      final places = snapshot['publishedPlaces'] as List? ?? const [];
      final requests = snapshot['placeRequests'] as List? ?? const [];
      final support = snapshot['supportRequests'] as List? ?? const [];
      final relatedAccessible = snapshot['relatedAccessible'] == true;
      final truncated = Map<String, dynamic>.from(
          snapshot['relatedTruncatedCollections'] as Map? ?? const {});
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Row(children: [
            const Icon(Icons.visibility_outlined),
            const SizedBox(width: 8),
            Expanded(child: Text(t('حساب المستخدم • قراءة فقط',
                'User account • read only'))),
          ]),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _userInfoRow(t('الاسم', 'Name'), profile['name']),
                  _userInfoRow(t('الهاتف', 'Phone'), profile['phone'], ltr: true),
                  _userInfoRow(t('نوع الحساب', 'Account type'),
                      profile['accountType']),
                  const Divider(),
                  if (relatedAccessible) ...[
                    _userInfoRow(t('الأماكن المعتمدة', 'Approved places'),
                        truncated['published_places'] == true
                            ? places.length.toString() + '+' : places.length),
                    _userInfoRow(t('طلبات الأماكن', 'Place requests'),
                        truncated['place_requests'] == true
                            ? requests.length.toString() + '+' : requests.length),
                    _userInfoRow(t('رسائل الدعم', 'Support messages'),
                        truncated['support_requests'] == true
                            ? support.length.toString() + '+' : support.length),
                    if (truncated.values.any((item) => item == true))
                      Text(t('علامة + تعني أن العدد الأدنى مؤكد، '
                          'وقد توجد سجلات إضافية.',
                          '+ means at least this many records; more may exist.')),
                    if (places.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(t('أماكن المستخدم', 'User places'),
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                      ...places.take(10).map((entry) {
                        final place = Map<String, dynamic>.from(entry as Map);
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.storefront_outlined),
                          title: Text((place['placeName'] ?? '').toString()),
                          subtitle: Text(
                            (place['approvalNumber'] ?? '').toString()),
                        );
                      }),
                    ],
                  ] else
                    Text(t('تفاصيل الأماكن والطلبات والدعم محجوبة لهذا الدور.',
                      'Related places, requests and support are restricted for this role.')),
                  const SizedBox(height: 8),
                  Text(t('عرض فقط؛ تم تسجيل المشاهدة في سجل الإدارة، '
                      'ولم تُعدّل بيانات المستخدم.',
                      'Read only: the view was audited and the user account was not modified.')),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext),
              child: Text(t('إغلاق', 'Close'))),
          ],
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(t('تعذر فتح تفاصيل المستخدم أو تأكيد صلاحية الإدارة.',
            'Could not verify permission or load user details.')),
        ));
      }
    } finally {
      if (mounted) setState(() => _openingUser = false);
    }
  }

  Future<void> _createInvitation() async {
    if (_mutating || widget.collection != 'admin_invites') return;
    setState(() => _mutating = true);
    final name = TextEditingController();
    final email = TextEditingController();
    final phone = TextEditingController();
    final department = TextEditingController();
    final province = TextEditingController();
    var role = 'employee';
    try {
      final data = await showDialog<Map<String, String>>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, updateDialog) => AlertDialog(
            title: Text(t('دعوة موظف إداري', 'Invite administrative staff')),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: name,
                    maxLength: 100,
                    decoration: InputDecoration(
                      labelText: t('الاسم الكامل', 'Full name'),
                    ),
                  ),
                  TextField(
                    controller: email,
                    keyboardType: TextInputType.emailAddress,
                    maxLength: 254,
                    decoration: InputDecoration(
                      labelText: t('البريد الإداري', 'Admin email'),
                    ),
                  ),
                  TextField(
                    controller: phone,
                    keyboardType: TextInputType.phone,
                    maxLength: 16,
                    decoration: InputDecoration(
                      labelText: t('رقم حساب DEDA', 'DEDA account phone'),
                    ),
                  ),
                  TextField(
                    controller: department,
                    maxLength: 100,
                    decoration: InputDecoration(
                      labelText: t('القسم', 'Department'),
                    ),
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: role,
                    decoration: InputDecoration(
                      labelText: t('الدور', 'Role'),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: 'employee',
                        child: Text(t('موظف', 'Employee')),
                      ),
                      DropdownMenuItem(
                        value: 'deputy_manager',
                        child: Text(t('معاون المدير', 'Deputy manager')),
                      ),
                      DropdownMenuItem(
                        value: 'province_agent',
                        child: Text(t('وكيل محافظة', 'Province agent')),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) updateDialog(() => role = value);
                    },
                  ),
                  if (role == 'province_agent')
                    TextField(
                      controller: province,
                      maxLength: 80,
                      decoration: InputDecoration(
                        labelText: t('المحافظة', 'Governorate'),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Text(t(
                    'الصلاحيات الافتراضية للدور؛ لا تُفعّل الدعوة قبل قبولها.',
                    'Role defaults; the invitation does not create an admin login.',
                  )),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(t('إلغاء', 'Cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, <String, String>{
                  'name': name.text,
                  'email': email.text,
                  'phone': phone.text,
                  'department': department.text,
                  'province': province.text,
                  'role': role,
                }),
                child: Text(t('إنشاء الدعوة', 'Create invitation')),
              ),
            ],
          ),
        ),
      );
      if (data == null || !mounted) return;
      final cleanRole = data['role'] ?? '';
      final result = await widget.admin.createScopedAdminInvitation(
        dedaPhone: widget.dedaPhone,
        displayName: data['name'] ?? '',
        email: data['email'] ?? '',
        phone: data['phone'] ?? '',
        role: cleanRole,
        department: data['department'] ?? '',
        governorate: cleanRole == 'province_agent'
            ? data['province'] ?? '' : '',
        permissions: DedaIsolatedAdminProofPolicy
            .defaultInvitationPermissions(cleanRole),
      );
      if (!mounted) return;
      _refresh();
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(t('دعوة إدارية جديدة', 'New administrative invitation')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t(
                  'شارك التفاصيل مع صاحب البريد فقط، ولا تنشر رمز التفعيل.',
                  'Share with the invited email owner only; keep the activation code private.',
                )),
                const SizedBox(height: 10),
                SelectableText('Email: ${result['email']}'),
                SelectableText('Invite ID: ${result['inviteId']}'),
                SelectableText('Admin ID: ${result['adminId']}'),
                SelectableText('Activation code: ${result['activationCode']}'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(t('إغلاق', 'Close')),
            ),
          ],
        ),
      );
    } catch (_) {
      if (mounted) {
        _refresh();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(t(
            'لم تُنشأ الدعوة: تحقق من البيانات والصلاحيات وعدم استخدام البريد أو الهاتف مسبقاً.',
            'Invitation not created: check inputs, manager rights, email and phone.',
          )),
        ));
      }
    } finally {
      name.dispose();
      email.dispose();
      phone.dispose();
      department.dispose();
      province.dispose();
      if (mounted) setState(() => _mutating = false);
    }
  }

  Future<String?> _askTeamReason({
    required String title,
    required String displayName,
  }) async {
    String reason = '';
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, updateDialog) => AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(displayName),
              const SizedBox(height: 12),
              TextField(
                maxLength: 400,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: t('السبب', 'Reason'),
                ),
                onChanged: (value) => updateDialog(() => reason = value.trim()),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(t('إلغاء', 'Cancel')),
            ),
            FilledButton(
              onPressed: reason.isEmpty
                  ? null : () => Navigator.pop(dialogContext, reason),
              child: Text(t('تأكيد', 'Confirm')),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _suspendMember(Map<String, dynamic> member) async {
    if (_mutating || widget.collection != 'admins') return;
    final targetUid = (member['id'] ?? '').toString();
    if (!DedaIsolatedAdminProofPolicy.validScopedDocumentId(targetUid)) {
      return;
    }
    final confirmedReason = await _askTeamReason(
      title: t('تعليق صلاحيات الموظف', 'Suspend staff access'),
      displayName: (member['displayName'] ?? '').toString(),
    );
    if (confirmedReason == null || !mounted) return;
    setState(() => _mutating = true);
    try {
      await widget.admin.suspendScopedAdminMember(
        dedaPhone: widget.dedaPhone,
        targetUid: targetUid,
        reason: confirmedReason,
      );
      if (!mounted) return;
      _refresh();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(t(
          'تم تعليق دخول الموظف للإدارة. لا يعني ذلك إبطال رمز Firebase؛ الصلاحيات تُراجع خادمياً عند الدخول.',
          'Staff admin access suspended. Firebase tokens were not revoked; admin rights are rechecked on the server.')),

      ));
    } catch (_) {
      if (!mounted) return;
      _refresh();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(t(
          'تعذر التعليق: يجب إعادة التحقق من صلاحية المدير والاتصال بالخادم.',
          'Suspension denied: verify manager rights and server connectivity.',
        )),
      ));
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }



  Future<void> _cancelInvitation(Map<String, dynamic> invitation) async {
    if (_mutating || widget.collection != 'admin_invites') return;
    final inviteId = (invitation['id'] ?? '').toString();
    if (!DedaIsolatedAdminProofPolicy.validScopedDocumentId(inviteId)) {
      return;
    }
    final confirmedReason = await _askTeamReason(
      title: t('إلغاء دعوة معلقة', 'Cancel pending invitation'),
      displayName: (invitation['displayName'] ?? '').toString(),
    );
    if (confirmedReason == null || !mounted) return;
    setState(() => _mutating = true);
    try {
      await widget.admin.cancelScopedAdminInvitation(
        dedaPhone: widget.dedaPhone,
        inviteId: inviteId,
        reason: confirmedReason,
      );
      if (!mounted) return;
      _refresh();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(t('تم إلغاء الدعوة المعلقة.', 'Pending invitation cancelled.')),
      ));
    } catch (_) {
      if (!mounted) return;
      _refresh();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(t(
          'تعذر الإلغاء: الدعوة غير معلقة أو تغيرت الصلاحيات أو بوابة الهاتف.',
          'Cancellation denied: invitation, permission or gateway changed.',
        )),
      ));
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }


  Future<void> _editMember(Map<String, dynamic> member) async {
    if (_mutating || widget.collection != 'admins') return;
    final id = (member['id'] ?? '').toString();
    if (!DedaIsolatedAdminProofPolicy.validScopedDocumentId(id)) return;
    final name = TextEditingController(text: (member['displayName'] ?? '').toString());
    final phone = TextEditingController(text: (member['phone'] ?? '').toString());
    final department = TextEditingController(text: (member['department'] ?? '').toString());
    final province = TextEditingController(text: (member['governorate'] ?? '').toString());
    var role = (member['role'] ?? 'employee').toString();
    var status = (member['status'] ?? 'disabled').toString();
    if (!const <String>{'active', 'temporarily_stopped', 'disabled'}.contains(status)) {
      status = member['active'] == true ? 'active' : 'disabled';
    }
    final prior = member['permissions'];
    var permissions = <String, bool>{
      for (final key in DedaIsolatedAdminProofPolicy.invitationPermissionKeys)
        key: prior is Map && prior[key] == true,
    };
    try {
      final values = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (dialog) => StatefulBuilder(
          builder: (dialog, refresh) => AlertDialog(
            title: Text(t('تعديل الموظف وصلاحياته', 'Edit staff and permissions')),
            content: SizedBox(width: 430, child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(controller: name, maxLength: 100,
                  decoration: InputDecoration(labelText: t('الاسم', 'Name'))),
                TextField(controller: phone, keyboardType: TextInputType.phone,
                  maxLength: 16,
                  decoration: InputDecoration(labelText: t('هاتف حساب DEDA', 'DEDA phone'))),
                TextField(controller: department, maxLength: 100,
                  decoration: InputDecoration(labelText: t('القسم', 'Department'))),
                DropdownButtonFormField<String>(
                  initialValue: role,
                  decoration: InputDecoration(labelText: t('الدور', 'Role')),
                  items: [
                    DropdownMenuItem(value: 'employee', child: Text(t('موظف', 'Employee'))),
                    DropdownMenuItem(value: 'deputy_manager', child: Text(t('معاون', 'Deputy'))),
                    DropdownMenuItem(value: 'province_agent', child: Text(t('وكيل محافظة', 'Province agent'))),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      refresh(() {
                        role = v;
                        permissions = DedaIsolatedAdminProofPolicy
                            .defaultInvitationPermissions(v);
                      });
                    }
                  },
                ),
                if (role == 'province_agent')
                  TextField(controller: province, maxLength: 80,
                    decoration: InputDecoration(labelText: t('المحافظة', 'Governorate'))),
                DropdownButtonFormField<String>(
                  initialValue: status,
                  decoration: InputDecoration(labelText: t('حالة الوصول', 'Access status')),
                  items: [
                    DropdownMenuItem(value: 'active', child: Text(t('نشط', 'Active'))),
                    DropdownMenuItem(value: 'temporarily_stopped', child: Text(t('موقوف مؤقتاً', 'Suspended'))),
                    DropdownMenuItem(value: 'disabled', child: Text(t('معطّل', 'Disabled'))),
                  ],
                  onChanged: (v) { if (v != null) refresh(() => status = v); },
                ),
                const Divider(),
                Text(t('الصلاحيات', 'Permissions')),
                ...DedaIsolatedAdminProofPolicy.invitationPermissionKeys.map((key) =>
                  SwitchListTile(
                    dense: true, title: Text(key),
                    value: permissions[key] ?? false,
                    onChanged: (v) => refresh(() => permissions[key] = v),
                  )),
              ]),
            )),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialog),
                child: Text(t('إلغاء', 'Cancel'))),
              FilledButton(onPressed: () => Navigator.pop(dialog, <String, dynamic>{
                'name': name.text, 'phone': phone.text, 'department': department.text,
                'province': province.text, 'role': role, 'status': status,
                'permissions': Map<String, bool>.from(permissions),
              }), child: Text(t('متابعة', 'Continue'))),
            ],
          ),
        ),
      );
      if (values == null || !mounted) return;
      final reason = await _askTeamReason(
        title: t('تأكيد تعديل الموظف', 'Confirm staff update'),
        displayName: (member['displayName'] ?? '').toString(),
      );
      if (reason == null || !mounted) return;
      setState(() => _mutating = true);
      try {
        await widget.admin.updateScopedAdminMember(
          dedaPhone: widget.dedaPhone, targetUid: id,
          displayName: values['name'] as String, phone: values['phone'] as String,
          role: values['role'] as String, department: values['department'] as String,
          governorate: values['role'] == 'province_agent' ? values['province'] as String : '',
          status: values['status'] as String,
          permissions: values['permissions'] as Map<String, bool>, reason: reason,
        );
        if (mounted) { _refresh(); ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(t('تم تعديل الموظف وبوابته.', 'Staff and gateway updated.')))); }
      } catch (_) {
        if (mounted) { _refresh(); ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(t('فشل التعديل: راجع الصلاحيات وربط الهاتف.',
            'Update denied: verify permissions and phone binding.')))); }
      } finally { if (mounted) setState(() => _mutating = false); }
    } finally {
      name.dispose(); phone.dispose(); department.dispose(); province.dispose();
    }
  }

  Future<void> _removeMemberAccess(Map<String, dynamic> member) async {
    if (_mutating || widget.collection != 'admins') return;
    final id = (member['id'] ?? '').toString();
    if (!DedaIsolatedAdminProofPolicy.validScopedDocumentId(id)) return;
    final reason = await _askTeamReason(
      title: t('إزالة وصول الموظف', 'Remove staff access'),
      displayName: (member['displayName'] ?? '').toString(),
    );
    if (reason == null || !mounted) return;
    final confirm = await showDialog<bool>(context: context,
      builder: (dialog) => AlertDialog(
        title: Text(t('تأكيد نهائي', 'Final confirmation')),
        content: Text(t('سيُحذف وصول الإدارة وبوابة الهاتف فقط، ولن يُحذف حساب DEDA أو Firebase Auth.',
          'Only admin access and its gateway are removed, not DEDA or Firebase Auth.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false),
            child: Text(t('إلغاء', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(dialog, true),
            child: Text(t('إزالة الوصول', 'Remove access'))),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() => _mutating = true);
    try {
      await widget.admin.removeScopedAdminMemberAccess(
        dedaPhone: widget.dedaPhone, targetUid: id, reason: reason,
      );
      if (mounted) { _refresh(); ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(t('أُزيل وصول الإدارة فقط.', 'Admin access removed.')))); }
    } catch (_) {
      if (mounted) { _refresh(); ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(t('تعذرت الإزالة: لم يثبت ربط الموظف وبوابة الهاتف.',
          'Removal denied: staff gateway binding unverified.')))); }
    } finally { if (mounted) setState(() => _mutating = false); }
  }

  Future<void> _resetMemberPassword(Map<String, dynamic> member) async {
    if (_mutating || widget.collection != 'admins') return;
    final id = (member['id'] ?? '').toString();
    if (!DedaIsolatedAdminProofPolicy.validScopedDocumentId(id)) return;
    final confirm = await showDialog<bool>(context: context,
      builder: (dialog) => AlertDialog(
        title: Text(t('إعادة تعيين كلمة المرور', 'Password reset')),
        content: Text(t('إرسال رابط إعادة تعيين إلى البريد الموثق لهذا الموظف؟',
          'Send a password reset link to the verified staff email?')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false),
            child: Text(t('إلغاء', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(dialog, true),
            child: Text(t('طلب الرابط', 'Request link'))),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() => _mutating = true);
    try {
      await widget.admin.requestScopedMemberPasswordReset(
        dedaPhone: widget.dedaPhone, targetUid: id,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(t('طُلب رابط إعادة التعيين.', 'Reset email requested.')),
        ));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(t('تعذر الطلب. راجع تخويل الإدارة والاتصال.',
            'Password reset denied; verify authorization and connection.')),
        ));
      }
    } finally { if (mounted) setState(() => _mutating = false); }
  }

  Future<void> _shareInvitation(Map<String, dynamic> invitation) async {
    if (_mutating || widget.collection != 'admin_invites') return;
    final id = (invitation['id'] ?? '').toString();
    if (!DedaIsolatedAdminProofPolicy.validScopedDocumentId(id)) return;
    setState(() => _mutating = true);
    try {
      final live = await widget.admin.readScopedAdminRecord(
        dedaPhone: widget.dedaPhone, collection: 'admin_invites', recordId: id,
      );
      final expiry = live?['expiresAt'];
      if (live == null || live['status'] != 'pending' ||
          (live['claimedUid'] ?? '').toString().trim().isNotEmpty ||
          expiry is! Timestamp || !expiry.toDate().isAfter(DateTime.now()) ||
          !RegExp(r'^[0-9]{8}$').hasMatch(
            (live['activationCode'] ?? '').toString())) {
        throw StateError('deda-admin-invitation-share-denied');
      }
      final email = (live['email'] ?? '').toString().trim();
      final msg = t(
        'دعوة إدارية إلى DEDA\n'
        'البريد: $email\n'
        'معرّف الدعوة: $id\n'
        'الرقم الإداري: ${live['adminId']}\n'
        'رمز التفعيل: ${live['activationCode']}\n'
        'من دخول الإدارة اختر تفعيل الدعوة. لا تشارك الرمز مع شخص آخر.',
        'DEDA administration invitation\n'
        'Email: $email\n'
        'Invitation ID: $id\n'
        'Admin ID: ${live['adminId']}\n'
        'Activation code: ${live['activationCode']}\n'
        'Choose Activate invitation from admin sign-in. Keep code private.',
      );
      if (!mounted) return;
      final action = await showDialog<String>(context: context,
        builder: (dialog) => AlertDialog(
          title: Text(t('مشاركة الدعوة', 'Share invitation')),
          content: Text(t('لصاحب البريد المقصود فقط. فتح البريد لا يثبت الإرسال.',
            'Share only with intended recipient; opening mail does not prove delivery.')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialog),
              child: Text(t('إلغاء', 'Cancel'))),
            TextButton(onPressed: () => Navigator.pop(dialog, 'copy'),
              child: Text(t('نسخ', 'Copy'))),
            FilledButton(onPressed: () => Navigator.pop(dialog, 'email_draft'),
              child: Text(t('فتح البريد', 'Open email'))),
          ],
        ),
      );
      if (action == null || !mounted) return;
      if (action == 'copy') {
        await Clipboard.setData(ClipboardData(text: msg));
      } else if (action == 'email_draft') {
        final uri = Uri(scheme: 'mailto', path: email, queryParameters: {
          'subject': t('دعوة إدارية إلى DEDA', 'DEDA admin invitation'),
          'body': msg,
        });
        if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
          throw StateError('deda-admin-mail-not-available');
        }
      } else { return; }
      await widget.admin.markScopedAdminInvitationShared(
        dedaPhone: widget.dedaPhone, inviteId: id, channel: action,
      );
      if (mounted) { _refresh(); ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(t(
          action == 'copy' ? 'نُسخت الدعوة.' : 'فُتحت مسودة البريد.',
          action == 'copy' ? 'Invitation copied.' : 'Email draft opened.',
        )))); }
    } catch (_) {
      if (mounted) { _refresh(); ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(t('تعذرت المشاركة: تحقق من صلاحية الدعوة.',
          'Share denied: verify invitation and authorization.')))); }
    } finally { if (mounted) setState(() => _mutating = false); }
  }


  /// Reuse the same verified list/tab, rather than adding a second recovery
  /// implementation. Only a fresh secondary manager can decide server-side.
  Future<void> _decideStaffRecovery(Map<String, dynamic> row,
      bool approve) async {
    if (_mutating || widget.collection != 'admin_recovery_requests' ||
        row['status'] != 'new') {
      return;
    }
    final id = (row['id'] ?? '').toString();
    if (!DedaIsolatedAdminProofPolicy.validScopedDocumentId(id)) return;
    String? reason = '';
    if (approve) {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: Text(t('موافقة على الاسترجاع', 'Approve staff recovery')),
          content: Text(t(
            'سيُصدر رمز استرجاع مدته 30 دقيقة بعد إثبات هوية الموظف وبوابة رقم DEDA.',
            'A 30-minute recovery code will be issued after checking the staff UID and DEDA phone gateway.',
          )),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: Text(t('إلغاء', 'Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: Text(t('موافقة', 'Approve')),
            ),
          ],
        ),
      );
      if (accepted != true) return;
    } else {
      final controller = TextEditingController();
      try {
        reason = await showDialog<String>(
          context: context,
          builder: (dialog) => StatefulBuilder(
            builder: (dialog, refresh) => AlertDialog(
              title: Text(t('رفض طلب الاسترجاع', 'Reject recovery request')),
              content: TextField(
                controller: controller,
                maxLength: 400,
                maxLines: 3,
                onChanged: (_) => refresh(() {}),
                decoration: InputDecoration(
                  labelText: t('سبب الرفض', 'Rejection reason')),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialog),
                  child: Text(t('إلغاء', 'Cancel')),
                ),
                FilledButton(
                  onPressed: controller.text.trim().isEmpty
                      ? null : () => Navigator.pop(
                          dialog, controller.text.trim()),
                  child: Text(t('رفض', 'Reject')),
                ),
              ],
            ),
          ),
        );
      } finally {
        controller.dispose();
      }
      if (reason == null) return;
    }
    if (!mounted) return;
    setState(() => _mutating = true);
    try {
      await widget.admin.decideScopedStaffRecovery(
        dedaPhone: widget.dedaPhone,
        requestId: id,
        approve: approve,
        rejectionReason: reason,
      );
      if (mounted) {
        _refresh();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(t(
            approve ? 'تم إصدار رمز الاسترجاع.' : 'تم رفض الطلب وتسجيل السبب.',
            approve ? 'Recovery code issued.' : 'Recovery rejected with reason.',
          )),
        ));
      }
    } catch (_) {
      if (mounted) {
        _refresh();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(t(
            'لم يكتمل القرار: تحقق من صلاحية المدير وربط حساب الموظف.',
            'Decision denied: verify manager authority and staff binding.',
          )),
        ));
      }
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  String _isolatedAuditActionLabel(String value) {
    const ar = <String, String>{
      'admin_member_created': 'إضافة عضو إداري',
      'admin_member_updated': 'تعديل عضو/صلاحيات',
      'admin_member_deleted': 'حذف عضو إداري',
      'admin_invite_created': 'إنشاء دعوة عضو إداري',
      'admin_invite_shared': 'مشاركة دعوة إدارية',
      'support_deleted': 'حذف رسالة دعم',
      'support_bulk_deleted': 'حذف مجموعة رسائل دعم',
      'support_restored': 'استرجاع رسالة دعم',
      'support_permanently_deleted': 'حذف رسالة دعم نهائيًا',
      'published_place_hidden': 'إخفاء مكان من الخريطة',
      'published_place_restored': 'إظهار مكان على الخريطة',
      'published_place_deleted': 'حذف مكان من الخريطة',
      'published_place_restored_from_trash': 'استرجاع مكان محذوف',
      'published_place_permanently_deleted': 'حذف مكان نهائيًا',
      'admin_invite_cancelled': 'إلغاء دعوة إدارية',
      'admin_invite_accepted': 'تفعيل دعوة إدارية',
      'admin_access_suspended': 'إيقاف وصول عضو مؤقتًا',
      'admin_password_reset_sent': 'إرسال رابط إعادة تعيين كلمة المرور',
      'admin_member_access_removed': 'إزالة صلاحية عضو إداري',
      'admin_sessions_revoked': 'تسجيل خروج من جميع الأجهزة',
      'admin_temporary_password_reset': 'إنشاء رمز دخول مؤقت',
      'admin_first_login_completed': 'اكتمال أول دخول',
      'admin_signed_in': 'تسجيل دخول إداري',
      'admin_signed_out': 'تسجيل خروج إداري',
      'admin_profile_normalized': 'تهيئة بيانات الحساب الإداري',
      'admin_display_name_updated': 'تعديل الاسم الإداري',
      'recovery_approved': 'اعتماد استرجاع الدخول',
      'recovery_rejected': 'رفض استرجاع الدخول',
      'read_user_account': 'مشاهدة حساب مستخدم',
      'account_deletion_status_changed': 'تحديث طلب حذف حساب',
      'road_hazard_deleted': 'حذف بلاغ طريق',
      'request_viewed': 'مشاهدة طلب',
      'support_replied': 'الرد على الدعم',
      'support_status_changed': 'تغيير حالة الدعم',
      'place_status_changed': 'تغيير حالة طلب مكان',
      'place_approved': 'اعتماد مكان',
    };
    return widget.isArabic
        ? (ar[value] ?? value)
        : value.replaceAll('_', ' ');
  }


  String _isolatedAuditTargetLabel(Map<String, dynamic> data) {
    final action = (data['action'] ?? '').toString();
    if (action == 'read_user_account') {
      final name = (data['targetUserName'] ?? '').toString().trim();
      final phone = (data['targetUserPhone'] ?? '').toString().trim();
      if (name.isNotEmpty && phone.isNotEmpty) {
        return '$name • \u200E$phone\u200E';
      }
      if (name.isNotEmpty) return name;
      if (phone.isNotEmpty) return '\u200E$phone\u200E';
      return t('بيانات غير مكتملة', 'Incomplete profile');
    }
    return (data['targetAdminName'] ?? data['targetUserName'] ??
        data['targetUserPhone'] ?? data['targetId'] ??
        data['sourceId'] ?? '').toString().trim();
  }

  String _timestamp(dynamic value) {
    if (value is! Timestamp) return '';
    final date = value.toDate().toLocal();
    return date.toString().substring(0, 16);
  }

  Widget _record(Map<String, dynamic> data) {
    // Show only existing human-readable fields, not raw Firestore records,
    // internal tokens, private maps or free-form audit metadata.
    final user = widget.collection == 'users';
    final team = widget.collection == 'admins';
    final invite = widget.collection == 'admin_invites';
    final recovery = widget.collection == 'admin_recovery_requests';
    // Exact original audit labels, actor, role, time, target and reason,
    // using existing server-scoped read and shared original formatters.
    // Never show raw audit maps, internal tokens, or credentials.
    if (widget.collection == 'admin_audit') {
      final target = _isolatedAuditTargetLabel(data);
      final reason = (data['reason'] ?? '').toString().trim();
      final actor = (data['adminName'] ??
          t('الإدارة', 'Administration')).toString();
      return Card(
        child: ListTile(
          leading: const Icon(Icons.fact_check_outlined,
              color: Color(0xFF17652F)),
          title: Text(_isolatedAuditActionLabel((data['action'] ?? '').toString()),
            style: const TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Text(
            actor + ' • ' +
            dedaAdminRoleLabel(widget.isArabic, data['adminRole']) +
            '\n' + dedaAdminTimestamp(data['createdAt']) +
            (target.isEmpty ? '' :
                '\n' + t('الهدف: ', 'Target: ') + target) +
            (reason.isEmpty ? '' :
                '\n' + t('السبب: ', 'Reason: ') + reason),
          ),
        ),
      );
    }
    final title = recovery ? (data['fullName'] ?? '').toString()
        : (team || invite)
        ? (data['displayName'] ?? data['name'] ?? '').toString()
        : user ? (data['name'] ?? '').toString()
            : (data['action'] ?? '').toString();
    final subtitle = recovery
        ? (data['email'] ?? '').toString()
        : (team || invite)
        ? (data['email'] ?? '').toString()
        : user ? (data['phone'] ?? '').toString()
            : (data['adminName'] ?? '').toString();
    final detail = recovery ? (data['status'] ?? '').toString()
        : team ? (data['role'] ?? '').toString()
        : invite ? (data['status'] ?? '').toString()
        : user ? (data['accountType'] ?? '').toString()
        : _timestamp(data['createdAt']);
    final subordinate = const <String>{
      'deputy_manager', 'employee', 'province_agent',
    }.contains((data['role'] ?? '').toString().trim().toLowerCase());
    final canSuspend = team && data['active'] == true && subordinate;
    final canCancel = invite && data['status'] == 'pending' && subordinate;
    final canRecover = recovery && data['status'] == 'new';
    return Card(
      child: ListTile(
        onTap: user && !_openingUser
            ? () => _openUser((data['id'] ?? '').toString()) : null,
        leading: user ? Icon(
          (data['name'] ?? '').toString().trim().isEmpty ||
                  (data['phone'] ?? '').toString().trim().isEmpty
              ? Icons.person_off_outlined : Icons.person_outline,
        ) : null,
        title: Text(title.isEmpty ? '—' : title),
        subtitle: Text(subtitle),
        trailing: (team && subordinate) || canCancel || canRecover
            ? PopupMenuButton<String>(
                enabled: !_mutating,
                tooltip: t('إجراءات الإدارة', 'Administration actions'),
                itemBuilder: (_) => [
                  if (canRecover) PopupMenuItem(value: 'approveRecovery',
                    child: Text(t('موافقة وإصدار رمز', 'Approve recovery'))),
                  if (canRecover) PopupMenuItem(value: 'rejectRecovery',
                    child: Text(t('رفض الطلب', 'Reject recovery'))),
                  if (team) PopupMenuItem(value: 'edit',
                    child: Text(t('تعديل', 'Edit'))),
                  if (canSuspend) PopupMenuItem(value: 'suspend',
                    child: Text(t('تعليق', 'Suspend'))),
                  if (team) PopupMenuItem(value: 'reset',
                    child: Text(t('رابط كلمة المرور', 'Password reset'))),
                  if (team) PopupMenuItem(value: 'remove',
                    child: Text(t('إزالة الوصول', 'Remove access'))),
                  if (canCancel) PopupMenuItem(value: 'share',
                    child: Text(t('مشاركة', 'Share'))),
                  if (canCancel) PopupMenuItem(value: 'cancel',
                    child: Text(t('إلغاء الدعوة', 'Cancel invitation'))),
                ],
                onSelected: (action) {
                  switch (action) {
                    case 'approveRecovery': _decideStaffRecovery(data, true); break;
                    case 'rejectRecovery': _decideStaffRecovery(data, false); break;
                    case 'edit': _editMember(data); break;
                    case 'suspend': _suspendMember(data); break;
                    case 'reset': _resetMemberPassword(data); break;
                    case 'remove': _removeMemberAccess(data); break;
                    case 'share': _shareInvitation(data); break;
                    case 'cancel': _cancelInvitation(data); break;
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(detail), const Icon(Icons.more_vert),
                  ]),
                ),
              )
            : Text(detail),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _rows,
      builder: (context, snapshot) {
        // A pending refresh must never leave previously fetched privileged
        // rows visible if a new server proof is denied or connectivity fails.
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(t(
                  'تعذر التحقق من صلاحيات القراءة من الخادم.',
                  'Could not verify read access from the server.',
                )),
                TextButton(
                  onPressed: _refresh,
                  child: Text(t('إعادة المحاولة', 'Retry')),
                ),
              ],
            ),
          );
        }
        final rows = snapshot.data!;
        final search = _userSearch.text.trim().toLowerCase();
        final filtered = widget.collection == 'users'
            ? (rows.where((user) {
                final haystack = <String>[
                  (user['name'] ?? '').toString(),
                  (user['phone'] ?? '').toString(),
                  (user['accountType'] ?? '').toString(),
                ].join(' ').toLowerCase();
                return search.isEmpty || haystack.contains(search);
              }).toList()
                ..sort((a, b) => (a['name'] ?? '').toString()
                    .compareTo((b['name'] ?? '').toString())))
            : rows;
        return Column(
          children: [
            if (widget.collection == 'users')
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                child: TextField(
                  controller: _userSearch,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: t('بحث بالاسم أو الهاتف',
                        'Search name or phone'),
                    prefixIcon: const Icon(Icons.search),
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Wrap(
                spacing: 8,
                children: [
                  if (widget.collection == 'admin_invites')
                    FilledButton.icon(
                      onPressed: _mutating ? null : _createInvitation,
                      icon: const Icon(Icons.person_add_alt_1_outlined),
                      label: Text(t('دعوة موظف', 'Invite staff')),
                    ),
                  TextButton.icon(
                    onPressed: _mutating ? null : _refresh,
                    icon: const Icon(Icons.refresh),
                    label: Text(t('تحديث من الخادم', 'Refresh from server')),
                  ),
                ],
              ),
            ),
            Expanded(
              child: filtered.isEmpty
                  ? Center(child: Text(t('لا توجد نتائج.', 'No results.')))
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: filtered.length,
                      itemBuilder: (context, index) => _record(filtered[index]),
                    ),
            ),
          ],
        );
      },
    );
  }
}


/// Management of existing manager entrance phone gateways using only the
/// independently authenticated secondary administrator. No public Auth writes.
class _DedaIsolatedManagerGatewaysTab extends StatefulWidget {
  final DedaIsolatedAdminIdentity admin;
  final String dedaPhone;
  final bool isArabic;

  const _DedaIsolatedManagerGatewaysTab({
    required this.admin,
    required this.dedaPhone,
    required this.isArabic,
  });

  @override
  State<_DedaIsolatedManagerGatewaysTab> createState() =>
      _DedaIsolatedManagerGatewaysTabState();
}

class _DedaIsolatedManagerGatewaysTabState
    extends State<_DedaIsolatedManagerGatewaysTab> {
  late Future<List<Map<String, dynamic>>> _rows;
  bool _mutating = false;

  String t(String ar, String en) => widget.isArabic ? ar : en;

  @override
  void initState() {
    super.initState();
    _rows = _fetch();
  }

  Future<List<Map<String, dynamic>>> _fetch() =>
      widget.admin.readScopedGeneralManagerGateways(
        dedaPhone: widget.dedaPhone,
      );

  void _refresh() => setState(() => _rows = _fetch());

  Future<void> _add() async {
    if (_mutating) return;
    final phone = TextEditingController();
    try {
      final value = await showDialog<String>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: Text(t('إضافة رقم دخول للمدير العام',
              'Add general-manager gateway')),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(t('يجب أن يكون الرقم حساب DEDA نشطاً. لن يُنشأ حساب إداري جديد.',
                'The phone must already be an active DEDA account; no admin account will be created.')),
            const SizedBox(height: 12),
            TextField(
              controller: phone,
              keyboardType: TextInputType.phone,
              textDirection: TextDirection.ltr,
              maxLength: 16,
              decoration: InputDecoration(
                labelText: t('رقم DEDA', 'DEDA phone'),
                hintText: '07XXXXXXXXX',
              ),
            ),
          ]),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: Text(t('إلغاء', 'Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, phone.text.trim()),
              child: Text(t('إضافة', 'Add')),
            ),
          ],
        ),
      );
      if (value == null || value.isEmpty || !mounted) return;
      setState(() => _mutating = true);
      try {
        await widget.admin.addScopedGeneralManagerGateway(
          dedaPhone: widget.dedaPhone, targetPhone: value,
        );
        if (mounted) {
          _refresh();
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(t('أُضيفت بوابة المدير العام بنجاح.',
                'Manager gateway added.')),
          ));
        }
      } catch (_) {
        if (mounted) {
          _refresh();
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(t('لم تُضف البوابة: تحقق من الرقم والتخويل وعدم تكرار الهاتف.',
                'Gateway denied: verify account, authority, and duplicate phone.')),
          ));
        }
      } finally {
        if (mounted) setState(() => _mutating = false);
      }
    } finally {
      phone.dispose();
    }
  }

  Future<void> _remove(Map<String, dynamic> row) async {
    if (_mutating) return;
    final phone = (row['id'] ?? '').toString();
    final reason = TextEditingController();
    try {
      final confirmedReason = await showDialog<String>(
        context: context,
        builder: (dialog) => StatefulBuilder(
          builder: (dialog, rebuild) => AlertDialog(
            title: Text(t('حذف بوابة رقم المدير',
                'Remove manager phone gateway')),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(t('تُزال بوابة الهاتف فقط دون حذف حساب DEDA أو المدير. '
                  'البوابة الأقدم بحسب الرقم محمية من الحذف.',
                  'Only the phone gateway will be removed. DEDA and administrator accounts stay unchanged. '
                  'The lowest-numbered active gateway is protected.')),
              const SizedBox(height: 8),
              SelectableText(phone, textDirection: TextDirection.ltr),
              TextField(
                controller: reason, maxLength: 400, maxLines: 2,
                decoration: InputDecoration(labelText: t('السبب', 'Reason')),
                onChanged: (_) => rebuild(() {}),
              ),
            ]),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialog),
                child: Text(t('إلغاء', 'Cancel')),
              ),
              FilledButton(
                onPressed: reason.text.trim().isEmpty
                    ? null : () => Navigator.pop(dialog, reason.text.trim()),
                child: Text(t('تأكيد الحذف', 'Confirm removal')),
              ),
            ],
          ),
        ),
      );
      if (confirmedReason == null || !mounted) return;
      setState(() => _mutating = true);
      try {
        await widget.admin.removeScopedGeneralManagerGateway(
          dedaPhone: widget.dedaPhone,
          targetPhone: phone, reason: confirmedReason,
        );
        if (mounted) {
          _refresh();
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(t('أُزيلت بوابة الهاتف فقط مع سجل تدقيق.',
                'Phone gateway removed with audit.')),
          ));
        }
      } catch (_) {
        if (mounted) {
          _refresh();
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(t('رُفض الحذف لحماية آخر بوابة أو لتغيّر صلاحيات المدير.',
                'Removal denied to protect manager access or changed authorization.')),
          ));
        }
      } finally {
        if (mounted) setState(() => _mutating = false);
      }
    } finally {
      reason.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _rows,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return Center(child: TextButton(
            onPressed: _refresh,
            child: Text(t('تعذر التحقق من الخادم. إعادة المحاولة',
                'Server check failed. Retry')),
          ));
        }
        final rows = snapshot.data!;
        final active = rows.where((row) =>
            DedaIsolatedAdminProofPolicy.activeGeneralManagerGateway(
              accountKey: (row['id'] ?? '').toString(),
              entry: row,
            )).toList();
        final protectedId =
            active.isEmpty ? '' : (active.first['id'] ?? '').toString();
        final selfPhone =
            DedaIsolatedAdminProofPolicy.canonicalIraqiPhone(
              widget.dedaPhone,
            );
        return Column(children: [
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Wrap(spacing: 8, children: [
              FilledButton.icon(
                onPressed: _mutating ? null : _add,
                icon: const Icon(Icons.add_moderator_outlined),
                label: Text(t('إضافة رقم', 'Add phone')),
              ),
              TextButton.icon(
                onPressed: _mutating ? null : _refresh,
                icon: const Icon(Icons.refresh),
                label: Text(t('تحديث من الخادم', 'Refresh from server')),
              ),
            ]),
          ),
          Expanded(
            child: rows.isEmpty
                ? Center(child: Text(t('لا توجد بوابات.', 'No gateways.')))
                : ListView.builder(
                    itemCount: rows.length,
                    itemBuilder: (context, index) {
                      final row = rows[index];
                      final id = (row['id'] ?? '').toString();
                      final removable = !_mutating && active.length > 1 &&
                          protectedId != id && selfPhone != id &&
                          DedaIsolatedAdminProofPolicy.activeGeneralManagerGateway(
                            accountKey: id, entry: row,
                          );
                      return ListTile(
                        leading: id == protectedId
                            ? const Icon(Icons.lock_outline)
                            : const Icon(Icons.phone_android_outlined),
                        title: Text((row['phone'] ?? id).toString()),
                        subtitle: Text(id == protectedId
                            ? t('البوابة المحمية', 'Protected gateway')
                            : (row['status'] ?? '').toString()),
                        trailing: IconButton(
                          tooltip: t('إزالة بوابة الهاتف', 'Remove gateway'),
                          icon: const Icon(Icons.remove_circle_outline),
                          onPressed: removable ? () => _remove(row) : null,
                        ),
                      );
                    },
                  ),
          ),
        ]);
      },
    );
  }
}

/// General-manager-only list for published places and both protected
/// archives. All records are re-fetched from server after each mutation.
class _DedaIsolatedManagerPlacesTab extends StatefulWidget {
  final DedaIsolatedAdminIdentity admin;
  final String dedaPhone;
  final String sourceCollection;
  final bool isArabic;

  const _DedaIsolatedManagerPlacesTab({
    required this.admin,
    required this.dedaPhone,
    required this.sourceCollection,
    required this.isArabic,
  });

  @override
  State<_DedaIsolatedManagerPlacesTab> createState() =>
      _DedaIsolatedManagerPlacesTabState();
}

class _DedaIsolatedManagerPlacesTabState
    extends State<_DedaIsolatedManagerPlacesTab> {
  late Future<DedaIsolatedManagerPage> _page;
  QueryDocumentSnapshot<Map<String, dynamic>>? _pageStart;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>?> _back = [];
  bool _mutating = false;

  String t(String ar, String en) => widget.isArabic ? ar : en;

  bool get _isArchive => widget.sourceCollection != 'published_places';

  String get _targetCollection =>
      widget.sourceCollection == 'admin_trash_place_requests'
          ? 'place_requests' : 'published_places';

  @override
  void initState() {
    super.initState();
    _page = _fetch();
  }

  Future<DedaIsolatedManagerPage> _fetch() =>
      widget.admin.readScopedManagerPage(
        dedaPhone: widget.dedaPhone,
        collection: widget.sourceCollection,
        startAfter: _pageStart,
        pageSize: 50,
      );

  void _refresh() => setState(() {
    _pageStart = null;
    _back.clear();
    _page = _fetch();
  });

  void _next(DedaIsolatedManagerPage page) {
    if (_mutating || page.nextCursor == null) return;
    setState(() {
      _back.add(_pageStart);
      _pageStart = page.nextCursor;
      _page = _fetch();
    });
  }

  void _previous() {
    if (_mutating || _back.isEmpty) return;
    setState(() {
      _pageStart = _back.removeLast();
      _page = _fetch();
    });
  }

  Future<String?> _confirm({
    required String id,
    required String action,
  }) async {
    final permanent = action == 'permanent';
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, refreshDialog) => AlertDialog(
          title: Text(permanent
              ? t('حذف نهائي لا يمكن التراجع عنه', 'Irreversible deletion')
              : action == 'restore'
                  ? t('تأكيد استرجاع السجل', 'Confirm restore')
                  : action == 'hide'
                      ? t('إخفاء المكان عن الخارطة', 'Hide place from map')
                      : action == 'show'
                          ? t('إظهار المكان مجدداً', 'Show place again')
                          : t('نقل إلى محذوفات المدير العام',
                              'Move to general-manager trash')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text("${t('المعرّف', 'Record ID')}: $id"),
              if (permanent) ...[
                const SizedBox(height: 12),
                Text(t(
                  'الحذف النهائي يمحو النسخة المؤرشفة فقط. '
                  'اكتب المعرّف كاملاً للتأكيد.',
                  'Permanently removes ONLY the archived record. '
                  'Type its full ID to confirm.',
                )),
                const SizedBox(height: 8),
                TextField(
                  controller: controller,
                  onChanged: (_) => refreshDialog(() {}),
                  decoration: InputDecoration(
                    labelText: t('اكتب المعرّف', 'Type the ID'),
                  ),
                ),
              ] else
                Text(t(
                  'لا تُعدّل بيانات المستخدمين أو حساباتهم.',
                  'User accounts and ownership are unchanged.',
                )),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(t('إلغاء', 'Cancel')),
            ),
            FilledButton(
              onPressed: permanent && controller.text.trim() != id
                  ? null : () => Navigator.pop(dialogContext, id),
              child: Text(t('تأكيد', 'Confirm')),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _mutate(String id, String action) async {
    if (_mutating) return;
    final confirmation = await _confirm(id: id, action: action);
    if (!mounted || confirmation != id || _mutating) return;
    setState(() => _mutating = true);
    try {
      if (action == 'hide' || action == 'show') {
        if (_isArchive) {
          throw StateError('deda-admin-visibility-source-invalid');
        }
        await widget.admin.setScopedPublishedVisibility(
          dedaPhone: widget.dedaPhone,
          placeId: id,
          hide: action == 'hide',
        );
      } else {
        await widget.admin.mutateScopedPlaceArchive(
          dedaPhone: widget.dedaPhone,
          sourceCollection: _targetCollection,
          recordId: id,
          action: action,
          permanentConfirmation: action == 'permanent' ? confirmation : null,
        );
      }
      if (mounted) {
        _refresh();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(t('تم تسجيل العملية في سجل الإدارة.',
              'Operation completed and audited.')),
        ));
      }
    } catch (_) {
      if (mounted) {
        _refresh(); // Discard any stale privileged result on failure.
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(t(
            'تعذرت العملية. تحقق من صلاحية المدير وحالة السجل.',
            'Operation denied; verify GM access and current record state.',
          )),
        ));
      }
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  Widget _record(Map<String, dynamic> data) {
    final id = (data['id'] ?? '').toString();
    final placeName = (data['placeName'] ?? data['name'] ?? '').toString();
    final approvalNumber = (data['approvalNumber'] ?? '').toString();
    final published = data['published'] == true;
    final managerHidden = data['hiddenByManager'] == true;
    final canRestoreHidden = !published && managerHidden &&
        data['hiddenAt'] is Timestamp &&
        (data['hiddenByUid'] ?? '').toString().trim().isNotEmpty;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(placeName.isEmpty ? id : placeName,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            Text(id, style: Theme.of(context).textTheme.bodySmall),
            if (approvalNumber.isNotEmpty)
              Text(approvalNumber),
            _isolatedPlaceField(t('المحافظة', 'Governorate'),
                data['governorate']),
            _isolatedPlaceField(t('العنوان', 'Address'), data['address']),
            _isolatedPlaceField(t('الهاتف', 'Phone'),
                data['phone'], ltr: true),
            _isolatedPlaceField(t('نوع المكان', 'Place type'),
                data['category']),
            _isolatedPlaceField(t('أوقات العمل', 'Opening hours'),
                data['openingHours']),
            _isolatedPlaceField(t('الوصف', 'Description'),
                data['description']),
            _isolatedPlaceField(t('حالة التواجد', 'Availability'),
                data['isAvailableNow'] == true
                    ? t('متواجد الآن', 'Available now')
                    : t('غير متواجد حاليًا', 'Not available now')),
            if (_isolatedValidPlaceCoords(
                data['latitude'], data['longitude']))
              OutlinedButton.icon(
                onPressed: _mutating ? null : () => _openIsolatedPlaceMap(
                  context: context, isArabic: widget.isArabic,
                  placeName: placeName,
                  latitude: data['latitude'] as num,
                  longitude: data['longitude'] as num,
                ),
                icon: const Icon(Icons.map_outlined),
                label: Text(t('فتح الموقع على الخريطة',
                    'Open place on map')),
              ),
            if (!_isArchive && (data['accountKey'] ?? '')
                .toString().trim().isNotEmpty)
              OutlinedButton.icon(
                onPressed: _mutating ? null :
                    () => _showIsolatedOwnerNoticeComposer(
                  context: context, admin: widget.admin,
                  dedaPhone: widget.dedaPhone,
                  isArabic: widget.isArabic,
                  sourceCollection: 'published_places',
                  sourceId: id, placeName: placeName,
                  accountKey: (data['accountKey'] ?? '').toString().trim(),
                ),
                icon: const Icon(Icons.notifications_active_outlined),
                label: Text(t('إرسال إشعار لصاحب المكان',
                    'Notify place owner')),
              ),
            if (!_isArchive && !published)
              Text(managerHidden
                  ? t('مخفي بواسطة الإدارة', 'Hidden by administration')
                  : t('غير منشور', 'Not published')),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 8, children: [
              if (!_isArchive && published && !managerHidden)
                OutlinedButton.icon(
                  onPressed: _mutating ? null : () => _mutate(id, 'hide'),
                  icon: const Icon(Icons.visibility_off_outlined),
                  label: Text(t('إخفاء المكان', 'Hide place')),
                ),
              if (!_isArchive && canRestoreHidden)
                OutlinedButton.icon(
                  onPressed: _mutating ? null : () => _mutate(id, 'show'),
                  icon: const Icon(Icons.visibility_outlined),
                  label: Text(t('إظهار المكان', 'Restore visibility')),
                ),
              if (!_isArchive)
                OutlinedButton.icon(
                  onPressed: _mutating ? null : () => _mutate(id, 'trash'),
                  icon: const Icon(Icons.delete_outline),
                  label: Text(t('إلى المحذوفات', 'Move to trash')),
                ),
              if (_isArchive) ...[
                FilledButton.icon(
                  onPressed: _mutating ? null : () => _mutate(id, 'restore'),
                  icon: const Icon(Icons.restore),
                  label: Text(t('استرجاع', 'Restore')),
                ),
                OutlinedButton.icon(
                  onPressed: _mutating ? null :
                      () => _mutate(id, 'permanent'),
                  icon: const Icon(Icons.delete_forever_outlined),
                  label: Text(t('حذف نهائي', 'Delete permanently')),
                ),
              ],
            ]),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!dedaIsolatedAdminIdentityEnabled) {
      return const SizedBox.shrink();
    }
    return FutureBuilder<DedaIsolatedManagerPage>(
      future: _page,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return Center(child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(t('لا يمكن قراءة السجلات من الخادم.',
                  'Could not verify archive access from server.')),
              TextButton(
                onPressed: _refresh,
                child: Text(t('إعادة المحاولة', 'Retry')),
              ),
            ],
          ));
        }
        final page = snapshot.data!;
        final rows = page.rows;
        return Column(children: [
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton.icon(
              onPressed: _mutating ? null : _refresh,
              icon: const Icon(Icons.refresh),
              label: Text(t('تحديث من الخادم', 'Refresh from server')),
            ),
          ),
          Expanded(
            child: rows.isEmpty
                ? Center(child: Text(t('لا توجد سجلات.', 'No records.')))
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: rows.length,
                    itemBuilder: (context, index) => _record(rows[index]),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(children: [
              Text("${t('صفحة', 'Page')} ${_back.length + 1}"),
              const Spacer(),
              TextButton.icon(
                onPressed: !_mutating && _back.isNotEmpty
                    ? _previous : null,
                icon: const Icon(Icons.chevron_left),
                label: Text(t('السابق', 'Previous')),
              ),
              TextButton.icon(
                onPressed: !_mutating && page.nextCursor != null
                    ? () => _next(page) : null,
                icon: const Icon(Icons.chevron_right),
                label: Text(t('التالي', 'Next')),
              ),
            ]),
          ),
        ]);
      },
    );
  }
}

/// Uses the same original green card and place-request position.
/// No automatic approval runs on the phone. ON stays disabled until BOTH
/// owner build gate and trusted backend worker actually confirm readiness.
class _DedaIsolatedPlaceAutoApprovalToggle extends StatefulWidget {
  final DedaIsolatedAdminIdentity admin;
  final String dedaPhone;
  final bool isArabic;

  const _DedaIsolatedPlaceAutoApprovalToggle({
    required this.admin,
    required this.dedaPhone,
    required this.isArabic,
  });

  @override
  State<_DedaIsolatedPlaceAutoApprovalToggle> createState() =>
      _DedaIsolatedPlaceAutoApprovalToggleState();
}

class _DedaIsolatedPlaceAutoApprovalToggleState
    extends State<_DedaIsolatedPlaceAutoApprovalToggle> {
  bool _loading = true;
  bool _saving = false;
  String? _error;
  DedaIsolatedAutomationState _state = (
    enabled: false, backendReady: false, revision: 0,
  );

  String t(String ar, String en) => widget.isArabic ? ar : en;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final status = await widget.admin.readScopedPlaceAutoApproval(
        dedaPhone: widget.dedaPhone,
      );
      if (!mounted) return;
      setState(() {
        _state = status;
        _error = null;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = t('تعذر التحقق من إعداد الاعتماد التلقائي.',
            'Could not verify the auto-approval setting.');
        _loading = false;
      });
    }
  }

  Future<void> _change(bool enabled) async {
    if (_saving || _loading || _error != null ||
        (enabled && (!_state.backendReady ||
            !DedaLaunchFeatureGates.serverFeaturesEnabled))) return;
    setState(() => _saving = true);
    try {
      await widget.admin.setScopedPlaceAutoApproval(
        dedaPhone: widget.dedaPhone,
        enabled: enabled,
        expectedRevision: _state.revision,
      );
      await _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(t('تم تحديث إعداد الاعتماد بعد التحقق من الخادم.',
              'Auto-approval setting updated after server verification.')),
        ));
      }
    } catch (_) {
      await _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(t('لم يتغير الإعداد؛ راجع صلاحية المدير وجاهزية الخادم.',
              'Setting unchanged; verify manager role and worker readiness.')),
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final note = !DedaLaunchFeatureGates.serverFeaturesEnabled
        ? t('الاعتماد التلقائي مؤجّل؛ تبقى مراجعة الطلبات يدوية.',
            'Auto-approval is deferred; requests stay manually reviewed.')
        : !_state.backendReady
            ? _state.enabled
                ? t('الخدمة لم تتأكد؛ يمكن إيقافها بأمان.',
                    'Worker not confirmed; OFF remains available.')
                : t('خادم الاعتماد لم يثبت جاهزيته؛ التشغيل محجوب.',
                    'Worker readiness not verified; ON is blocked.')
            : t(_state.enabled ? 'مفعّل للطلبات الجديدة' : 'مطفأ — مراجعة يدوية',
                _state.enabled ? 'ON for new requests' : 'OFF — manual review');
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 12, 6),
      child: Card(
        color: const Color(0xFFEAF4EA),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF9FBDA3)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: _loading
              ? const Center(child: Padding(
                  padding: EdgeInsets.all(12),
                  child: CircularProgressIndicator(),
                ))
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        t('الاعتماد التلقائي للطلبات الجديدة فقط',
                            'Auto-approve NEW place requests only'),
                        style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 15,
                        ),
                      ),
                      subtitle: Text(t(
                        'الطلبات الجديدة المكتملة تُنشر تلقائياً بعد 30 ثانية؛ '
                        'القديمة تبقى يدوية.',
                        'New complete requests publish after 30 seconds; '
                        'old requests stay manual.',
                      ), style: const TextStyle(fontSize: 12.5)),
                      value: _state.enabled,
                      onChanged: _saving || _error != null ||
                          (!_state.backendReady && !_state.enabled)
                          ? null : _change,
                    ),
                    Text(_error ?? note,
                      style: TextStyle(fontSize: 12,
                          color: _error == null
                              ? const Color(0xFF3B6043)
                              : const Color(0xFF9C3324))),
                    if (_error != null)
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: TextButton.icon(
                          onPressed: _refresh,
                          icon: const Icon(Icons.refresh, size: 18),
                          label: Text(t('إعادة المحاولة', 'Retry')),
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _DedaIsolatedRequestTab extends StatefulWidget {
  final DedaIsolatedAdminIdentity admin;
  final String dedaPhone;
  final String collection;
  final bool isArabic;
  final Map<String, dynamic> profile;

  const _DedaIsolatedRequestTab({
    required this.admin,
    required this.dedaPhone,
    required this.collection,
    required this.isArabic,
    required this.profile,
  });

  @override
  State<_DedaIsolatedRequestTab> createState() => _DedaIsolatedRequestTabState();
}

class _DedaIsolatedRequestTabState extends State<_DedaIsolatedRequestTab> {
  late Stream<QuerySnapshot<Map<String, dynamic>>> _stream;
  QueryDocumentSnapshot<Map<String, dynamic>>? _pageStart;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>?> _back = [];
  int _pageEpoch = 0;
  bool _sending = false;
  String _section = 'current';
  final Set<String> _viewing = <String>{};
  // Explicit selection across fresh server pages; never selects unseen rows.
  final Set<String> _selectedSupportIds = <String>{};

  String t(String ar, String en) => widget.isArabic ? ar : en;

  @override
  void initState() {
    super.initState();
    _stream = _watchPage();
  }

  // Keep live server-confirmed updates for every page. The 51st result is
  // ONLY a pagination sentinel; it is never displayed as a request card.
  Stream<QuerySnapshot<Map<String, dynamic>>> _watchPage() =>
      widget.admin.watchScopedAdminRequests(
        dedaPhone: widget.dedaPhone,
        collection: widget.collection,
        maxItems: 51,
        startAfter: _pageStart,
      );

  void _nextPage(QuerySnapshot<Map<String, dynamic>> snapshot) {
    if (_sending || snapshot.docs.length <= 50) return;
    final cursor = snapshot.docs[49];
    if (cursor.metadata.isFromCache || cursor.metadata.hasPendingWrites) return;
    setState(() {
      _back.add(_pageStart);
      _pageStart = cursor;
      _pageEpoch++;
      _stream = _watchPage();
    });
  }

  void _previousPage() {
    if (_sending || _back.isEmpty) return;
    setState(() {
      _pageStart = _back.removeLast();
      _pageEpoch++;
      _stream = _watchPage();
    });
  }

  bool get _canReply => widget.collection == 'support_requests' &&
      DedaIsolatedAdminProofPolicy.allowsPermission(
        admin: widget.profile, permission: 'supportReply',
      );

  bool get _canArchivePlace => widget.collection == 'place_requests' &&
      DedaIsolatedAdminProofPolicy.allowsPermission(
        admin: widget.profile, permission: 'managePlaceArchives',
      );

  bool get _canTrashSupport => widget.collection == 'support_requests' &&
      widget.profile['role'] == 'general_manager' &&
      DedaIsolatedAdminProofPolicy.allowsPermission(
        admin: widget.profile, permission: 'supportRead',
      );

  Future<void> _archiveSupportRequest(String id) async {
    if (!_canTrashSupport || _sending) return;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(t('نقل رسالة الدعم إلى المحذوفات',
            'Move support message to trash')),
        content: Text(t('ستبقى الرسالة ومرفقاتها محفوظة ويمكن استرجاعها.',
            'Message and attachments remain safely restorable.')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(t('إلغاء', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(t('نقل للمحذوفات', 'Move to trash')),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted || _sending) return;
    setState(() => _sending = true);
    try {
      await widget.admin.mutateScopedSupportTrash(
        dedaPhone: widget.dedaPhone,
        requestId: id, action: 'trash',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(t('تم حفظ رسالة الدعم في المحذوفات مع سجل التدقيق.',
              'Support message archived with its audit.')),
        ));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(t('تعذرت الأرشفة. تحقق من صلاحية المدير العام.',
              'Archive denied; verify GM permission.')),
        ));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// Stage2 OFF: select only fresh, visible support IDs across pages.
  /// The bulk action reuses the existing individual GM transaction/audit.
  void _selectVisibleSupportRequests(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> visible,
    SnapshotMetadata metadata,
  ) {
    if (!_canTrashSupport || _sending ||
        metadata.isFromCache || metadata.hasPendingWrites) return;
    final ids = visible.where((doc) =>
        !doc.metadata.isFromCache &&
        !doc.metadata.hasPendingWrites &&
        DedaIsolatedAdminProofPolicy.validScopedDocumentId(doc.id))
        .map((doc) => doc.id).toSet();
    if (ids.isEmpty) return;
    if (_selectedSupportIds.union(ids).length > 100) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(t('الحد الأعلى 100 رسالة، ألغِ بعض التحديد أولاً.',
            'Maximum 100 messages; clear some selections first.')),
      ));
      return;
    }
    setState(() => _selectedSupportIds.addAll(ids));
  }

  Future<void> _archiveSelectedSupportRequests() async {
    if (!_canTrashSupport || _sending || _selectedSupportIds.isEmpty) return;
    final targets = _selectedSupportIds.toList(growable: false);
    if (targets.length > 100 || targets.any((id) =>
        !DedaIsolatedAdminProofPolicy.validScopedDocumentId(id))) {
      throw StateError('deda-isolated-support-bulk-selection-denied');
    }
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(t('نقل رسائل الدعم المحددة',
            'Move selected support messages to trash')),
        content: Text(t(
          'عدد الرسائل المحددة: ${targets.length}. سيتم نقل كل رسالة '
          'بمعاملة مستقلة وتدقيق إداري، ويمكن استرجاعها. '
          'إذا فشلت إحداها يتوقف النقل وتبقى البقية دون تغيير.',
          'Selected messages: ${targets.length}. Every message uses its '
          'own checked transaction and admin audit and can be restored. '
          'If one fails, the remaining messages will not be changed.',
        )),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(t('إلغاء', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(t('تأكيد النقل', 'Confirm move')),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted || _sending) return;
    setState(() => _sending = true);
    final completed = <String>[];
    var interrupted = false;
    try {
      for (final id in targets) {
        if (!mounted) { interrupted = true; break; }
        try {
          // Revalidates secondary Auth, GM permission, server documents,
          // original/archive conflict and audit atomically for EACH ID.
          await widget.admin.mutateScopedSupportTrash(
            dedaPhone: widget.dedaPhone, requestId: id, action: 'trash',
          );
          completed.add(id);
        } catch (_) {
          interrupted = true;
          break; // Do not continue after revoked access/conflict.
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _selectedSupportIds.removeAll(completed);
          _sending = false;
        });
      }
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(interrupted
          ? t('تم نقل ${completed.length} من ${targets.length}. '
              'توقفت الدفعة عند أول تعارض؛ تحقق من البقية.',
              'Moved ${completed.length} of ${targets.length}; stopped at '
              'first conflict. Review the remaining selection.')
          : t('تم نقل ${completed.length} رسالة مع سجل تدقيق لكل رسالة.',
              'Moved ${completed.length} messages, each with its own audit.')),
    ));
  }

  Future<void> _openSupportTrash() async {
    if (!_canTrashSupport || _sending) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => DedaStage2IsolatedSupportTrashPage(
        admin: widget.admin, dedaPhone: widget.dedaPhone,
        isArabic: widget.isArabic,
      ),
    ));
  }


  bool _matchesSection(String status, String section) {
    if (widget.collection == 'support_requests') {
      if (section == 'approved') return status == 'replied';
      if (section == 'rejected') return status == 'closed';
      return status == 'new' || status == 'in_progress';
    }
    if (section == 'approved') return status == 'approved';
    if (section == 'rejected') return status == 'rejected';
    return status != 'approved' && status != 'rejected';
  }

  Widget _sectionChip({
    required String section,
    required String arLabel,
    required String enLabel,
    required int count,
  }) => ChoiceChip(
    selected: _section == section,
    selectedColor: const Color(0xFFDDEDDD),
    label: Text(t(arLabel, enLabel) + ' (' + count.toString() + ')'),
    onSelected: _sending ? null : (_) => setState(() => _section = section),
  );

  Future<void> _markFirstViewed(String id) async {
    if (_viewing.contains(id) || !mounted) return;
    _viewing.add(id);
    try {
      await widget.admin.markScopedAdminRequestViewed(
        dedaPhone: widget.dedaPhone,
        collection: widget.collection,
        requestId: id,
      );
    } catch (_) {
      // Keep the original unread marker if the server refuses the write.
      // The live listener will display the true server-confirmed status.
    } finally {
      _viewing.remove(id);
    }
  }

  Future<void> _viewLinkedUser(String ownerUid) async {
    if (_sending || !DedaIsolatedAdminProofPolicy.validScopedDocumentId(
            ownerUid) ||
        !DedaIsolatedAdminProofPolicy.allowsPermission(
          admin: widget.profile, permission: 'viewUsers',
        )) {
      return;
    }
    setState(() => _sending = true);
    try {
      final snap = await widget.admin.readScopedUserAccountSnapshot(
        dedaPhone: widget.dedaPhone, userUid: ownerUid,
      );
      if (!mounted) return;
      final profile = Map<String, dynamic>.from(
        snap['profile'] as Map? ?? const <String, dynamic>{},
      );
      final related = snap['relatedAccessible'] == true;
      final places = snap['publishedPlaces'] as List? ?? const [];
      final requests = snap['placeRequests'] as List? ?? const [];
      final support = snap['supportRequests'] as List? ?? const [];
      final truncated = Map<String, dynamic>.from(
        snap['relatedTruncatedCollections'] as Map? ?? const {},
      );
      String count(List values, String collection) =>
          values.length.toString() +
          (truncated[collection] == true ? '+' : '');
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(t('حساب صاحب الطلب • قراءة فقط',
              'Request owner • read only')),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _isolatedPlaceField(t('الاسم', 'Name'), profile['name']),
                  _isolatedPlaceField(t('الهاتف', 'Phone'),
                      profile['phone'], ltr: true),
                  _isolatedPlaceField(t('نوع الحساب', 'Account type'),
                      profile['accountType']),
                  const Divider(),
                  if (related) ...[
                    _isolatedPlaceField(t('الأماكن المنشورة',
                        'Published places'),
                        count(places, 'published_places')),
                    _isolatedPlaceField(t('طلبات الأماكن',
                        'Place requests'),
                        count(requests, 'place_requests')),
                    _isolatedPlaceField(t('رسائل الدعم',
                        'Support requests'),
                        count(support, 'support_requests')),
                    if (places.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(t('أماكن المستخدم', 'User places'),
                          style: const TextStyle(
                              fontWeight: FontWeight.w800)),
                      ...places.take(10).map((raw) {
                        final p = Map<String, dynamic>.from(raw as Map);
                        return ListTile(
                          dense: true,
                          title: Text((p['placeName'] ?? '').toString()),
                          subtitle: Text(
                            (p['approvalNumber'] ?? '').toString()),
                        );
                      }),
                    ],
                  ] else
                    Text(t('بيانات الأماكن والدعم محجوبة لصلاحية هذا الدور.',
                        'Related records are restricted for this admin role.')),
                  const SizedBox(height: 8),
                  Text(t('تم تسجيل هذه المشاهدة إدارياً بلا تعديل حساب المستخدم.',
                      'The view was audited without changing the user account.')),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(t('إغلاق', 'Close')),
            ),
          ],
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(t('تعذر عرض الحساب أو التحقق من الصلاحيات.',
              'Could not verify permissions or read this user.')),
        ));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _setStatus(String id, String status) async {
    if (!_canReply || _sending) return;
    setState(() => _sending = true);
    try {
      await widget.admin.updateScopedSupportStatus(
        dedaPhone: widget.dedaPhone, requestId: id, status: status,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t('تم التحديث.', 'Updated.'))),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t('تعذر التحديث.', 'Could not update.'))),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<String?> _editApprovalMessage(Map<String, dynamic> prepared) async {
    final controller = TextEditingController(
      text: (prepared['message'] ?? '').toString(),
    );
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(t('رسالة اعتماد المكان', 'Place approval message')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(t(
                'راجع الرسالة ورقم الاعتماد قبل إرسال الموافقة.',
                'Review the message and approval number before approving.',
              )),
              const SizedBox(height: 8),
              Text(
                '${(prepared['approvalNumber'] ?? '').toString()} • '
                '${(prepared['approvalDate'] ?? '').toString()}',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                minLines: 5,
                maxLines: 8,
                maxLength: 4000,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(t('إلغاء', 'Cancel')),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(
              dialogContext, controller.text.trim(),
            ),
            icon: const Icon(Icons.send_outlined),
            label: Text(t('إرسال واعتماد', 'Send & approve')),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _approvePlace(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    if (widget.collection != 'place_requests' || _sending ||
        !DedaIsolatedAdminProofPolicy.placeApprovalAllowed(
          admin: widget.profile, request: doc.data(),
          requestId: doc.id,
          expectedStatus: (doc.data()['status'] ?? '').toString(),
        )) {
      return;
    }
    final expectedStatus = (doc.data()['status'] ?? '').toString();
    setState(() => _sending = true);
    try {
      final prepared = await widget.admin.prepareScopedPlaceApproval(
        dedaPhone: widget.dedaPhone,
        requestId: doc.id,
        expectedStatus: expectedStatus,
      );
      if (!mounted) {
        return;
      }
      final message = await _editApprovalMessage(prepared);
      if (message == null || !mounted) {
        return;
      }
      await widget.admin.finalizeScopedPlaceApproval(
        dedaPhone: widget.dedaPhone,
        requestId: doc.id,
        expectedStatus: expectedStatus,
        expectedApprovalNumber:
            (prepared['approvalNumber'] ?? '').toString(),
        expectedApprovalDate: (prepared['approvalDate'] ?? '').toString(),
        message: message,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t(
            'تم اعتماد المكان ونشره وتسجيل القرار.',
            'The place was approved, published and audited.',
          ))),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t(
            'تعذر الاعتماد. تأكد من الصلاحيات وبيانات المكان.',
            'Approval failed. Verify permissions and place details.',
          ))),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _archivePlaceRequest(String id) async {
    if (!_canArchivePlace || _sending) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(t('نقل الطلب إلى محذوفات المدير العام',
            'Move request to general-manager trash')),
        content: Text("${t('تأكيد نقل الطلب إلى المحذوفات؟',
            'Move this request to recoverable trash?')}\n$id"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(t('إلغاء', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(t('تأكيد', 'Confirm')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || _sending) return;
    setState(() => _sending = true);
    try {
      await widget.admin.mutateScopedPlaceArchive(
        dedaPhone: widget.dedaPhone,
        sourceCollection: 'place_requests',
        recordId: id,
        action: 'trash',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(t('نُقل الطلب إلى المحذوفات.',
              'Request archived for recovery.')),
        ));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(t(
            'تعذّر نقل الطلب؛ راجع حالة الصلاحيات والسجل.',
            'Could not archive the request; verify rights and record.',
          )),
        ));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<String?> _askPlaceReason(String targetStatus) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(targetStatus == 'rejected'
            ? t('سبب رفض الطلب', 'Reason for rejection')
            : t('التعديل المطلوب', 'Required changes')),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 2,
          maxLines: 4,
          maxLength: 1000,
          decoration: InputDecoration(
            labelText: t('اكتب السبب', 'Write a reason'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(t('إلغاء', 'Cancel')),
          ),
          FilledButton(
            onPressed: () {
              final reason = controller.text.trim();
              if (reason.isNotEmpty) {
                Navigator.pop(dialogContext, reason);
              }
            },
            child: Text(t('تأكيد', 'Confirm')),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _placeReview(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
    String targetStatus,
  ) async {
    if (widget.collection != 'place_requests' || _sending) return;
    final data = doc.data();
    final expectedStatus = (data['status'] ?? '').toString();
    // This local check only controls buttons. The isolated transport
    // re-checks server role, gateway, activation and latest record.
    final noteRequired = targetStatus != 'reviewing';
    if (!DedaIsolatedAdminProofPolicy.placeReviewMutationAllowed(
      admin: widget.profile,
      request: data,
      requestId: doc.id,
      expectedStatus: expectedStatus,
      targetStatus: targetStatus,
      note: noteRequired ? 'required' : null,
    )) {
      return;
    }
    final note = noteRequired ? await _askPlaceReason(targetStatus) : null;
    if (noteRequired && (note == null || note.isEmpty)) {
      return;
    }
    if (!mounted || _sending) {
      return;
    }
    setState(() => _sending = true);
    try {
      await widget.admin.updateScopedPlaceReview(
        dedaPhone: widget.dedaPhone,
        requestId: doc.id,
        expectedStatus: expectedStatus,
        targetStatus: targetStatus,
        note: note,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t('تم تسجيل قرار المراجعة.',
              'Review decision recorded.'))),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t(
            'تعذر حفظ القرار؛ تأكد من الصلاحيات والطلب الحالي.',
            'Could not save the decision; verify access and current status.',
          ))),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _reply(String id) async {
    if (!_canReply || _sending) return;
    final reply = TextEditingController();
    final message = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(t('رد الإدارة', 'Admin reply')),
        content: TextField(
          controller: reply,
          maxLines: 5,
          maxLength: 4000,
          decoration: InputDecoration(
            labelText: t('اكتب الرد', 'Write reply'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(t('إلغاء', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, reply.text.trim()),
            child: Text(t('إرسال', 'Send')),
          ),
        ],
      ),
    );
    reply.dispose();
    if (message == null || message.isEmpty || !mounted) return;
    setState(() => _sending = true);
    try {
      await widget.admin.replyToScopedSupport(
        dedaPhone: widget.dedaPhone, requestId: id, message: message,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t('تم إرسال الرد.', 'Reply sent.'))),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t('تعذر إرسال الرد.', 'Could not send reply.'))),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Widget _request(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final support = widget.collection == 'support_requests';
    final title = (data[support ? 'name' : 'placeName'] ?? doc.id).toString();
    final status = (data['status'] ?? '').toString();
    final canApprove = !support &&
        DedaIsolatedAdminProofPolicy.placeApprovalAllowed(
          admin: widget.profile,
          request: data,
          requestId: doc.id,
          expectedStatus: status,
        );
    bool canReview(String targetStatus) =>
        !support && DedaIsolatedAdminProofPolicy.placeReviewMutationAllowed(
          admin: widget.profile,
          request: data,
          requestId: doc.id,
          expectedStatus: status,
          targetStatus: targetStatus,
          note: targetStatus == 'reviewing' ? null : 'required',
        );
    return Card(
      child: ExpansionTile(
        key: ValueKey(doc.id),
        onExpansionChanged: (expanded) {
          if (expanded && data['firstViewedAt'] == null) {
            _markFirstViewed(doc.id);
          }
        },
        leading: Stack(
          clipBehavior: Clip.none,
          children: [
            Icon(support ? Icons.support_agent : Icons.storefront_outlined,
                color: const Color(0xFF17652F)),
            if (data['firstViewedAt'] == null &&
                status != 'approved' && status != 'rejected')
              const Positioned(
                right: -5, top: -5,
                child: CircleAvatar(
                  backgroundColor: Color(0xFFD62828), radius: 5),
              ),
          ],
        ),
        title: Text(title),
        subtitle: Text(status),
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text((data[support ? 'message' : 'description'] ?? '')
                .toString()),
          ),
          if ((data['ownerUid'] ?? '').toString().trim().isNotEmpty &&
              DedaIsolatedAdminProofPolicy.allowsPermission(
                admin: widget.profile, permission: 'viewUsers'))
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: OutlinedButton.icon(
                onPressed: _sending ? null : () => _viewLinkedUser(
                    (data['ownerUid'] ?? '').toString().trim()),
                icon: const Icon(Icons.visibility_outlined),
                label: Text(t('عرض حساب المستخدم • قراءة فقط',
                    'View user account • read only')),
              ),
            ),
          if (!support)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                '${t('المحافظة', 'Governorate')}: '
                '${(data['governorate'] ?? '').toString()}'
                ' • ${(data['address'] ?? '').toString()}',
              ),
            ),
          if (!support) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _isolatedPlaceField(t('نوع الطلب', 'Request type'),
                      data['requestType']),
                  _isolatedPlaceField(t('نوع المكان', 'Place type'),
                      data['category']),
                  _isolatedPlaceField(t('الهاتف', 'Phone'),
                      data['phone'], ltr: true),
                  _isolatedPlaceField(t('أوقات العمل', 'Opening hours'),
                      data['openingHours']),
                  _isolatedPlaceField(t('حالة التواجد', 'Availability'),
                    data['isAvailableNow'] == true
                        ? t('متواجد الآن', 'Available now')
                        : t('غير متواجد حاليًا', 'Not available now')),
                  _isolatedPlaceField(t('رقم الاعتماد', 'Approval number'),
                      data['approvalNumber']),
                  _isolatedPlaceField(t('ملاحظات الإدارة', 'Admin note'),
                      data['decisionNote']),
                  if (_isolatedValidPlaceCoords(
                      data['latitude'], data['longitude']))
                    OutlinedButton.icon(
                      onPressed: _sending ? null : () => _openIsolatedPlaceMap(
                        context: context, isArabic: widget.isArabic,
                        placeName: title,
                        latitude: data['latitude'] as num,
                        longitude: data['longitude'] as num,
                      ),
                      icon: const Icon(Icons.map_outlined),
                      label: Text(t('فتح الموقع على الخريطة',
                          'Open location on map')),
                    ),
                  if ((data['accountKey'] ?? '').toString().trim().isNotEmpty &&
                      DedaIsolatedAdminProofPolicy.allowsPermission(
                        admin: widget.profile, permission: 'viewPlaceRequests'))
                    OutlinedButton.icon(
                      onPressed: _sending ? null :
                          () => _showIsolatedOwnerNoticeComposer(
                        context: context, isArabic: widget.isArabic,
                        admin: widget.admin, dedaPhone: widget.dedaPhone,
                        sourceCollection: 'place_requests',
                        sourceId: doc.id, placeName: title,
                        accountKey: (data['accountKey'] ?? '').toString().trim(),
                      ),
                      icon: const Icon(Icons.notifications_active_outlined),
                      label: Text(t('إرسال إشعار لصاحب المكان',
                          'Notify place owner')),
                    ),
                ],
              ),
            ),
          ],
          if (support) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _isolatedPlaceField(t('نوع التواصل', 'Contact type'),
                      data['type']),
                  _isolatedPlaceField(t('الاسم', 'Name'), data['name']),
                  _isolatedPlaceField(t('الهاتف', 'Phone'),
                      data['phone'], ltr: true),
                  _isolatedPlaceField(t('رد الإدارة', 'Admin reply'),
                      data['adminReply']),
                  _isolatedPlaceField(t('المكان المرتبط', 'Linked place'),
                      data['linkedPlaceName'] ?? data['linkedPlaceId']),
                  if (_isolatedValidPlaceCoords(
                      data['linkedLatitude'], data['linkedLongitude']))
                    OutlinedButton.icon(
                      onPressed: _sending ? null : () => _openIsolatedPlaceMap(
                        context: context, isArabic: widget.isArabic,
                        placeName: (data['linkedPlaceName'] ?? '').toString(),
                        latitude: data['linkedLatitude'] as num,
                        longitude: data['linkedLongitude'] as num,
                      ),
                      icon: const Icon(Icons.map_outlined),
                      label: Text(t('فتح المكان المرتبط', 'Open linked place')),
                    ),
                ],
              ),
            ),
          ],
          if (support)
            _isolatedSupportPhotoGallery(
              context: context,
              isArabic: widget.isArabic,
              data: data,
            ),
          if (!support &&
              (canApprove || canReview('reviewing') ||
               canReview('needs_changes') ||
               canReview('rejected')))
            Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                if (canApprove)
                  FilledButton.icon(
                    onPressed: _sending ? null : () => _approvePlace(doc),
                    icon: const Icon(Icons.verified_outlined),
                    label: Text(t('اعتماد المكان', 'Approve place')),
                  ),
                if (canReview('reviewing'))
                  OutlinedButton(
                    onPressed: _sending ? null :
                        () => _placeReview(doc, 'reviewing'),
                    child: Text(t('قيد المراجعة', 'Reviewing')),
                  ),
                if (canReview('needs_changes'))
                  OutlinedButton(
                    onPressed: _sending ? null :
                        () => _placeReview(doc, 'needs_changes'),
                    child: Text(t('يحتاج تعديل', 'Needs changes')),
                  ),
                if (canReview('rejected'))
                  OutlinedButton(
                    onPressed: _sending ? null :
                        () => _placeReview(doc, 'rejected'),
                    child: Text(t('رفض الطلب', 'Reject request')),
                  ),
              ]),
            ),
          if (!support && _canArchivePlace)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: OutlinedButton.icon(
                  onPressed: _sending ? null :
                      () => _archivePlaceRequest(doc.id),
                  icon: const Icon(Icons.delete_outline),
                  label: Text(t('نقل الطلب للمحذوفات', 'Archive request')),
                ),
              ),
            ),
          if (support && _canTrashSupport)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: OutlinedButton.icon(
                  onPressed: _sending ? null :
                      () => _archiveSupportRequest(doc.id),
                  icon: const Icon(Icons.delete_outline),
                  label: Text(t('نقل رسالة الدعم إلى المحذوفات',
                      'Move support to trash')),
                ),
              ),
            ),
          if (support && _canReply)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Wrap(spacing: 8, children: [
                OutlinedButton(
                  onPressed: _sending ? null :
                      () => _setStatus(doc.id, 'in_progress'),
                  child: Text(t('قيد المعالجة', 'In progress')),
                ),
                FilledButton(
                  onPressed: _sending ? null : () => _reply(doc.id),
                  child: Text(t('إرسال رد', 'Reply')),
                ),
                OutlinedButton(
                  onPressed: _sending ? null :
                      () => _setStatus(doc.id, 'closed'),
                  child: Text(t('إغلاق', 'Close')),
                ),
              ]),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!dedaIsolatedAdminIdentityEnabled) {
      return const SizedBox.shrink();
    }
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      // Prevent the previous page's privileged rows from remaining visible
      // while the new page is still waiting for fresh server authorization.
      key: ValueKey(_pageEpoch),
      stream: _stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text(t(
            'تعذر تأكيد صلاحيات الإدارة من الخادم.',
            'Could not verify admin permissions from the server.',
          )));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final serverPage = snapshot.data!;
        final records = serverPage.docs.take(50).toList(growable: false);
        final hasNext = serverPage.docs.length > 50;
        int count(String section) => records.where((doc) =>
          _matchesSection((doc.data()['status'] ?? '').toString(), section))
          .length;
        final visible = records.where((doc) => _matchesSection(
          (doc.data()['status'] ?? '').toString(), _section,
        )).toList(growable: false);
        return Column(children: [
          if (widget.collection == 'place_requests' &&
              widget.profile['role'] == 'general_manager')
            _DedaIsolatedPlaceAutoApprovalToggle(
              admin: widget.admin,
              dedaPhone: widget.dedaPhone,
              isArabic: widget.isArabic,
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
            child: Column(children: [
              Text(t('إحصائية الصفحة الحالية فقط',
                  'Counts for this loaded page only'),
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 4),
              Wrap(spacing: 8, runSpacing: 4, children: [
                _sectionChip(section: 'current',
                    arLabel: 'الحالية', enLabel: 'Current',
                    count: count('current')),
                _sectionChip(section: 'approved',
                    arLabel: widget.collection == 'support_requests'
                        ? 'تم الرد' : 'المعتمدات',
                    enLabel: widget.collection == 'support_requests'
                        ? 'Replied' : 'Approved',
                    count: count('approved')),
                _sectionChip(section: 'rejected',
                    arLabel: widget.collection == 'support_requests'
                        ? 'المغلقة' : 'المرفوضات',
                    enLabel: widget.collection == 'support_requests'
                        ? 'Closed' : 'Rejected',
                    count: count('rejected')),
              ]),
            ]),
          ),
          if (_canTrashSupport)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                alignment: WrapAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: _sending || visible.isEmpty ||
                            serverPage.metadata.isFromCache ||
                            serverPage.metadata.hasPendingWrites
                        ? null : () => _selectVisibleSupportRequests(
                            visible, serverPage.metadata),
                    icon: const Icon(Icons.select_all),
                    label: Text(t('تحديد رسائل هذه الصفحة',
                        'Select this page')),
                  ),
                  if (_selectedSupportIds.isNotEmpty) ...[
                    TextButton.icon(
                      onPressed: _sending ? null : () =>
                          setState(() => _selectedSupportIds.clear()),
                      icon: const Icon(Icons.clear),
                      label: Text(t('إلغاء التحديد', 'Clear selection')),
                    ),
                    FilledButton.icon(
                      onPressed: _sending ? null : _archiveSelectedSupportRequests,
                      icon: const Icon(Icons.delete_outline),
                      label: Text(t('نقل المحدد', 'Move selected') +
                          ' (${_selectedSupportIds.length}/100)'),
                    ),
                  ],
                  TextButton.icon(
                    onPressed: _sending ? null : _openSupportTrash,
                    icon: const Icon(Icons.delete_sweep_outlined),
                    label: Text(t('محذوفات الدعم', 'Support trash')),
                  ),
                ],
              ),
            ),
          Expanded(
            child: visible.isEmpty
                ? Center(child: Text(t('لا توجد طلبات في هذه الصفحة.',
                    'No matching requests on this page.')))
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: visible.length,
                    itemBuilder: (context, index) => _request(visible[index]),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 12, vertical: 6,
            ),
            child: Row(children: [
              Text("${t('صفحة', 'Page')} ${_back.length + 1}"),
              const Spacer(),
              TextButton.icon(
                onPressed: !_sending && _back.isNotEmpty
                    ? _previousPage : null,
                icon: const Icon(Icons.chevron_left),
                label: Text(t('السابق', 'Previous')),
              ),
              TextButton.icon(
                onPressed: !_sending && hasNext
                    ? () => _nextPage(serverPage) : null,
                icon: const Icon(Icons.chevron_right),
                label: Text(t('التالي', 'Next')),
              ),
            ]),
          ),
        ]);
      },
    );
  }
}


/// A new invited staff member uses the second Firebase Auth, never the
/// currently logged-in public DEDA account. The legacy activation stays off.
class DedaStage2IsolatedInviteActivationPage extends StatefulWidget {
  final bool isArabic;
  final String dedaPhone;

  const DedaStage2IsolatedInviteActivationPage({
    super.key,
    required this.isArabic,
    required this.dedaPhone,
  });

  @override
  State<DedaStage2IsolatedInviteActivationPage> createState() =>
      _DedaStage2IsolatedInviteActivationPageState();
}

class _DedaStage2IsolatedInviteActivationPageState
    extends State<DedaStage2IsolatedInviteActivationPage> {
  final _email = TextEditingController();
  final _inviteId = TextEditingController();
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  String t(String ar, String en) => widget.isArabic ? ar : en;

  @override
  void dispose() {
    _email.dispose();
    _inviteId.dispose();
    _code.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _activate() async {
    if (_busy) return;
    final email = _email.text.trim().toLowerCase();
    final id = _inviteId.text.trim();
    final code = _code.text.trim();
    final password = _password.text;
    if (!RegExp(r'^[^@\s]+@[^@\s]+[.][^@\s]+$').hasMatch(email) ||
        !DedaIsolatedAdminProofPolicy.validScopedDocumentId(id) ||
        !RegExp(r'^[0-9]{8}$').hasMatch(code) ||
        password.length < 8 || password != _confirm.text) {
      setState(() => _error = t(
        'أكمل البريد ورقم الدعوة والرمز الصحيح وكلمتي مرور متطابقتين (8 أحرف على الأقل).',
        'Enter your email, invitation, 8-digit code and matching 8+ character passwords.',
      ));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final isolated = await DedaIsolatedAdminIdentity.open();
      await isolated.activateScopedAdminInvitation(
        dedaPhone: widget.dedaPhone,
        inviteId: id,
        email: email,
        activationCode: code,
        password: password,
      );
      final verifiedProfile = await isolated.readVerifiedAdminProfile(
        dedaPhone: widget.dedaPhone,
      );
      if (!mounted) {
        await isolated.signOutSecondaryAdmin();
        return;
      }
      Navigator.pushReplacement(
        context,
        MaterialPageRoute<void>(
          builder: (_) => DedaStage2IsolatedDashboardPage(
            isArabic: widget.isArabic,
            dedaPhone: widget.dedaPhone,
            admin: isolated,
            profile: verifiedProfile,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      final raw = error.toString();
      setState(() => _error = raw.contains('manager-repair-required') ||
              raw.contains('auth-cleanup-required')
          ? t(
              'تعذّر إكمال تنظيف سجل دعوة الإدارة؛ راجع المدير العام قبل إعادة التفعيل.',
              'Administrator invitation cleanup needs manager review before another attempt.',
            )
          : t(
              'التفعيل لم يكتمل؛ تأكد من ملكية رقم DEDA والدعوة والرمز واتصال الإنترنت.',
              'Activation not completed. Verify DEDA phone ownership, invitation, code and internet.',
            ));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(t('تفعيل دعوة الإدارة', 'Activate admin invitation')),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(t(
                  'التفعيل مرتبط بحساب DEDA الحالي، ويستخدم جلسة إدارة منفصلة.',
                  'Activation verifies this DEDA account and uses separate admin Auth.',
                ), textAlign: TextAlign.center),
                const SizedBox(height: 12),
                TextField(
                  controller: _email, enabled: !_busy,
                  textDirection: TextDirection.ltr,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(labelText: t('البريد', 'Email')),
                ),
                TextField(
                  controller: _inviteId, enabled: !_busy,
                  textDirection: TextDirection.ltr,
                  decoration: InputDecoration(
                    labelText: t('معرّف الدعوة', 'Invitation ID')),
                ),
                TextField(
                  controller: _code, enabled: !_busy, maxLength: 8,
                  keyboardType: TextInputType.number,
                  textDirection: TextDirection.ltr,
                  decoration: InputDecoration(
                    labelText: t('رمز التفعيل 8 أرقام', '8-digit activation code')),
                ),
                TextField(
                  controller: _password, enabled: !_busy,
                  obscureText: true,
                  textDirection: TextDirection.ltr,
                  decoration: InputDecoration(
                    labelText: t('كلمة المرور', 'New password')),
                ),
                TextField(
                  controller: _confirm, enabled: !_busy,
                  obscureText: true,
                  textDirection: TextDirection.ltr,
                  onSubmitted: (_) => _activate(),
                  decoration: InputDecoration(
                    labelText: t('تأكيد كلمة المرور', 'Confirm password')),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(_error!,
                      style: const TextStyle(color: Colors.red)),
                  ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _busy ? null : _activate,
                  icon: _busy ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ) : const Icon(Icons.verified_user_outlined),
                  label: Text(t(
                    'تفعيل الحساب الإداري', 'Activate administrator')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
