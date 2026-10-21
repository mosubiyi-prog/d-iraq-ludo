/// DEDA LAB 16 authentic frame metadata — safely staged for owner QA.
/// No wallet access, no account mutation, no fake purchases.
/// Royal 3 existing image files in app assets; other 13 must be bundled
/// before enabling their previews in the native app.
class DedaLabFrameSpec {
  final String id;
  final String nameAr;
  final String assetPath;
  final bool bundled;
  final int priceDiamonds;
  final double portraitLeft, portraitTop, portraitWidth, portraitHeight;
  final String originalSha256;
  const DedaLabFrameSpec({required this.id,required this.nameAr,
    required this.assetPath,required this.bundled,required this.priceDiamonds,
    required this.portraitLeft,required this.portraitTop,
    required this.portraitWidth,required this.portraitHeight,
    required this.originalSha256});
  bool get free => priceDiamonds == 0;
  bool get canPreviewNatively => bundled;
  bool get needsTrustedCheckout => priceDiamonds > 0;
}
/// Original LAB internal avatar sizing; independent of 850px source art.
const int dedaLabInternalAvatarDimension = 111;
const int dedaLabPurchasedFramePriceDiamonds = 1000;
const List<DedaLabFrameSpec> dedaLabVerifiedFrames = <DedaLabFrameSpec>[
  DedaLabFrameSpec(id:'FRAME_01',nameAr:'الأسطورة الذهبي',assetPath:'assets/deda_royal_frames/royal_frame_1.webp',
    bundled:true,priceDiamonds:0,
    portraitLeft:0.246,portraitTop:0.265,
    portraitWidth:0.508,portraitHeight:0.404,
    originalSha256:'a31029b56a4a989feaec25a119b58a8a90c378e6ba3159705d2d5e537f4f299e'),
  DedaLabFrameSpec(id:'FRAME_02',nameAr:'الأسطورة الماروني',assetPath:'assets/deda_royal_frames/royal_frame_2.webp',
    bundled:true,priceDiamonds:0,
    portraitLeft:0.246,portraitTop:0.265,
    portraitWidth:0.508,portraitHeight:0.404,
    originalSha256:'dbd02ca458cf9e94e3a0005134d2b61cb0bdaaf7729893a8cbfe5f75123c249f'),
  DedaLabFrameSpec(id:'FRAME_03',nameAr:'الأسطورة الأسود الفحمي',assetPath:'assets/deda_lab_frames/FRAME_03.webp',
    bundled:false,priceDiamonds:1000,
    portraitLeft:0.246,portraitTop:0.265,
    portraitWidth:0.508,portraitHeight:0.404,
    originalSha256:'85310dd70afb964f42bbfa0922322ebbceb84f86a0a5957dd16818be1ea94bec'),
  DedaLabFrameSpec(id:'FRAME_04',nameAr:'الأسطورة الزمردي',assetPath:'assets/deda_royal_frames/royal_frame_0.webp',
    bundled:true,priceDiamonds:0,
    portraitLeft:0.246,portraitTop:0.265,
    portraitWidth:0.508,portraitHeight:0.404,
    originalSha256:'9ae19c51cbc7394299b361cb1f8dd07e015898b43e4ecaca0fdb0f4b207a12b5'),
  DedaLabFrameSpec(id:'FRAME_05',nameAr:'الكوبرا الياقوتية الزرقاء',assetPath:'assets/deda_lab_frames/FRAME_05.webp',
    bundled:false,priceDiamonds:1000,
    portraitLeft:0.272,portraitTop:0.27,
    portraitWidth:0.457,portraitHeight:0.385,
    originalSha256:'1032d2a2748d0f5308de967cf7713789a7daff3c0ce6f65ba91a2337743bba16'),
  DedaLabFrameSpec(id:'FRAME_06',nameAr:'الكوبرا الياقوتية الحمراء',assetPath:'assets/deda_lab_frames/FRAME_06.webp',
    bundled:false,priceDiamonds:1000,
    portraitLeft:0.273,portraitTop:0.273,
    portraitWidth:0.453,portraitHeight:0.383,
    originalSha256:'626e432cbed0ae2b1a8de38e4ad410abd07ccf8e6e10a794f9737cca573ae703'),
  DedaLabFrameSpec(id:'FRAME_07',nameAr:'الكوبرا الزمردية',assetPath:'assets/deda_lab_frames/FRAME_07.webp',
    bundled:false,priceDiamonds:1000,
    portraitLeft:0.272,portraitTop:0.273,
    portraitWidth:0.455,portraitHeight:0.383,
    originalSha256:'824a852e7233cd9ba929a70e08ee8d7bb117b8242604dd38020006221ad2bfbf'),
  DedaLabFrameSpec(id:'FRAME_08',nameAr:'البركان المتوهج',assetPath:'assets/deda_lab_frames/FRAME_08.webp',
    bundled:false,priceDiamonds:1000,
    portraitLeft:0.274,portraitTop:0.25,
    portraitWidth:0.452,portraitHeight:0.474,
    originalSha256:'f12a8acba653665d3176602547e968f5bc291048641bebcb6088aaa685ef4ce1'),
  DedaLabFrameSpec(id:'FRAME_09',nameAr:'العراقي التراثي',assetPath:'assets/deda_lab_frames/FRAME_09.webp',
    bundled:false,priceDiamonds:1000,
    portraitLeft:0.208,portraitTop:0.235,
    portraitWidth:0.583,portraitHeight:0.462,
    originalSha256:'de0a36956223339cb63bd66b6e108231393b44c2c0bdd1abd1af044e8c93530f'),
  DedaLabFrameSpec(id:'FRAME_10',nameAr:'العراقي الجمهوري',assetPath:'assets/deda_lab_frames/FRAME_10.webp',
    bundled:false,priceDiamonds:1000,
    portraitLeft:0.285,portraitTop:0.345,
    portraitWidth:0.431,portraitHeight:0.421,
    originalSha256:'e184900f5478e0eb5b29e2ef108a36626f7eedd71666c56b67a03f9d28cf3142'),
  DedaLabFrameSpec(id:'FRAME_11',nameAr:'قلب الحب الملكي',assetPath:'assets/deda_lab_frames/FRAME_11.webp',
    bundled:false,priceDiamonds:1000,
    portraitLeft:0.273,portraitTop:0.271,
    portraitWidth:0.453,portraitHeight:0.453,
    originalSha256:'3a3219dda5eefd23071e4bc8fc12acc5d272c2dffb4b82a0054ca00751f2b479'),
  DedaLabFrameSpec(id:'FRAME_12',nameAr:'قلب الحب المجنّح',assetPath:'assets/deda_lab_frames/FRAME_12.webp',
    bundled:false,priceDiamonds:1000,
    portraitLeft:0.276,portraitTop:0.27,
    portraitWidth:0.449,portraitHeight:0.454,
    originalSha256:'303bb4fce8ee6b8c2886fd7243d5fbb6f00dfe1ade58f4e58c5abbfbdd28b473'),
  DedaLabFrameSpec(id:'FRAME_13',nameAr:'قلب الحب الأزرق',assetPath:'assets/deda_lab_frames/FRAME_13.webp',
    bundled:false,priceDiamonds:1000,
    portraitLeft:0.274,portraitTop:0.271,
    portraitWidth:0.452,portraitHeight:0.453,
    originalSha256:'a47528acd41d0a8dce50d2e2612a304323229a2660faa217c71c3ffd1b6a8a4c'),
  DedaLabFrameSpec(id:'FRAME_14',nameAr:'الجاكور الأسود الملكي',assetPath:'assets/deda_lab_frames/FRAME_14.webp',
    bundled:false,priceDiamonds:1000,
    portraitLeft:0.168,portraitTop:0.284,
    portraitWidth:0.664,portraitHeight:0.552,
    originalSha256:'ad4d0b11f02ace63b1a530d3cc20b933e4b50d0f1076a6f3c496eb0e469f1741'),
  DedaLabFrameSpec(id:'FRAME_15',nameAr:'BMW الفاخر · واجهة السيارة',assetPath:'assets/deda_lab_frames/FRAME_15.webp',
    bundled:false,priceDiamonds:1000,
    portraitLeft:0.277,portraitTop:0.222,
    portraitWidth:0.447,portraitHeight:0.438,
    originalSha256:'dffe7bd4a78fa1b866b9885cc1ab9661cbaeaeb9f03a3ed911398c1d24f2ca4c'),
  DedaLabFrameSpec(id:'FRAME_16',nameAr:'مرسيدس الفخامة الملكية',assetPath:'assets/deda_lab_frames/FRAME_16.webp',
    bundled:false,priceDiamonds:1000,
    portraitLeft:0.276,portraitTop:0.215,
    portraitWidth:0.449,portraitHeight:0.449,
    originalSha256:'a53c5f6dda02aa7a57d08dcec15f5cff525ce3873c53af2db2deb304b8029a5f'),
];
/// Never imply paid entitlement from local preference or selected preview.
bool dedaLabIsGiftedOrOwnedFrame(DedaLabFrameSpec frame, Set<String> verifiedOwnedIds) {
  return frame.free || verifiedOwnedIds.contains(frame.id);
}
