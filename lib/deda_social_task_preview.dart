import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:url_launcher/url_launcher.dart';
import 'deda_social_task_live_service.dart';

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
class DedaSocialTaskUserPreviewPage extends StatelessWidget {
  const DedaSocialTaskUserPreviewPage({
    super.key, required this.isArabic,
  });
  final bool isArabic;

  String t(String ar, String en) => isArabic ? ar : en;

  Uri? safeTaskUrl(Map<String, dynamic> data) {
    final text = (data['url'] ?? '').toString();
    final platform = (data['platform'] ?? '').toString();
    final uri = Uri.tryParse(text);
    if (uri == null || uri.scheme != 'https' || uri.userInfo.isNotEmpty ||
        uri.hasPort || uri.hasFragment) return null;
    if (platform == 'telegram' &&
        !<String>{'t.me', 'telegram.me'}.contains(uri.host.toLowerCase())) {
      return null;
    }
    const allowed = <String, List<String>>{
      'facebook': ['facebook.com', 'fb.com', 'fb.watch'],
      'youtube': ['youtube.com', 'youtu.be'],
      'instagram': ['instagram.com'],
      'tiktok': ['tiktok.com'],
    };
    if (allowed.containsKey(platform) &&
        !allowed[platform]!.any((host) =>
            uri.host == host || uri.host.endsWith('.$host'))) {
      return null;
    }
    if (!<String>{'telegram', ...allowed.keys}.contains(platform)) return null;
    return uri;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(t('مهام التواصل الاجتماعي', 'Social tasks')),
        backgroundColor: const Color(0xFF0B3156),
        foregroundColor: Colors.white,
      ),
      backgroundColor: const Color(0xFFF8FAF2),
      body: Firebase.apps.isEmpty
          ? Center(child: Text(t('لا توجد مهمة منشورة بعد.',
              'No published task yet.')))
          : StreamBuilder(
              stream: const DedaLiveSocialTaskService().watchPublished(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text(t(
                    'تعذر تحميل المهام المنشورة. حاول لاحقاً.',
                    'Could not load published social tasks.')));
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final doc = snapshot.data!;
                final data = doc.data();
                if (!doc.exists || data == null ||
                    data['rewardsEnabled'] != false ||
                    data['rewardClaimMode'] !=
                      'blocked-until-trusted-proof-and-ssv-ledger') {
                  return Center(child: Text(t(
                    'لا توجد مهمة منشورة حالياً.',
                    'There is no published task yet.')));
                }
                final uri = safeTaskUrl(data);
                if (uri == null) {
                  return Center(child: Text(t(
                    'بيانات المهمة غير صالحة، ولا يمكن فتحها.',
                    'Task link is invalid.')));
                }
                final title = (data['title'] ?? '').toString();
                final amount = data['rewardAmount'];
                final unit = (data['rewardUnit'] ?? '').toString();
                final rewardName = unit == 'diamonds'
                  ? t('ماسات', 'diamonds')
                  : unit == 'coins' ? t('عملات', 'coins')
                  : t('نقاط', 'points');
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
                            Text(uri.toString(),
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.white)),
                            const SizedBox(height: 10),
                            Text(t(
                              'المكافأة المحددة: $amount $rewardName (غير متاحة للاستلام حتى التحقق)',
                              'Configured reward: $amount $rewardName (not claimable until verification)'),
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
                      'عرض المهمة ونقل المستخدم للقناة لا يثبت الاشتراك. لن تُمنح أي مكافأة قبل توفر تحقق موثوق، ولن يُخصم شيء من رصيد المدير العام.',
                      'Opening a channel is not proof of subscription. No reward is granted until server verification.'),
                      textAlign: TextAlign.center),
                  ],
                );
              },
            ),
    );
  }
}
