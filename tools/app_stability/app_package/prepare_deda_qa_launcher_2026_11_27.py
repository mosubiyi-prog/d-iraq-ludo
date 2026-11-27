"""Prepare only the independent QA launcher on the held, disposable full app.

No auth, network, signing key, release flags, original assets or Dart changes.
This is packaging preparation, NOT permission to open the full app.
"""
import hashlib
from pathlib import Path
import re
import sys
import xml.etree.ElementTree as ET

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[3]
PACKAGE = 'com.deda.qa.uiddevice'
ANDROID = '{http://schemas.android.com/apk/res/android}'
TOOLS = '{http://schemas.android.com/tools}'
# Flutter's manifest preflight uses the literal android: prefix.
ET.register_namespace('android', ANDROID[1:-1])
ET.register_namespace('tools', TOOLS[1:-1])
DENSITIES = {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}


def require(ok, reason):
    if not ok:
        raise ValueError(reason)


def digest(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()


def prepare(project):
    p = Path(project).resolve()
    require(p.is_dir() and p != ROOT and ROOT not in p.parents and p not in ROOT.parents,
            'DISPOSABLE_PROJECT_REQUIRED')
    gradle = (p/'android/app/build.gradle.kts').read_text()
    require(re.findall(r'applicationId\s*=\s*"([^"]+)"', gradle) == [PACKAGE],
            'INDEPENDENT_PACKAGE_REQUIRED')
    require(not list(p.rglob('google-services.json')), 'NATIVE_CONFIG_FORBIDDEN')
    main = (p/'lib/main.dart').read_text()
    require(main.count('stage02Lab.main()') == 1 and
            main.count('_dedaStage01HeldOriginalMain(') == 1, 'FULL_ENTRY_HOLD_REQUIRED')
    manifest = p/'android/app/src/main/AndroidManifest.xml'
    tree = ET.parse(manifest)
    doc = tree.getroot()
    app = doc.find('application')
    embedding = [n for n in app.findall('meta-data')
                 if n.get(ANDROID+'name') == 'flutterEmbedding'] if app is not None else []
    require(len(embedding) == 1 and embedding[0].get(ANDROID+'value') == '2',
            'FLUTTER_V2_EMBEDDING_REQUIRED')
    require(app is not None and app.get(ANDROID+'allowBackup') == 'false', 'BACKUP_HOLD_REQUIRED')
    for perm in ('android.permission.INTERNET', 'android.permission.ACCESS_NETWORK_STATE'):
        require(any(n.get(ANDROID+'name') == perm and n.get(TOOLS+'node') == 'remove'
                    for n in doc.findall('uses-permission')), 'NETWORK_HOLD_REQUIRED')
    source = p/'deda_app_icon.png'
    reference = ROOT/'deda_app_icon.png'
    require(digest(source) == digest(reference), 'ORIGINAL_ICON_CHANGED')
    with Image.open(source) as im:
        require(im.width == im.height and im.width >= 48, 'SQUARE_ORIGINAL_ICON_REQUIRED')
        icon = im.convert('RGBA').resize((512,512), Image.Resampling.LANCZOS)
    # A small, legible gold badge on the outside launcher only.
    draw = ImageDraw.Draw(icon)
    draw.rounded_rectangle((290, 380, 501, 494), radius=19,
                           fill='#F7CB65', outline='#342710', width=5)
    font = ImageFont.load_default(size=72)
    box = draw.textbbox((0,0), 'QA', font=font)
    x = (290+501-box[0]-box[2])/2
    y = (380+494-box[1]-box[3])/2
    draw.text((x,y), 'QA', font=font, fill='#342710')
    res = p/'android/app/src/main/res'
    for density, size in DENSITIES.items():
        dest = res/('mipmap-'+density)/'deda_qa_launcher.png'
        require(not dest.exists(), 'QA_LAUNCHER_ALREADY_EXISTS')
    for density, size in DENSITIES.items():
        dest = res/('mipmap-'+density)/'deda_qa_launcher.png'
        dest.parent.mkdir(parents=True, exist_ok=True)
        icon.resize((size,size), Image.Resampling.LANCZOS).save(dest)
        with Image.open(dest) as actual:
            require(actual.size == (size,size), 'LAUNCHER_SIZE_MISMATCH')
    app.set(ANDROID+'label', 'DEDA QA')
    app.set(ANDROID+'icon', '@mipmap/deda_qa_launcher')
    if ANDROID+'roundIcon' in app.attrib:
        app.set(ANDROID+'roundIcon', '@mipmap/deda_qa_launcher')
    # Check the serialized result BEFORE replacing the known-good manifest.
    encoded = ET.tostring(doc, encoding='utf-8', xml_declaration=True)
    require(b'xmlns:android=' in encoded and b'xmlns:tools=' in encoded
            and b'android:name="flutterEmbedding"' in encoded
            and b'android:value="2"' in encoded, 'FLUTTER_MANIFEST_PREFIX_REQUIRED')
    restored = ET.fromstring(encoded)
    require(ET.tostring(restored) == ET.tostring(doc), 'MANIFEST_ROUNDTRIP_CHANGED')
    manifest.write_bytes(encoded)
    require(digest(source) == digest(reference), 'ORIGINAL_ICON_CHANGED')
    print('PASS_QA_LAUNCHER_INDEPENDENT_PACKAGE_ORIGINAL_ICON_RETAINED_FULL_ENTRY_HELD')


if __name__ == '__main__':
    prepare(sys.argv[1])
