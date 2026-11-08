#!/usr/bin/env python3
"""Fail-closed stage8 QA device-lab configuration validator.

No Firebase API calls. No production config modification or deployment.
Run with a local, uncommitted JSON file passed as --config. Never echo keys.
"""
from __future__ import annotations
import argparse
import json
import re
from pathlib import Path

QA_ANDROID = "com.deda.qa.uiddevice"
PROD_ANDROID = "com.diraq.ludo.d_iraq_ludo"
PROD_FIREBASE_PROJECT = "deda-25b88"
EXPECTED_KEYS = {
    "LAB_QA_PROJECT_ID",
    "LAB_QA_FIREBASE_APP_ID",
    "LAB_QA_SENDER_ID",
    "LAB_QA_API_KEY",
    "LAB_QA_GOOGLE_WEB_CLIENT_ID",
}
PROJ = re.compile(r"^deda-qa-uid-lab-[a-z0-9-]{4,40}$")
APP = re.compile(r"^1:([0-9]+):android:([a-fA-F0-9]+)$")
GOOGLE = re.compile(r"^[0-9]+-[A-Za-z0-9_-]+\.apps\.googleusercontent\.com$")


def check_config(data: dict, production_data: dict | None = None) -> str:
    if not isinstance(data, dict) or set(data) != EXPECTED_KEYS or not all(
        isinstance(v, str) for v in data.values()
    ):
        return "QA_CONFIG_KEYS_MISSING_OR_UNEXPECTED"
    project_id = data["LAB_QA_PROJECT_ID"]
    if not PROJ.fullmatch(project_id) or project_id == PROD_FIREBASE_PROJECT:
        return "QA_PROJECT_ID_NOT_DISTINCT"
    app = APP.fullmatch(data["LAB_QA_FIREBASE_APP_ID"])
    if not app or app.group(1) != data["LAB_QA_SENDER_ID"]:
        return "QA_APP_SENDER_MISMATCH"
    api_key = data["LAB_QA_API_KEY"]
    if len(api_key) < 20 or re.fullmatch(r"[A-Za-z0-9_-]+", api_key) is None:
        return "QA_API_KEY_INVALID"
    if not GOOGLE.fullmatch(data["LAB_QA_GOOGLE_WEB_CLIENT_ID"]):
        return "QA_GOOGLE_WEB_CLIENT_ID_INVALID"
    if production_data:
        prod = production_data.get("project_info") or {}
        client = production_data.get("client") or []
        forbidden_projects = {PROD_FIREBASE_PROJECT, prod.get("project_id")}
        forbidden_app_ids = {
            c.get("client_info", {}).get("mobilesdk_app_id") for c in client
        }
        forbidden_api_keys = {
            k.get("current_key")
            for c in client
            for k in c.get("api_key", [])
        }
        forbidden_oauth_ids = {
            o.get("client_id")
            for c in client
            for o in c.get("oauth_client", [])
        }
        if (project_id in forbidden_projects or
            data["LAB_QA_FIREBASE_APP_ID"] in forbidden_app_ids or
            api_key in forbidden_api_keys or
            data["LAB_QA_GOOGLE_WEB_CLIENT_ID"] in forbidden_oauth_ids):
            return "LIVE_FIREBASE_CONFIGURATION_REJECTED"
    return "QA_ISOLATION_CONFIG_VALID"


def checked_build_package(package: str) -> str:
    if package != QA_ANDROID or package == PROD_ANDROID:
        return "QA_ANDROID_PACKAGE_MISMATCH"
    return "QA_ANDROID_PACKAGE_VALID"


def main() -> int:
    parser = argparse.ArgumentParser(description="QA-only Firebase config guard")
    parser.add_argument("--config", required=True, type=Path)
    parser.add_argument("--repo-root", required=True, type=Path)
    parser.add_argument("--android-package", default=QA_ANDROID)
    args = parser.parse_args()
    repo_root = args.repo_root.resolve(strict=True)
    config_file = args.config.resolve(strict=True)
    # A QA config is an operator-local file, never an artifact in GitHub.
    if config_file.is_relative_to(repo_root):
        print("DENIED:QA_CONFIG_MUST_BE_OUTSIDE_GIT_REPOSITORY")
        return 3
    if checked_build_package(args.android_package) != "QA_ANDROID_PACKAGE_VALID":
        print("DENIED:QA_ANDROID_PACKAGE_MISMATCH")
        return 4
    try:
        qa = json.loads(config_file.read_text(encoding="utf-8"))
        production = json.loads((repo_root / "google-services.json")
                                .read_text(encoding="utf-8"))
    except (ValueError, OSError):
        print("DENIED:QA_CONFIG_READ_INVALID")
        return 5
    status = check_config(qa, production)
    if status != "QA_ISOLATION_CONFIG_VALID":
        print("DENIED:" + status)
        return 6
    print("PASS_QA_SEPARATE_FIREBASE_PROJECT_AND_UNIQUE_ANDROID_PACKAGE")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
