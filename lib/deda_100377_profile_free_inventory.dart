import 'deda_100377_my_store_page_staged.dart';

/// Point12/Point05: free local appearance CATALOG visible in the existing
/// signed editor. Does not claim an owned purchase, mint credits, override
/// server appearance or substitute the still-missing moonlit trio.
///
/// The original picker offers exactly avatars 0..5, free frames 0..5,
/// and backgrounds 0,1,2,6,7,8. Legacy selections outside those picker
/// choices remain visible ONLY when selected by the current phone/account.
class DedaProfileFreeInventory {
  const DedaProfileFreeInventory._();

  static const List<int> avatarChoices = <int>[0, 1, 2, 3, 4, 5];
  static const List<int> frameChoices = <int>[0, 1, 2, 3, 4, 5];
  static const List<int> backgroundChoices = <int>[0, 1, 2, 6, 7, 8];

  static List<DedaMyStoreItem> forDevice({
    required int avatarStyle,
    required int frameStyle,
    required int backgroundStyle,
  }) {
    final results = <DedaMyStoreItem>[];
    const avatarNames = <String>[
      'الصورة الملكية الرجالية',
      'الصورة الملكية النسائية',
      'الصورة الملكية المشتركة',
      'الصورة الكلاسيكية 1',
      'الصورة الكلاسيكية 2',
      'الصورة الكلاسيكية 3',
    ];
    const avatarArt = <String>[
      'assets/deda_royal_avatars/deda_avatar_male_royal.jpg',
      'assets/deda_royal_avatars/deda_avatar_female_royal.jpg',
      'assets/deda_royal_avatars/deda_avatar_couple_royal.jpg',
    ];
    for (final style in avatarChoices) {
      results.add(DedaMyStoreItem(
        id: 'avatar_$style',
        label: avatarNames[style],
        section: DedaMyStoreSection.avatars,
        proof: DedaMyStoreProof.basicFree,
        active: avatarStyle == style,
        previewAsset: style < avatarArt.length ? avatarArt[style] : null,
      ));
    }
    // Old owner choices 6..8 are preserved by the avatar migration, not
    // represented as new free store products or moonlit replacements.
    if (avatarStyle >= 6 && avatarStyle <= 8) {
      results.add(DedaMyStoreItem(
        id: 'avatar_$avatarStyle',
        label: 'الصورة القديمة المحفوظة',
        section: DedaMyStoreSection.avatars,
        proof: DedaMyStoreProof.deviceSaved,
        active: true,
      ));
    }

    const frameNames = <String>[
      'إطار DEDA الأساسي الأول',
      'إطار DEDA الأساسي الثاني',
      'إطار DEDA الأساسي الثالث',
      'وردي ملكي',
      'ذهبي ملكي',
      'زمردي ملكي',
    ];
    for (final style in frameChoices) {
      results.add(DedaMyStoreItem(
        id: 'frame_$style',
        label: frameNames[style],
        section: DedaMyStoreSection.frames,
        proof: DedaMyStoreProof.basicFree,
        active: frameStyle == style,
        previewAsset: style >= 3
            ? 'assets/deda_royal_frames/royal_frame_${style - 3}.webp'
            : null,
      ));
    }

    const backgroundNames = <int, String>{
      0: 'الخلفية الخضراء الفاتحة',
      1: 'الخلفية الزرقاء الفاتحة',
      2: 'الخلفية الرملية الفاتحة',
      6: 'الخلفية الملكية المرصّعة بالنجوم',
      7: 'الخلفية الزمردية الذهبية',
      8: 'الخلفية المارونية الذهبية',
    };
    for (final style in backgroundChoices) {
      results.add(DedaMyStoreItem(
        id: 'background_$style',
        label: backgroundNames[style]!,
        section: DedaMyStoreSection.backgrounds,
        proof: DedaMyStoreProof.basicFree,
        active: backgroundStyle == style,
        previewAsset: switch (style) {
          7 => 'assets/deda_royal_backgrounds/deda_royal_bg_emerald.webp',
          8 => 'assets/deda_royal_backgrounds/deda_royal_bg_burgundy.webp',
          _ => null,
        },
      ));
    }
    // The saved legacy 3..5 backgrounds can still decorate an account even
    // though the current six-choice editor does not offer them anymore.
    if (backgroundStyle >= 3 && backgroundStyle <= 5) {
      results.add(DedaMyStoreItem(
        id: 'background_$backgroundStyle',
        label: 'الخلفية القديمة المحفوظة',
        section: DedaMyStoreSection.backgrounds,
        proof: DedaMyStoreProof.deviceSaved,
        active: true,
      ));
    }
    return List<DedaMyStoreItem>.unmodifiable(results);
  }
}
