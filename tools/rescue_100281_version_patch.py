from pathlib import Path

VERSION_CODE = 100281

kts = Path("android/app/build.gradle.kts")
groovy = Path("android/app/build.gradle")

if kts.exists():
    text = kts.read_text()
    candidates = [
        "versionCode = flutter.versionCode",
        "versionCode = flutterVersionCode.toInt()",
    ]
    for old in candidates:
        if old in text:
            text = text.replace(old, f"versionCode = {VERSION_CODE}", 1)
            break
    else:
        if f"versionCode = {VERSION_CODE}" not in text:
            raise SystemExit("DEDA rescue: Kotlin versionCode anchor not found")
    kts.write_text(text)
elif groovy.exists():
    text = groovy.read_text()
    candidates = [
        "versionCode flutterVersionCode.toInteger()",
        "versionCode flutterVersionCode.toInt()",
        "versionCode flutter.versionCode",
    ]
    for old in candidates:
        if old in text:
            text = text.replace(old, f"versionCode {VERSION_CODE}", 1)
            break
    else:
        if f"versionCode {VERSION_CODE}" not in text:
            raise SystemExit("DEDA rescue: Groovy versionCode anchor not found")
    groovy.write_text(text)
else:
    raise SystemExit("DEDA rescue: Android Gradle file not found")

print(f"DEDA rescue versionCode forced to {VERSION_CODE}")
