# DEDA 100386 – Google Play Protect security hold (2026-10-27)

Status: **INSTALL BLOCKED. DO NOT SHIP. DO NOT BYPASS PLAY PROTECT.**

## Grounded owner device evidence
- Owner's Android phone displayed Google Play Protect: "تم حظر تطبيق ضار".
- Detailed message: "يحاول هذا التطبيق تجاوز إجراءات الحماية الأمنية لنظام التشغيل Android."
- The second screenshot reports "التطبيق ليس مثبتاً".
- Owner reattempted opening the same APK. Google Play Protect again displayed "تم حظر تطبيق ضار"; further details state "قد يكون هذا التطبيق ضاراً" and "قد يؤدي تثبيت هذا التطبيق إلى تعريض جهازك للخطر".
- The screen offers "التثبيت على أي حال", but that is a security bypass and **must not be recommended or selected**. Owner has supplied enough screenshots; no further install attempts are needed.
- Independent app behavior/security review remains pending. The existing CI package-signature/SDK/permission comparisons establish integrity, **not** Play Protect clearance.
- These screenshots do **not** establish the underlying detector category or the exact cause.

## Reproducible build evidence
- Latest tested CI: https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/40447895508
- CI succeeded and produced 100386 APK, but CI does **not** test Google Play Protect acceptance.
- Observed APK SHA-256: `dbd42152be480eecc857ad834eb95c89d5b314885177f2999c5a2b1850cfcb51`.
- 100385 and 100386 share package `com.diraq.ludo.d_iraq_ludo`, signing certificate SHA256 `a53d855b82d1280f324037428421838139ecf2e30174f9fcd0bd1878698b5f4a`, targetSdk 36, minSdk 24, and identical manifest permission lists.
- The binary `AndroidManifest.xml` differs by one byte, consistent with versionCode 100385 → 100386.
- The `classes.dex` file is byte-for-byte identical. ARM/x86 native Flutter application libraries changed as expected after Dart UI/content change; the MaterialIcons subset also changed.
- No new Android permission, changed applicationId, or changed signing certificate has been established to explain the new Play Protect block.
- **A malware verdict has not been proven false or true by these comparisons.** Treat the device block as a security-stop condition until further vendor/device diagnostics.

## Independent local artifact comparison (100384, 100385, 100386; 2026-10-27)

Actual signed APK bytes were inspected offline, not just workflow summaries.

- 100384: 87,757,365 bytes; SHA256 `a6ef5e2a438bda49532a8d56167563796bb203e1234a3df4abaf0c141a72237c`.
- 100385: 87,822,901 bytes; SHA256 `3353863addd06951dc0fa02e873a1a84375d72e66ca5844ee7de85c7800ae0f7`.
- 100386: 87,824,321 bytes; SHA256 `dbd42152be480eecc857ad834eb95c89d5b314885177f2999c5a2b1850cfcb51`.
- All three contain 571 ZIP entries; ZIP consistency checks passed.
- Compared to 100385, 100386 contains **zero added or removed ZIP entries** and exactly **five altered entries**: `AndroidManifest.xml`, `MaterialIcons-Regular.otf`, and `libapp.so` for three ABIs.
- The *only* AndroidManifest.xml binary change is one byte at offset 17524, the little-endian versionCode **100385 → 100386**. This rules out a changed manifest permission declaration between these particular two binaries.
- The 8,371,160-byte `classes.dex` is byte-for-byte identical (SHA256 `84c235106675610ce1c6161b2e11f2879c5cc5db28f7e4ad82747eb1fec40473`).
- The Android native executable/DEX module name sets are identical; no new DEX, SO, embedded APK, JAR, SH or EXE was introduced.
- Each accompanying `verification.json` lists the same 17 Android permissions, package name and signing certificate; the certificate is `a53d855b82d1280f324037428421838139ecf2e30174f9fcd0bd1878698b5f4a`.
- A limited byte-pattern check did not find accessibility-service, device-admin, app-install, overlay, SMS or VPN permission declarations. This is **not** a comprehensive malware scan.

**Interpretation:** no newly added Android permission, DEX or native plugin library explains the 100386-only Play Protect warning. The changed Flutter Dart AOT code, version code, Google detection metadata or another factor remain possible. This result neither proves nor disproves malware or a false positive. Vendor diagnostics / independent assessment are necessary before treating an APK as safe.

## Required next investigation, no workaround or silent repackaging
1. Preserve the warning screenshot; ask owner for what the Play Protect **More details** disclosure says, but do not tap install-anyway or disable Play Protect.
2. Independently check APK provenance, permissions, bundled libraries, security-sensitive code paths and Android security behaviors; do not assume Dart quiz changes explain the warning.
3. Check whether the *official Play-installed* release launches safely and remains unaffected; avoid removing the installed app or user data for this test.
4. Follow the official Play Protect false-positive/dispute route **only if the detector finding is demonstrably incorrect**. Otherwise fix confirmed security issues in a separate safe branch.
5. Do not build a new public APK or publish to Google Play until safe installation and relevant security checks are independently verified.
6. Never claim CI signing/build success equals Play Protect trust.

## Scope protection
- Production and Play Console remain untouched.
- Existing user account and wallet data must not be deleted.
- This checkpoint is security documentation, not an implementation fix or product safety certificate.
