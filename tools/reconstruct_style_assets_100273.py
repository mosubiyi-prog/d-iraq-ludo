from __future__ import annotations

import base64
import gzip
import io
import tarfile
import zipfile
from pathlib import Path

ROOT = Path('.')
TOOLS = ROOT / 'tools'
ASSETS = ROOT / 'assets'
STYLE = ASSETS / 'deda_style'
REFERENCE = ASSETS / 'deda_style_reference_100273.jpg'
PARTS = sorted(TOOLS.glob('style_assets_100273.part*'))


def _safe_join(base: Path, name: str) -> Path:
    target = (base / name).resolve()
    root = base.resolve()
    if root != target and root not in target.parents:
        raise SystemExit(f'Unsafe archive path: {name}')
    return target


def _write_reference(data: bytes) -> None:
    REFERENCE.write_bytes(data)
    print(f'Restored DEDA 100273 visual reference: {REFERENCE} ({len(data)} bytes)')


def _extract_zip(data: bytes) -> bool:
    try:
        with zipfile.ZipFile(io.BytesIO(data)) as archive:
            members = archive.infolist()
            if not members:
                return False
            for member in members:
                if member.is_dir():
                    continue
                target = _safe_join(ROOT, member.filename)
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(archive.read(member))
            print(f'Extracted DEDA 100273 ZIP asset bundle ({len(members)} entries)')
            return True
    except zipfile.BadZipFile:
        return False


def _extract_tar(data: bytes) -> bool:
    try:
        with tarfile.open(fileobj=io.BytesIO(data), mode='r:*') as archive:
            members = archive.getmembers()
            if not members:
                return False
            for member in members:
                if not member.isfile():
                    continue
                target = _safe_join(ROOT, member.name)
                target.parent.mkdir(parents=True, exist_ok=True)
                src = archive.extractfile(member)
                if src is None:
                    continue
                target.write_bytes(src.read())
            print(f'Extracted DEDA 100273 TAR asset bundle ({len(members)} entries)')
            return True
    except tarfile.TarError:
        return False


def _looks_base64_text(data: bytes) -> bool:
    try:
        text = data.decode('ascii')
    except UnicodeDecodeError:
        return False
    compact = ''.join(text.split())
    if len(compact) < 16 or len(compact) % 4 != 0:
        return False
    allowed = set('ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=')
    return all(ch in allowed for ch in compact)


def _consume_payload(data: bytes, depth: int = 0) -> bool:
    if depth > 3:
        return False

    if data.startswith(b'\x1f\x8b'):
        try:
            return _consume_payload(gzip.decompress(data), depth + 1)
        except OSError as exc:
            raise SystemExit(f'Invalid gzip payload in DEDA 100273 split assets: {exc}')

    if data.startswith(b'PK\x03\x04') and _extract_zip(data):
        return True

    if _extract_tar(data):
        return True

    if data.startswith(b'\xff\xd8\xff') or data.startswith(b'\x89PNG\r\n\x1a\n'):
        _write_reference(data)
        return True

    if _looks_base64_text(data):
        compact = ''.join(data.decode('ascii').split())
        try:
            return _consume_payload(base64.b64decode(compact, validate=True), depth + 1)
        except Exception:
            pass

    return False


if not PARTS:
    raise SystemExit('DEDA 100273 split asset parts are missing')

payload_text = ''.join(part.read_text(encoding='utf-8').strip() for part in PARTS)
try:
    payload = base64.b64decode(payload_text, validate=True)
except Exception as exc:
    raise SystemExit(f'Could not decode DEDA 100273 split asset bundle: {exc}')

if not _consume_payload(payload):
    signature = payload[:24].hex()
    raise SystemExit(f'Unknown DEDA 100273 split asset payload format: {signature}')

STYLE.mkdir(parents=True, exist_ok=True)
expected = [STYLE / f'{kind}_{index}.png' for kind in ('badge', 'frame') for index in range(6)]
ready = [p for p in expected if p.exists() and p.stat().st_size >= 2000]
print(f'DEDA 100273 reconstructed assets ready: {len(ready)}/12 direct PNGs')
