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
