#!/usr/bin/env python3
"""DEDA 100354 PRIVATE BUILD ONLY: keep Kotlin Continuation's exact runtime name.

The SHA-pinned 100353 APK obfuscated kotlin.coroutines.Continuation to Lax;
while its SharedPreferencesApiRegistrar.getAll was invoked through a bridge
expecting the original Continuation name, causing NoSuchMethodError at launch.
This changes only generated Android build inputs on the ephemeral CI runner.
No Dart, Firestore, user data, app ID, release signing, or Play mutation.
"""
from pathlib import Path

gradle = Path("android/app/build.gradle.kts")
assert gradle.is_file(), "SAFE_STOP: expected generated Kotlin Android Gradle script is absent"
before = gradle.read_text()
assert "com.android.application" in before and "android {" in before
assert "buildTypes {" in before and "release {" in before
marker = "// DEDA_100354_KEEP_KOTLIN_CONTINUATION_RUNTIME_NAME"
assert marker not in before, "SAFE_STOP: rule already inserted"
rules = Path("android/app/proguard-rules.pro")
existing = rules.read_text() if rules.exists() else ""
assert "kotlin.coroutines.Continuation" not in existing, "SAFE_STOP: conflicting old continuation rule; inspect manually"
policy = (
    "\n# DEDA 100354: generated Pigeon methods use Continuation reflection.\n"
    "# Do not let R8 rename the Kotlin Continuation interface used in method signatures.\n"
    "-keep interface kotlin.coroutines.Continuation { *; }\n"
    "# Keep public registrar signatures used across the Flutter<->Kotlin platform bridge.\n"
    "-keep class io.flutter.plugins.sharedpreferences.SharedPreferencesApiRegistrar { *; }\n"
    "-keep class io.flutter.plugins.sharedpreferences.SharedPreferencesAsyncApiRegistrar { *; }\n"
)
rules.write_text(existing + policy)
gradle.write_text(before.rstrip() + "\n\n" + marker + "\n" + """
android {
    buildTypes {
        getByName("release") {
            proguardFiles("proguard-rules.pro")
        }
    }
}
""")
after = gradle.read_text()
assert after.startswith(before.rstrip()), "SAFE_STOP: existing Gradle settings altered"
assert after.count(marker) == 1
assert after.count('proguardFiles("proguard-rules.pro")') == 1
assert rules.read_text().count("-keep interface kotlin.coroutines.Continuation { *; }") == 1
print("PASS: release keep rule appended to generated Kotlin Gradle only")
print("PASS: continuation and SharedPreferences Pigeon names preserved; Dart and signing untouched")
