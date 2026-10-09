import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:url_launcher/url_launcher.dart';
import 'deda_social_task_live_service.dart';
import 'deda_telegram_verified_reward_service.dart';

/// Isolated social-task UI: never enters the existing eight task IDs, Firebase,
/// or the reward ledger. The release build keeps this preview disabled.
class DedaSocialTaskPreview {
  const DedaSocialTaskPreview._();
  static const bool visible = bool.fromEnvironment(
    'DEDA_SOCIAL_TASKS_UI_PREVIEW',
    defaultValue: false,
  );
}

class DedaSocialTaskCatalog {
  const DedaSocialTaskCatalog._();

  static const List<String> platforms = <String>[
    'facebook', 'telegram', 'youtube', 'instagram', 'tiktok', 'other',
  ];
  static const List<String> actions = <String>[
    'follow', 'like_post', 'watch_video', 'like_video', 'other',
  ];

  static String platformLabel(String id, bool ar) {
    switch (id) {
      case 'facebook': return ar ? 'صفحة فيس بوك' : 'Facebook page';
      case 'telegram': return ar ? 'تلي جرام' : 'Telegram';
      case 'youtube': return ar ? 'يوتيوب' : 'YouTube';
      case 'instagram': return ar ? 'إنستغرام' : 'Instagram';
      case 'tiktok': return ar ? 'تيك توك' : 'TikTok';
      default: return ar ? 'أخرى' : 'Other';
    }
  }

  static String actionLabel(String id, bool ar) {
    switch (id) {
      case 'follow': return ar ? 'متابعة صفحة أو قناة' : 'Follow page or channel';
      case 'like_post': return ar ? 'إعجاب بمنشور' : 'Like post';
      case 'watch_video': return ar ? 'مشاهدة فيديو' : 'Watch video';
      case 'like_video': return ar ? 'إعجاب بفيديو' : 'Like video';
      default: return ar ? 'أخرى' : 'Other';
    }
  }
}

/// Intentionally 78-88px high on normal phones versus ordinary task min 94px.
class DedaSocialTaskCompactCard extends StatelessWidget {
  const DedaSocialTaskCompactCard({
    super.key, required this.isArabic, required this.onTap,
  });
  final bool isArabic;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('socialTaskCompactCard'),
      constraints: const BoxConstraints(minHeight: 78),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0D4778), Color(0xFF082E59), Color(0xFF061F3E)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8C56C)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      child: Row(
        textDirection: TextDirection.ltr,
        children: [
          Container(
            width: 36, height: 36,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [Color(0xFFFFE9A8), Color(0xFFE0AE39)],
              ),
            ),
            child: const Icon(Icons.people_alt_rounded,
              color: Color(0xFF0B3156), size: 22),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  isArabic ? 'مهام التواصل الاجتماعي' : 'Social tasks',
                  key: const Key('socialTaskCardTitle'),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    color: Color(0xFFFFDE7C),
                    fontSize: 13.4, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 2),
                Text(
                  isArabic
                      ? 'تابع صفحاتنا وتفاعل مع المنشورات والفيديوهات'
                      : 'Follow pages and engage with posts and videos for rewards',
                  maxLines: 3, overflow: TextOverflow.visible,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    color: Colors.white, fontSize: 9.8,
                    height: 1.12, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          const SizedBox(width: 7),
          SizedBox(
            width: 54, height: 31,
            child: Material(
              color: const Color(0xFFE8C56C),
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                key: const Key('socialTaskCardOpen'),
                onTap: onTap, borderRadius: BorderRadius.circular(10),
                child: Center(
                  child: Text(isArabic ? 'عرض' : 'View',
                    style: const TextStyle(
                      color: Color(0xFF0B3156), fontSize: 11,
                      fontWeight: FontWeight.w900)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Published social config is displayed only after a trusted backend publish.
/// There are deliberately NO reward-claim or wallet-write methods on this page.
/// User view: fetch only today's signed-in Firestore server document.
/// Reads before Baghdad midnight are denied by Firestore Security Rules.
/// No offline future cache, payout, ad claim, or client-side unlock.
class DedaSocialTaskUserPreviewPage extends StatefulWidget {
  const DedaSocialTaskUserPreviewPage({
    super.key, required this.isArabic, this.onDiamondsGranted,
  });
  final bool isArabic;
  final Future<void> Function()? onDiamondsGranted;

  @override
  State<DedaSocialTaskUserPreviewPage> createState() =>
      _DedaSocialTaskUserPreviewPageState();
}

class _DedaSocialTaskUserPreviewPageState
    extends State<DedaSocialTaskUserPreviewPage> {
  Future<Map<String, dynamic>?>? _taskFuture;
  final _service = const DedaLiveSocialTaskService();
  final _telegram = const DedaTelegramVerifiedRewardService();
  bool _verificationBusy = false;

  String t(String ar, String en) => widget.isArabic ? ar : en;

  @override
  void initState() {
    super.initState();
    if (Firebase.apps.isNotEmpty) _taskFuture = _service.publishedToday();
  }

  void _refresh() {
    if (Firebase.apps.isEmpty) return;
    setState(() => _taskFuture = _service.publishedToday());
  }

  Uri? safeTaskUrl(Map<String, dynamic> data) {
    final text = (data['url'] ?? '').toString();
    final uri = Uri.tryParse(text);
    if (data['platform'] != 'telegram' || data['action'] != 'follow' ||
        !DedaLiveSocialTaskService.allowedTelegramLink(text) ||
        uri == null || uri.scheme != 'https' || uri.host != 't.me') {
      return null;
    }
    return uri;
  }

  Future<void> _startBotVerification() async {
    if (_verificationBusy) return;
    setState(() => _verificationBusy = true);
    try {
      final result = await _telegram.beginTelegramLink();
      if (!mounted) return;
      final outcome = (result['outcome'] ?? '').toString();
      final text = (result['botLink'] ?? '').toString();
      final link = Uri.tryParse(text);
      if (outcome == 'started' && link != null &&
          link.scheme == 'https' && link.host == 't.me') {
        final opened = await launchUrl(
          link, mode: LaunchMode.externalApplication);
        if (!mounted) return;
        if (!opened) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(t('تعذر فتح بوت التحقق.',
                'Could not open the verification bot.'))));
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(t(
            outcome == 'wait-before-new-link'
                ? 'انتظر دقيقة قبل طلب رابط جديد.'
                : 'التحقق عبر تليجرام غير جاهز حالياً.',
            outcome == 'wait-before-new-link'
                ? 'Please wait a minute before requesting another link.'
                : 'Telegram verification is not available yet.'))));
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(t('تعذر الاتصال بخادم التحقق، حاول لاحقاً.',
            'Verification server unavailable. Try again later.'))));
    } finally {
      if (mounted) setState(() => _verificationBusy = false);
    }
  }

  Future<void> _claimVerifiedTelegramDiamonds() async {
    if (_verificationBusy) return;
    setState(() => _verificationBusy = true);
    try {
      final result = await _telegram.claimAfterMembershipCheck();
      if (!mounted) return;
      final outcome = (result['outcome'] ?? '').toString();
      if (outcome == 'awarded') {
        if (widget.onDiamondsGranted != null) {
          await widget.onDiamondsGranted!();
        }
        if (!mounted) return;
      }
      final message = outcome == 'awarded'
          ? t('مبروك! انضافت 10 ماسات إلى رصيدك 💎',
              '10 diamonds have been credited to your balance! 💎')
          : outcome == 'already-rewarded'
              ? t('استلمت مكافأة تليجرام سابقاً.',
                  'You already received the Telegram reward.')
              : t('افتح القناة واشترك واربط حسابك بالبوت، وبعدها حاول مجدداً.',
                  'Join the channel, link via the bot, then try again.');
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(t('فشل التحقق من الخادم. لم تُمنح أي مكافأة.',
            'Server verification failed. No reward was granted.'))));
    } finally {
      if (mounted) setState(() => _verificationBusy = false);
    }
  }

  Widget _empty() => Center(child: Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(t('لا توجد مهمة تليجرام منشورة لهذا اليوم.',
          'There is no Telegram task for today.'),
          textAlign: TextAlign.center),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: _refresh,
        icon: const Icon(Icons.refresh),
        label: Text(t('تحديث من الخادم', 'Refresh from server')),
      ),
    ],
  ));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(t('مهام التواصل الاجتماعي', 'Social tasks')),
        backgroundColor: const Color(0xFF0B3156),
        foregroundColor: Colors.white,
      ),
      backgroundColor: const Color(0xFFF8FAF2),
      body: _taskFuture == null ? _empty()
        : FutureBuilder<Map<String, dynamic>?>(
            future: _taskFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(t('تعذر الاتصال بخادم Firebase. حاول مرة أخرى.',
                        'Firebase connection failed. Try again.'),
                        textAlign: TextAlign.center),
                    TextButton(onPressed: _refresh,
                      child: Text(t('إعادة المحاولة', 'Retry'))),
                  ],
                ));
              }
              final data = snapshot.data;
              if (data == null || data['rewardsEnabled'] != false ||
                  data['rewardClaimMode'] !=
                    'blocked-until-trusted-proof-and-ssv-ledger') {
                return _empty();
              }
              final uri = safeTaskUrl(data);
              if (uri == null) return _empty();
              final title = (data['title'] ?? '').toString();
              final amount = data['rewardAmount'];
              final unit = (data['rewardUnit'] ?? '').toString();
              final rewardName = unit == 'diamonds'
                  ? t('ماسات', 'diamonds')
                  : unit == 'coins'
                    ? t('عملات', 'coins') : t('نقاط', 'points');
              return ListView(
                padding: const EdgeInsets.all(18),
                children: [
                  Card(
                    color: const Color(0xFF0B3156),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                      side: const BorderSide(color: Color(0xFFE8C56C)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Icon(Icons.people_alt_rounded,
                              color: Color(0xFFFFD76A), size: 38),
                          const SizedBox(height: 12),
                          Text(title, textAlign: TextAlign.center,
                              key: const Key('publishedSocialTaskTitle'),
                              style: const TextStyle(
                                color: Color(0xFFFFD76A), fontSize: 20,
                                fontWeight: FontWeight.bold)),
                          const SizedBox(height: 12),
                          Text(uri.toString(), textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white)),
                          const SizedBox(height: 10),
                          Text(t(
                            'المكافأة المحددة: $amount $rewardName (غير قابلة للاستلام حالياً)',
                            'Configured reward: $amount $rewardName (claim disabled)'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white)),
                          const SizedBox(height: 18),
                          FilledButton.icon(
                            key: const Key('openPublishedSocialTask'),
                            icon: const Icon(Icons.open_in_new),
                            label: Text(t('افتح القناة', 'Open channel')),
                            onPressed: () async {
                              final opened = await launchUrl(uri,
                                  mode: LaunchMode.externalApplication);
                              if (!opened && context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(t(
                                    'تعذر فتح الرابط.', 'Could not open link.'))));
                              }
                            },
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFFE8C56C),
                              foregroundColor: const Color(0xFF0B3156)),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(t(
                    'فتح الرابط لا يثبت الاشتراك. لا توجد مكافآت قابلة للصرف بهذه النسخة، ولا خصم من محفظة المدير.',
                    'Opening the link is not subscription proof; payouts are disabled.'),
                    textAlign: TextAlign.center),
                  TextButton.icon(
                    onPressed: _refresh,
                    icon: const Icon(Icons.refresh),
                    label: Text(t('تحديث', 'Refresh')),
                  ),
                ],
              );
            },
          ),
    );
  }
}
