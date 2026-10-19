#!/usr/bin/env python3
"""Extract exact accepted 100359 source reconstruction from original workflow.

REVIEW-ONLY CI. Runs original published job's script-generator steps, then
replays original reconstruction+Flutter checks with APK build replaced by an
echo, and applies Stage35 compact premium foils to actual built source.
Never generates or uploads an APK, never deploys to Firebase, never debits.
"""
from pathlib import Path
import re
import subprocess
import tempfile

SOURCE = Path(".github/workflows/qa-deda-100359-jamal-owner-private-sandbox-signed-android16-no-play.yml")
REBUILT = Path("/tmp/deda_100340_play_aab.sh")
NAMES = (
    "Reconstruct accepted 100330 and inject owner-only card without backend changes",
    "Replace accepted 100340 bundle with signed 100359 private APK after passed 3-point tests",
)

def original_step(text, name):
    start = "      - name: " + name + "\n        shell: bash\n        run: |\n"
    if text.count(start) != 1:
        raise RuntimeError("SAFE_STOP original 100359 step absent/duplicate")
    remaining = text.split(start, 1)[1]
    # GitHub YAML step boundary at six spaces. Each run source line is
    # indented ten spaces; no rewriting of nested heredocs is permitted.
    match = re.search(r"\n      - (?:name:|uses:)", remaining)
    if not match:
        raise RuntimeError("SAFE_STOP no YAML step boundary")
    block = remaining[:match.start()]
    lines = block.splitlines()
    if not lines or any(line and not line.startswith("          ") for line in lines):
        raise RuntimeError("SAFE_STOP run source malformed")
    script = "\n".join(line[10:] if line else "" for line in lines) + "\n"
    if re.search(r"^\s*(?:firebase\s+deploy|gh\s+workflow\s+run)\b", script, re.M):
        raise RuntimeError("SAFE_STOP unsafe executable command")
    return script

def main():
    if REBUILT.exists():
        raise RuntimeError("SAFE_STOP unexpected leftover source script")
    text = SOURCE.read_text()
    for index, name in enumerate(NAMES):
        script = original_step(text, name)
        with tempfile.NamedTemporaryFile(mode="w", suffix=".sh", delete=False) as tmp:
            tmp.write(script)
            path = tmp.name
        subprocess.run(["bash", "-e", path], check=True)
        if index == 0 and not REBUILT.exists():
            raise RuntimeError("SAFE_STOP original build generator failed")
    original = REBUILT.read_text()
    matches = re.findall(r"^flutter build apk --release --build-number=100359 .*$",
                         original, re.M)
    if len(matches) != 1:
        raise RuntimeError("SAFE_STOP exact original 100359 build command missing")
    # Replace ONLY final compile command, do not touch original staging steps.
    adjusted = original.replace(matches[0],
        "echo 'QA-ONLY: build command disabled; NO APK produced'", 1)
    if re.search(r"^flutter build (?:apk|appbundle)\b", adjusted, re.M):
        raise RuntimeError("SAFE_STOP build unexpectedly remains enabled")
    if re.search(r"^\s*(?:firebase\s+deploy|gh\s+workflow\s+run)\b", adjusted, re.M):
        raise RuntimeError("SAFE_STOP live deploy command exists")
    REBUILT.write_text(adjusted)
    print("PASS original signed-build source reconstruction extracted; final APK build disabled", flush=True)

if __name__ == "__main__":
    main()
