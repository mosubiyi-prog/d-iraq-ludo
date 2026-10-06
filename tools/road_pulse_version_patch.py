from pathlib import Path

VERSION_CODE = 100280

kts = Path("android/app/build.gradle.kts")
groovy = Path("android/app/build.gradle")

if kts.exists():
    text = kts.read_text()
    candidates = [
        "versionCode = flutter.versionCode",
        "versionCode = flutterVersionCode.toInt()",
    ]
    replaced = False
    for old in candidates:
        if old in text:
            text = text.replace(old, f"versionCode = {VERSION_CODE}", 1)
            replaced = True
            break
    if not replaced:
        if f"versionCode = {VERSION_CODE}" not in text:
            raise SystemExit("DEDA Road Pulse version patch: Kotlin versionCode anchor not found")
    kts.write_text(text)
    print(f"DEDA Road Pulse versionCode forced to {VERSION_CODE} in build.gradle.kts")
elif groovy.exists():
    text = groovy.read_text()
    candidates = [
        "versionCode flutterVersionCode.toInteger()",
        "versionCode flutterVersionCode.toInt()",
        "versionCode flutter.versionCode",
    ]
    replaced = False
    for old in candidates:
        if old in text:
            text = text.replace(old, f"versionCode {VERSION_CODE}", 1)
            replaced = True
            break
    if not replaced:
        if f"versionCode {VERSION_CODE}" not in text:
            raise SystemExit("DEDA Road Pulse version patch: Groovy versionCode anchor not found")
    groovy.write_text(text)
    print(f"DEDA Road Pulse versionCode forced to {VERSION_CODE} in build.gradle")
else:
    raise SystemExit("DEDA Road Pulse version patch: Android Gradle file not found")
