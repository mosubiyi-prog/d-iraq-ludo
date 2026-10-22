# DEDA 100377 — Point12 correction after owner phone 100378 acceptance
Date: 2026-10-22. Owner explicitly instructed full 13-point repair in original order.

## Original owner acceptance failure that compelled this correction
- 100378 original profile showed a NEW teal wide "متجري" tile alongside an unchanged separate purple "متجر المعرّفات" tile. This was NOT the requested replacement of the profile tile.
- "متجري" showed placeholders such as "الإطار المجاني 3", "الخلفية المجانية 7" and "محفوظ على هذا الجهاز"; the gallery lacked its actual visual assets and was not a convenient use/switch view.
- Screenshots also show 13 genuine paid 1000-diamond frames still LOCKED (Point01 OPEN), missing user-approved moonlit avatar trio (Point05 OPEN), original @DEDA-AQPYXJ substituted for @DEDA-IRAQI (Point06/13 OPEN), missing exact six level-earned decorative achievement assets (Point10/11 OPEN), and no verified purchases or received gifts listed (Point09/12 not cross-device proven). These failures are carried forward, not silently closed.

## Corrective source commits on same development branch
- d9f734d53d3f72f1766f9b810dd31ec150995a4d: `lib/deda_100377_my_store_page_staged.dart` adds action within My Store that calls the ORIGINAL identifier acquisition shop route. No client balance spending or counterfeit ownership.
- 21ece1f6cd6a5e51f216527f16e212faecbeb5b3: `tools/stage_deda_100377_point12_my_store.py` rewrites the ORIGINAL existing purple tile to "متجري" instead of prepending a new wide tile. Existing shop route is preserved as an internal action. The name "متجري" appears ONCE in the original profile feature grid; "متجر المعرّفات" is no longer a second profile feature tile.
- 2e4aa7f3c4d04b1f00994911f9c68c159822b484: My Store can display authentic Flutter asset thumbnails and optionally link directly to the genuine Edit Profile selector.
- d9fc1c2fb6986d220b284c0b71add8ba47519208: `lib/deda_100377_profile_free_inventory.dart` maps known free choices to readable Arabic names and uses exact existing Flutter assets for three royal portraits, royal frames and available original backgrounds. No guessed "moonlit" art is presented as supplied or approved.
- 08bd8519134c8f8188b3fc5be183a321ecd3e0c3: securely route My Store's "اختيار الصورة والإطار والخلفية" control back to the original Edit Profile dialog; user phone, original identifier and Firebase UID still bound to initiating owner.
- e97aa9efba9f21881c398a7dc14d03949810183a + c0941f7fbc31f4f90ea108050e6522ba8eb9e075 + 91f77319495535215fe9ac02262f7eee26888461: corrected source tests and Point11 lock-page navigation test to expect one tile and intact earned badges.
- b056b0cc919cabe8e41f210990a4841fc6895cb8 + 40905f2c8b15f9f034ae936cc400036ee13d1b55: guard actual free choices and verify the original acquisition shop and Edit Profile callbacks in Flutter.

## Verified outcomes / open gates
- Most recent completed exact integrated source QA for these changes: https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/39818137257 SUCCESS at head 08bd8519, BEFORE newest widget-test-only commit 40905f2c.
- Latest 40905f2c workflow run 39818101790 was CANCELLED by newer-run concurrency before executing, not a confirmed test pass.
- This checkpoint commit re-triggers entire exact-source QA; verify its own run before claiming the latest head passed.
- No signed final APK and NO Play/Firebase deployment occurred after these edits. The old owner 100378 partial APK remains unchanged. No production balance, UID, points, level, rewards, gifts or purchases changed.
- Open limitations: paid LAB frame checkout defaults OFF; new exact moonlit trio original images not located in Flutter assets; six exact owner badge drawings not in Flutter assets; activated alias and admin-200 gate off; cross-device persistence not proven. Do not claim 13/13. The successful UI source corrections are not proof of on-device acceptance.
