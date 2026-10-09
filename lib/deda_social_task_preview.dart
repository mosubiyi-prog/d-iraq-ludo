import 'package:flutter/material.dart';

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
                      ? 'تابع صفحاتنا وتفاعل مع المنشورات والفيديوهات لتحصل على مكافآت مميزة'
                      : 'Follow pages and engage with posts and videos for rewards',
                  maxLines: 2, overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    color: Colors.white, fontSize: 10.2,
                    height: 1.16, fontWeight: FontWeight.w600),
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

class DedaSocialTaskUserPreviewPage extends StatelessWidget {
  const DedaSocialTaskUserPreviewPage({
    super.key, required this.isArabic,
  });
  final bool isArabic;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(isArabic ? 'مهام التواصل الاجتماعي' : 'Social tasks'),
        backgroundColor: const Color(0xFF0B3156),
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            isArabic
                ? 'معاينة تصميم فقط. لا توجد مهام منشورة ولا مكافآت. يجب التحقق من المتابعة أو الإعجاب قبل منح أي جائزة.'
                : 'Design preview only. No published tasks or rewards. Follow or like actions require verification.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16),
          ),
        ),
      ),
    );
  }
}
