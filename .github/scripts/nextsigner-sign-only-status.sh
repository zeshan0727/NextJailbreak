#!/usr/bin/env bash
set -euo pipefail

STATE="${1:-running}"
STAGE="${2:-Unknown}"
MESSAGE="${3:-Working}"
REQUEST_ID="${REQUEST_ID:-}"
INBOX_TAG="${INBOX_TAG:-nextsigner-inbox}"

[ -n "$REQUEST_ID" ] || exit 0

STAMP="$(date +%s%N)"
STATUS_NAME="status-$REQUEST_ID-$STAMP.json"
STATUS_FILE="$RUNNER_TEMP/$STATUS_NAME"

python3 - "$REQUEST_ID" "$STATE" "$STAGE" "$MESSAGE" "$GITHUB_RUN_ID" "$GITHUB_REPOSITORY" "$STATUS_FILE" <<'PY'
import json, os, sys
from datetime import datetime, timezone
request_id, state, stage, message, run_id, repository, path = sys.argv[1:]
payload = {
    "request_id": request_id,
    "state": state,
    "stage": stage,
    "message": message,
    "run_url": f"https://github.com/{repository}/actions/runs/{run_id}",
    "updated_at": datetime.now(timezone.utc).isoformat(),
}
optional = {
    "result_url": "SIGNED_URL",
    "result_filename": "SIGNED_FILENAME",
    "result_sha256": "SIGNED_SHA256",
    "result_size": "SIGNED_SIZE",
    "result_bundle_id": "APP_BUNDLE_ID",
    "result_app_name": "APP_NAME",
    "result_version": "APP_VERSION",
    "result_build": "APP_BUILD",
    "staging_object_key": "STAGING_OBJECT_KEY",
}
for json_key, env_key in optional.items():
    value = os.environ.get(env_key, "")
    if not value:
        continue
    if json_key == "result_size":
        try:
            value = int(value)
        except ValueError:
            pass
    payload[json_key] = value
with open(path, "w", encoding="utf-8") as f:
    json.dump(payload, f, separators=(",", ":"))
PY

gh release upload "$INBOX_TAG" "$STATUS_FILE" >/dev/null

LEGACY_FILE="$RUNNER_TEMP/status-$REQUEST_ID.json"
cp "$STATUS_FILE" "$LEGACY_FILE"
gh release upload "$INBOX_TAG" "$LEGACY_FILE" --clobber >/dev/null 2>&1 || true
