from pathlib import Path

path = Path('android/app/src/main/AndroidManifest.xml')
if not path.exists():
    raise SystemExit('AndroidManifest.xml not found; run after flutter create')

text = path.read_text(encoding='utf-8')
app_id = 'ca-app-pub-3940256099942544~3347511713'
marker = '</application>'
metadata = (
    '        <meta-data\n'
    '            android:name="com.google.android.gms.ads.APPLICATION_ID"\n'
    f'            android:value="{app_id}" />\n'
)

if app_id not in text:
    if marker not in text:
        raise SystemExit('Android application closing tag not found')
    text = text.replace(marker, metadata + '    ' + marker, 1)

path.write_text(text, encoding='utf-8')
print('Google sample AdMob application ID configured for test build only.')
