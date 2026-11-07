#!/usr/bin/env python3
"""Read-only Firebase Google account chooser readiness; no credentials/keys logged.

The signed 100439 package and original signer must not change. This checks the
Android OAuth client for the package AND the Web OAuth client used for ID tokens.
Google provider activation, Play signing fingerprints and a real device are
independent proof requirements and cannot be inferred from this JSON alone.
"""
import argparse
import json
import re
from pathlib import Path

APP_PACKAGE = "com.diraq.ludo.d_iraq_ludo"
PROJECT_ID = "deda-25b88"
SOURCE_CERT_SHA256 = "a53d855b82d1280f324037428421838139ecf2e30174f9fcd0bd1878698b5f4a"
SOURCE_CERT_SHA1 = "f5d7e13309be6f7af76798a60d72bac880005c58"


def review(config, expected_sha1=SOURCE_CERT_SHA1):
    issues = []
    if config.get("project_info", {}).get("project_id") != PROJECT_ID:
        issues.append("FIREBASE_PROJECT_ID_MISMATCH")
    clients = [
        row for row in config.get("client", [])
        if row.get("client_info", {}).get("android_client_info", {})
            .get("package_name") == APP_PACKAGE
    ]
    if len(clients) != 1:
        issues.append("ANDROID_APP_PACKAGE_CLIENT_NOT_UNIQUE")
        return issues
    oauth = clients[0].get("oauth_client") or []
    android = [
        row for row in oauth if row.get("client_type") == 1
        and row.get("android_info", {}).get("package_name") == APP_PACKAGE
        and re.fullmatch(r"[0-9a-fA-F]{40}", row.get("android_info", {})
                             .get("certificate_hash", ""))
    ]
    web = [
        row for row in oauth if row.get("client_type") == 3
        and isinstance(row.get("client_id"), str)
        and row["client_id"].endswith(".apps.googleusercontent.com")
    ]
    if not android:
        issues.append("ANDROID_OAUTH_SHA1_CLIENT_MISSING")
    if not web:
        issues.append("WEB_OAUTH_ID_TOKEN_CLIENT_MISSING")
    if expected_sha1:
        fingerprint = expected_sha1.lower().replace(":", "")
        if not re.fullmatch(r"[0-9a-f]{40}", fingerprint):
            issues.append("INVALID_EXPECTED_CERT_SHA1")
        elif android and not any(row["android_info"]["certificate_hash"].lower() ==
                     fingerprint for row in android):
            issues.append("RELEASE_SIGNER_SHA1_NOT_REGISTERED")
    return issues


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=Path, default=Path("google-services.json"))
    parser.add_argument("--release-sha1", default=SOURCE_CERT_SHA1,
                        help="Public SHA-1 certificate fingerprint, not a key/password")
    parser.add_argument("--report-only", action="store_true")
    args = parser.parse_args()
    try:
        issues = review(json.loads(args.config.read_text()),
                        expected_sha1=args.release_sha1)
    except (OSError, json.JSONDecodeError, ValueError) as exc:
        issues = ["FIREBASE_CONFIG_INVALID_OR_MISSING"]
    result = {
        "googleOAuthConfigReady": not issues,
        "package": APP_PACKAGE,
        "project": PROJECT_ID,
        "signed100439CertSha256Expected": SOURCE_CERT_SHA256,
        "signed100439CertSha1Expected": SOURCE_CERT_SHA1,
        "issues": issues,
        "stillRequires": [
            "Firebase Authentication Google provider enabled on correct project",
            "original signed APK certificate SHA-1 registered",
            "original signed APK certificate SHA-256 registered",
            "regenerated google-services.json in separately approved isolated build",
            "verified original phone UID and legacy-data backup before provider link",
            "Google consent and SAME UID verified on physical Android phone",
            "replacement device and guardian data recovery tested separately",
        ],
    }
    print(json.dumps(result, ensure_ascii=False, sort_keys=True))
    if issues and not args.report_only:
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
