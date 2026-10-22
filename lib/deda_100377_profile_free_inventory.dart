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
    for (final style in avatarChoices) {
      results.add(DedaMyStoreItem(
        id: 'avatar_$style',
        label: avatarNames[style],
        section: DedaMyStoreSection.avatars,
        proof: DedaMyStoreProof.basicFree,
        active: avatarStyle == style,
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

    for (final style in frameChoices) {
      results.add(DedaMyStoreItem(
        id: 'frame_$style',
        label: 'الإطار المجاني $style',
        section: DedaMyStoreSection.frames,
        proof: DedaMyStoreProof.basicFree,
        active: frameStyle == style,
      ));
    }

    for (final style in backgroundChoices) {
      results.add(DedaMyStoreItem(
        id: 'background_$style',
        label: 'الخلفية المجانية $style',
        section: DedaMyStoreSection.backgrounds,
        proof: DedaMyStoreProof.basicFree,
        active: backgroundStyle == style,
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
