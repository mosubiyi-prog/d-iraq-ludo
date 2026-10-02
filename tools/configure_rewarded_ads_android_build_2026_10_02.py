from pathlib import Path


def configure_google_services() -> None:
    settings_kts = Path('android/settings.gradle.kts')
    settings_groovy = Path('android/settings.gradle')
    app_kts = Path('android/app/build.gradle.kts')
    app_groovy = Path('android/app/build.gradle')

    if settings_kts.exists():
        text = settings_kts.read_text(encoding='utf-8')
        line = '    id("com.google.gms.google-services") version "4.4.2" apply false\n'
        if 'com.google.gms.google-services' not in text:
            if 'plugins {\n' not in text:
                raise SystemExit('plugins block not found in settings.gradle.kts')
            text = text.replace('plugins {\n', 'plugins {\n' + line, 1)
            settings_kts.write_text(text, encoding='utf-8')
    elif settings_groovy.exists():
        text = settings_groovy.read_text(encoding='utf-8')
        line = "    id 'com.google.gms.google-services' version '4.4.2' apply false\n"
        if 'com.google.gms.google-services' not in text:
            if 'plugins {\n' not in text:
                raise SystemExit('plugins block not found in settings.gradle')
            text = text.replace('plugins {\n', 'plugins {\n' + line, 1)
            settings_groovy.write_text(text, encoding='utf-8')
    else:
        raise SystemExit('Android settings Gradle file not found')

    if app_kts.exists():
        text = app_kts.read_text(encoding='utf-8')
        line = '    id("com.google.gms.google-services")\n'
        if 'com.google.gms.google-services' not in text:
            if 'plugins {\n' not in text:
                raise SystemExit('plugins block not found in app build.gradle.kts')
            text = text.replace('plugins {\n', 'plugins {\n' + line, 1)
            app_kts.write_text(text, encoding='utf-8')
    elif app_groovy.exists():
        text = app_groovy.read_text(encoding='utf-8')
        line = "    id 'com.google.gms.google-services'\n"
        if 'com.google.gms.google-services' not in text:
            if 'plugins {\n' not in text:
                raise SystemExit('plugins block not found in app build.gradle')
            text = text.replace('plugins {\n', 'plugins {\n' + line, 1)
            app_groovy.write_text(text, encoding='utf-8')
    else:
        raise SystemExit('Android app Gradle file not found')


def configure_sdk_and_signing() -> None:
    kts = Path('android/app/build.gradle.kts')
    groovy = Path('android/app/build.gradle')

    if kts.exists():
        text = kts.read_text(encoding='utf-8')
        text = text.replace('compileSdk = flutter.compileSdkVersion', 'compileSdk = 36')
        text = text.replace('targetSdk = flutter.targetSdkVersion', 'targetSdk = 36')

        marker = '    buildTypes {'
        signing = '\n'.join([
            '    signingConfigs {',
            '        create("release") {',
            '            keyAlias = System.getenv("DEDA_KEY_ALIAS")',
            '            keyPassword = System.getenv("DEDA_KEY_PASSWORD")',
            '            storeFile = file("deda-release.jks")',
            '            storePassword = System.getenv("DEDA_STORE_PASSWORD")',
            '        }',
            '    }',
            '',
        ])
        if 'create("release")' not in text:
            if marker not in text:
                raise SystemExit('buildTypes not found in build.gradle.kts')
            text = text.replace(marker, signing + marker, 1)
        old = 'signingConfig = signingConfigs.getByName("debug")'
        if old in text:
            text = text.replace(old, 'signingConfig = signingConfigs.getByName("release")', 1)
        elif 'signingConfig = signingConfigs.getByName("release")' not in text:
            raise SystemExit('Signing configuration marker not found in build.gradle.kts')
        kts.write_text(text, encoding='utf-8')
        return

    if groovy.exists():
        text = groovy.read_text(encoding='utf-8')
        text = text.replace('compileSdkVersion flutter.compileSdkVersion', 'compileSdkVersion 36')
        text = text.replace('targetSdkVersion flutter.targetSdkVersion', 'targetSdkVersion 36')
        marker = '    buildTypes {'
        signing = '\n'.join([
            '    signingConfigs {',
            '        release {',
            '            keyAlias System.getenv("DEDA_KEY_ALIAS")',
            '            keyPassword System.getenv("DEDA_KEY_PASSWORD")',
            '            storeFile file("deda-release.jks")',
            '            storePassword System.getenv("DEDA_STORE_PASSWORD")',
            '        }',
            '    }',
            '',
        ])
        if 'signingConfigs {' not in text or 'release {' not in text:
            if marker not in text:
                raise SystemExit('buildTypes not found in build.gradle')
            text = text.replace(marker, signing + marker, 1)
        if 'signingConfig signingConfigs.debug' in text:
            text = text.replace('signingConfig signingConfigs.debug', 'signingConfig signingConfigs.release', 1)
        elif 'signingConfig = signingConfigs.debug' in text:
            text = text.replace('signingConfig = signingConfigs.debug', 'signingConfig = signingConfigs.release', 1)
        elif 'signingConfigs.release' not in text:
            raise SystemExit('Signing configuration marker not found in build.gradle')
        groovy.write_text(text, encoding='utf-8')
        return

    raise SystemExit('Android app Gradle file not found')


def configure_manifest() -> None:
    path = Path('android/app/src/main/AndroidManifest.xml')
    text = path.read_text(encoding='utf-8')
    permissions = [
        '<uses-permission android:name="android.permission.INTERNET" />',
        '<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />',
        '<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />',
    ]
    missing = [p for p in permissions if p not in text]
    if missing:
        pos = text.find('>')
        if pos < 0:
            raise SystemExit('Malformed AndroidManifest.xml')
        insertion = '\n' + '\n'.join('    ' + p for p in missing) + '\n'
        text = text[:pos + 1] + insertion + text[pos + 1:]
    text = text.replace('android:label="d_iraq_ludo"', 'android:label="DEDA"')

    sample_app_id = 'ca-app-pub-3940256099942544~3347511713'
    if sample_app_id not in text:
        marker = '</application>'
        metadata = '\n'.join([
            '        <meta-data',
            '            android:name="com.google.android.gms.ads.APPLICATION_ID"',
            f'            android:value="{sample_app_id}" />',
            '    ',
        ])
        if marker not in text:
            raise SystemExit('application closing tag not found')
        text = text.replace(marker, metadata + marker, 1)
    path.write_text(text, encoding='utf-8')


def configure_launcher_icons() -> None:
    pubspec = Path('pubspec.yaml')
    text = pubspec.read_text(encoding='utf-8')
    if '\nflutter_launcher_icons:\n' not in text:
        text += '\n'.join([
            '',
            'flutter_launcher_icons:',
            '  android: "ic_launcher"',
            '  ios: false',
            '  image_path: "deda_app_icon.png"',
            '  min_sdk_android: 21',
            '',
        ])
        pubspec.write_text(text, encoding='utf-8')


configure_google_services()
configure_sdk_and_signing()
configure_manifest()
configure_launcher_icons()
print('Rewarded-ad Android build configuration applied.')
