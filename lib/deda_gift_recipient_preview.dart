import 'package:flutter/material.dart';

/// Read-only preview before an administrative gift is sent.
///
/// Displays only the recipient's PUBLIC DEDA identity. Never exposes raw
/// phone, UID, email, address, PIN, or any hidden Firestore account fields.
/// The transfer still re-verifies the stable public ID on the backend.
class DedaGiftRecipientPreview extends StatelessWidget {
  const DedaGiftRecipientPreview({
    super.key,
    required this.profile,
    required this.isArabic,
  });

  final Map<String, dynamic> profile;
  final bool isArabic;

  static int _boundedInt(dynamic value, int min, int max, int fallback) {
    if (value is! num) return fallback;
    final n = value.toInt();
    return n >= min && n <= max ? n : fallback;
  }

  @override
  Widget build(BuildContext context) {
    final name = (profile['displayName'] ?? 'DEDA').toString().trim();
    final id = (profile['publicId'] ?? '').toString().trim().toUpperCase();
    final frameStyle = _boundedInt(profile['frameStyle'], 0, 5, 0);
    final avatarStyle = _boundedInt(profile['avatarStyle'], 0, 5, 0);
    final level = _boundedInt(profile['level'], 1, 999, 1);
    const frameColors = [
      Color(0xFF07A9C5), Color(0xFFE0AB39), Color(0xFF8751CE),
      Color(0xFF238A50), Color(0xFFDA5B45), Color(0xFF195BAF),
    ];
    final frameColor = frameColors[frameStyle];
    final avatarIcon = avatarStyle.isEven
        ? Icons.face_rounded
        : Icons.face_3_rounded;

    return Semantics(
      container: true,
      label: isArabic
          ? 'الملف العام للمستلم، ${name.isEmpty ? "DEDA" : name}، $id'
          : 'Recipient public profile, ${name.isEmpty ? "DEDA" : name}, $id',
      child: Container(
        key: const Key('dedaVerifiedGiftRecipientProfile'),
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFFFFCF0), Color(0xFFE8F6FD)],
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE6C66A)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              isArabic ? 'تأكد من حساب المستلم' : 'Verify recipient before sending',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF173F62),
                fontWeight: FontWeight.w900,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 9),
            Row(
              children: [
                Container(
                  width: 66,
                  height: 66,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFF2F8FC),
                    border: Border.all(color: frameColor, width: 4),
                    boxShadow: [
                      BoxShadow(color: frameColor.withOpacity(0.2),
                        blurRadius: 6),
                    ],
                  ),
                  child: Icon(avatarIcon, size: 38,
                    color: const Color(0xFF0F5781)),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name.isEmpty ? 'DEDA' : name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF153C5C),
                        fontSize: 17)),
                    const SizedBox(height: 4),
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: Text(id,
                        key: const Key('verifiedRecipientPublicId'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF54667B),
                          fontWeight: FontWeight.w800,
                          fontSize: 13)),
                    ),
                    Text(
                      isArabic ? 'المستوى $level' : 'Level $level',
                      style: const TextStyle(
                        color: Color(0xFF9A6500),
                        fontWeight: FontWeight.w700,
                        fontSize: 12),
                    ),
                  ],
                )),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              isArabic
                  ? 'تأكد من الاسم والمعرف، وبعدها حدد المبلغ وأكّد الهدية.'
                  : 'Check both the name and DEDA ID, then choose the amount and confirm.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF607284),
                fontSize: 11.5),
            ),
          ],
        ),
      ),
    );
  }
}
