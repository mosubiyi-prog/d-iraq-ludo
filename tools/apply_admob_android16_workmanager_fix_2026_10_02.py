from pathlib import Path

kts = Path('android/app/build.gradle.kts')
groovy = Path('android/app/build.gradle')

if kts.exists():
    text = kts.read_text(encoding='utf-8')
    dep = '    implementation("androidx.work:work-runtime:2.11.2")'
    if dep not in text:
        text = text.rstrip() + '\n\ndependencies {\n' + dep + '\n}\n'
    kts.write_text(text, encoding='utf-8')
elif groovy.exists():
    text = groovy.read_text(encoding='utf-8')
    dep = "    implementation 'androidx.work:work-runtime:2.11.2'"
    if dep not in text:
        text = text.rstrip() + '\n\ndependencies {\n' + dep + '\n}\n'
    groovy.write_text(text, encoding='utf-8')
else:
    raise SystemExit('Android app Gradle file not found')

print('Pinned androidx.work:work-runtime:2.11.2 for Android 16 release crash workaround.')
