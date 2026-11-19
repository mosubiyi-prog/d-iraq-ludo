#!/usr/bin/env python3
"""DEDA Firebase Spark DATA SAFETY: encrypt a STRICTLY READ-ONLY snapshot.

Exports Firestore documents (including nested subcollections) and Firebase
Authentication public/user metadata, not password hashes or Storage objects.
No Firebase writes, mutations, grants, authentication changes or Play deploy.
Encrypted output ONLY; plaintext is confined to an ephemeral CI tempfile.
Original owner device and all A/B/C identities remain untouched.
"""
from __future__ import annotations

import base64
import gzip
import hashlib
import json
import os
import secrets
import sys
import tempfile
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

PROJECT = "deda-25b88"
# The OWNER holds the matching PRIVATE key OFFLINE. Never store it in GitHub.
OWNER_X25519_PUBLIC_KEY_B64 = "CUCspyIbUrWeNSusSOyprE6eoIKayb3AyNZD/nExSSg="
AAD = b"DEDA-SPARK-FIRESTORE-AUTH-ENCRYPTED-SNAPSHOT-v1"
MAX_DOCS = 20000
MAX_AUTH_USERS = 10000
MAX_PLAINTEXT = 100_000_000
MAX_COLLECTION_DEPTH = 15


class SafeStop(Exception):
    pass


def encrypt_payload(data: bytes, owner_public: bytes) -> bytes:
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.asymmetric import x25519
    from cryptography.hazmat.primitives.ciphers.aead import AESGCM
    from cryptography.hazmat.primitives.kdf.hkdf import HKDF
    if len(data) > MAX_PLAINTEXT or len(owner_public) != 32:
        raise SafeStop("INVALID_BACKUP_INPUT_SIZE")
    ephemeral = x25519.X25519PrivateKey.generate()
    peer = x25519.X25519PublicKey.from_public_bytes(owner_public)
    salt, nonce = secrets.token_bytes(16), secrets.token_bytes(12)
    key = HKDF(
        algorithm=hashes.SHA256(), length=32, salt=salt, info=AAD
    ).derive(ephemeral.exchange(peer))
    sealed = AESGCM(key).encrypt(nonce, data, AAD)
    envelope = {
        "format": "deda-spark-firestore-auth-v1",
        "ephemeralPublicKey": base64.b64encode(ephemeral.public_key().public_bytes(
            serialization.Encoding.Raw, serialization.PublicFormat.Raw
        )).decode("ascii"),
        "salt": base64.b64encode(salt).decode("ascii"),
        "nonce": base64.b64encode(nonce).decode("ascii"),
        "ciphertext": base64.b64encode(sealed).decode("ascii"),
    }
    return json.dumps(envelope, separators=(",", ":")).encode("utf-8")


def decrypt_payload_for_test(envelope: bytes, private_key) -> bytes:
    from cryptography.hazmat.primitives import hashes
    from cryptography.hazmat.primitives.asymmetric import x25519
    from cryptography.hazmat.primitives.ciphers.aead import AESGCM
    from cryptography.hazmat.primitives.kdf.hkdf import HKDF
    d = json.loads(envelope)
    eph = x25519.X25519PublicKey.from_public_bytes(base64.b64decode(
        d["ephemeralPublicKey"]))
    key = HKDF(algorithm=hashes.SHA256(), length=32,
               salt=base64.b64decode(d["salt"]), info=AAD).derive(
                   private_key.exchange(eph))
    return AESGCM(key).decrypt(base64.b64decode(d["nonce"]),
                               base64.b64decode(d["ciphertext"]), AAD)


def self_test() -> int:
    from cryptography.hazmat.primitives.asymmetric import x25519
    from cryptography.hazmat.primitives import serialization
    priv = x25519.X25519PrivateKey.generate()
    pub = priv.public_key().public_bytes(
        serialization.Encoding.Raw, serialization.PublicFormat.Raw)
    example = b"test-only-firestore-document-private-not-production"
    cipher = encrypt_payload(example, pub)
    assert decrypt_payload_for_test(cipher, priv) == example
    d = json.loads(cipher)
    d["ciphertext"] = base64.b64encode(b"altered").decode()
    try:
        decrypt_payload_for_test(json.dumps(d).encode(), priv)
    except Exception:
        pass
    else:
        raise AssertionError("tampered archive accepted")
    assert len(base64.b64decode(OWNER_X25519_PUBLIC_KEY_B64)) == 32
    print("PASS_OFFLINE_ENCRYPTION_AUTHENTICITY_AND_OWNER_PUBLIC_KEY")
    return 0


def run() -> int:
    from cryptography.hazmat.primitives import serialization
    from firebase_admin import auth, credentials, firestore, initialize_app
    from google.cloud.firestore_v1._helpers import encode_dict
    from google.protobuf.json_format import MessageToDict

    service_account = os.getenv("DEDA_FIREBASE_SA", "")
    if not service_account:
        raise SafeStop("MISSING_EXISTING_FIREBASE_READ_CREDENTIAL")
    account = json.loads(service_account)
    if account.get("project_id") != PROJECT:
        raise SafeStop("WRONG_FIREBASE_PROJECT")
    app = initialize_app(credentials.Certificate(account), {"projectId": PROJECT},
                         name="deda_readonly_encrypted_snapshot")
    db = firestore.client(app=app)
    output = Path(os.getenv("DEDA_BACKUP_OUTPUT", ""))
    if not output.name or output.suffix != ".dedabackup":
        raise SafeStop("MISSING_SAFE_ENCRYPTED_OUTPUT")

    count = Counter()
    total_docs = 0
    total_users = 0
    visited_paths = set()

    # Write sensitive plaintext only into an ephemeral CI tempfile,
    # NEVER the repo or an Actions artifact.
    temp_path = None
    try:
        with tempfile.NamedTemporaryFile(mode="wb", prefix="deda-ephemeral-",
                                         suffix=".jsonl.gz", delete=False) as handle:
            temp_path = Path(handle.name)
        with gzip.open(temp_path, "wt", encoding="utf-8") as stream:
            stream.write(json.dumps({
                "type": "header", "format": "DEDA_FIREBASE_READONLY_BACKUP_V1",
                "project": PROJECT,
                "scope": ["Firestore/all/root/and/nested", "Auth/public-metadata"],
                "notIncluded": ["Storage binaries", "Auth passwords",
                                "device-local progress", "sign-in tokens"],
                "dateUtc": datetime.now(timezone.utc).isoformat(),
            }) + "\n")

            # Firestore network reads are independent. Bounded parallel
            # retrieval avoids thousands of sequential per-document RPCs.
            # All archive writes and counters remain on this one thread.
            from collections import deque
            from concurrent.futures import ThreadPoolExecutor

            def get_snapshot(ref):
                return ref.get()

            def get_subcollections(ref):
                return list(ref.collections())

            work = deque((collection, 0) for collection in db.collections())
            with ThreadPoolExecutor(max_workers=8) as pool:
                while work:
                    collection, depth = work.popleft()
                    if depth > MAX_COLLECTION_DEPTH:
                        raise SafeStop("FIRESTORE_DEPTH_LIMIT_EXCEEDED")
                    refs = list(collection.list_documents(page_size=100))
                    snaps = pool.map(get_snapshot, refs)
                    for docref, snap in zip(refs, snaps):
                        if docref.path in visited_paths:
                            raise SafeStop("DUPLICATE_DOCUMENT_PATH")
                        visited_paths.add(docref.path)
                        if not snap.exists:
                            continue
                        total_docs += 1
                        if total_docs > MAX_DOCS:
                            raise SafeStop("BACKUP_DOCUMENT_LIMIT_EXCEEDED")
                        values = encode_dict(snap.to_dict() or {})
                        fields = {
                            name: MessageToDict(
                                value._pb if hasattr(value, "_pb") else value,
                                preserving_proto_field_name=True)
                            for name, value in values.items()
                        }
                        record = {
                            "type": "firestoreDocument",
                            "path": docref.path,
                            "createTime": snap.create_time.isoformat()
                                if snap.create_time else None,
                            "updateTime": snap.update_time.isoformat()
                                if snap.update_time else None,
                            "fields": fields,
                        }
                        stream.write(json.dumps(record, ensure_ascii=False,
                                                separators=(",", ":")) + "\n")
                        count[docref.path.split("/")[0]] += 1
                        if total_docs % 1000 == 0:
                            # Count only: never print Firestore paths or PII.
                            print("READONLY_FIRESTORE_DOCUMENTS_PROCESSED",
                                  total_docs, flush=True)
                    # list_documents, unlike stream(), covers refs whose
                    # parent doc is absent but subcollections still exist.
                    for subcollections in pool.map(get_subcollections, refs):
                        for sub in subcollections:
                            work.append((sub, depth + 1))

            # Firebase Auth metadata: UID, email/phone/provider info and
            # creation/last-login fields. Secure password hashes/tokens are
            # never exposed by the supported Admin read APIs.
            for user in auth.list_users(app=app).iterate_all():
                total_users += 1
                if total_users > MAX_AUTH_USERS:
                    raise SafeStop("BACKUP_AUTH_USER_LIMIT_EXCEEDED")
                meta = user.user_metadata
                providers = []
                for p in user.provider_data:
                    providers.append({
                        "providerId": p.provider_id,
                        "uid": p.uid,
                        "email": p.email,
                        "phone": p.phone_number,
                        "displayName": p.display_name,
                        "photoUrl": p.photo_url,
                    })
                record = {
                    "type": "authUserMetadata", "uid": user.uid,
                    "disabled": user.disabled, "email": user.email,
                    "emailVerified": user.email_verified,
                    "phoneNumber": user.phone_number,
                    "displayName": user.display_name,
                    "photoUrl": user.photo_url,
                    "customClaims": user.custom_claims,
                    "creationTimestamp": meta.creation_timestamp if meta else None,
                    "lastSignInTimestamp": meta.last_sign_in_timestamp if meta else None,
                    "providerData": providers,
                }
                stream.write(json.dumps(record, ensure_ascii=False,
                                        separators=(",", ":")) + "\n")

        plaintext = temp_path.read_bytes()
        if len(plaintext) > MAX_PLAINTEXT:
            raise SafeStop("BACKUP_MAX_PLAINTEXT_EXCEEDED")
        owner_public = base64.b64decode(OWNER_X25519_PUBLIC_KEY_B64, validate=True)
        encrypted = encrypt_payload(plaintext, owner_public)
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_bytes(encrypted)
        # Sanitized manifest: no usernames, phone numbers or UIDs.
        manifest = {
            "format": "DEDA_FIREBASE_READONLY_ENCRYPTED_BACKUP_V1",
            "project": PROJECT, "firestoreDocuments": total_docs,
            "authUserMetadataRecords": total_users,
            "rootCollectionDocumentCounts": dict(sorted(count.items())),
            "encryptedFileSha256": hashlib.sha256(encrypted).hexdigest(),
            "encryptedFileBytes": len(encrypted),
            "firestoreAndAuthRead": True,
            "firebaseStorageIncluded": False,
            "authCredentialSecretsIncluded": False,
            "productionWrites": False,
            "signedAppChanged": False,
        }
        output.with_suffix(".manifest.json").write_text(
            json.dumps(manifest, indent=2, ensure_ascii=False) + "\n")
        print("PASS_ENCRYPTED_READONLY_SNAPSHOT_FIRESTORE_DOCUMENTS", total_docs)
        print("PASS_ENCRYPTED_READONLY_SNAPSHOT_AUTH_USER_METADATA", total_users)
        print("PASS_ENCRYPTED_ARTIFACT_ONLY_SHA256", manifest["encryptedFileSha256"])
        print("NO_PII_NO_FIREBASE_WRITES_NO_AUTH_TOKENS_NO_PLAY_DEPLOY")
        return 0
    finally:
        if temp_path is not None:
            temp_path.unlink(missing_ok=True)


if __name__ == "__main__":
    try:
        raise SystemExit(self_test() if sys.argv[1:] == ["--self-test"] else run())
    except SafeStop as e:
        print("SAFE_STOP_" + str(e))
        raise SystemExit(2)
    except Exception as error:
        # Log ONLY exception class and source-code locations, NEVER exception
        # messages, Firebase document paths, user data, phone or UID values.
        import traceback
        print("SAFE_STOP_BACKUP_READ_OR_FORMAT_UNVERIFIED",
              type(error).__module__, type(error).__name__)
        for frame in traceback.extract_tb(error.__traceback__)[-3:]:
            print("SAFE_STOP_SOURCE_LOCATION", Path(frame.filename).name,
                  frame.lineno)
        raise SystemExit(2)
