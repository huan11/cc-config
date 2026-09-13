#!/usr/bin/env bash
# W34 run-info: single-shot collector. Uploads the PowerShell collector once,
# runs it once, prints one JSON blob on stdout.
#
#   w34-run-info.sh <project>
#
# Design notes (learned the hard way):
#   - One round trip beats thirteen. All probing happens inside the .ps1.
#   - ControlMaster reuse makes the upload+run pair cheap and removes the need
#     for defensive sleeps between calls.
#   - No pipes on the command that decides success: a pipe returns the exit
#     code of the last stage, masking remote failure.
set -uo pipefail

PROJECT="${1:-}"
[ -z "$PROJECT" ] && { echo "usage: w34-run-info.sh <project>" >&2; exit 2; }

HOST=administrator@47.101.52.34
CP=/tmp/w34-cm-$$
PS_LOCAL="$(dirname "$0")/w34-run-info-collect.ps1"
[ -f "$PS_LOCAL" ] || { echo "collector not found: $PS_LOCAL" >&2; exit 2; }

export LC_ALL=C
SSHOPTS=(-o StrictHostKeyChecking=no -o ConnectTimeout=25 -o ControlPath="$CP")
cleanup() { ssh -O exit -o ControlPath="$CP" "$HOST" 2>/dev/null || true; }
trap cleanup EXIT

# 1) open the shared connection and make sure C:\Temp exists
#    Key-based auth since 2026-09-13 (public key in C:\ProgramData\ssh\administrators_authorized_keys).
#    No password anywhere: BatchMode makes a missing key fail loudly instead of prompting.
ssh "${SSHOPTS[@]}" -o BatchMode=yes -o ControlMaster=auto -o ControlPersist=120 "$HOST" \
  'if not exist C:\Temp mkdir C:\Temp' >/dev/null 2>&1 \
  || { echo "ssh failed (key auth; check ~/.ssh/id_ed25519)" >&2; exit 1; }

# 2) upload as base64, then decode remotely (raw scp of .ps1 can trip on CRLF/BOM)
base64 -i "$PS_LOCAL" > "/tmp/w34-collect-$$.b64"
scp -o ControlPath="$CP" "/tmp/w34-collect-$$.b64" "$HOST:C:/Temp/collect.b64" >/dev/null 2>&1 \
  || { echo "scp failed" >&2; exit 1; }
rm -f "/tmp/w34-collect-$$.b64"
ssh -o ControlPath="$CP" "$HOST" \
  'powershell -NoProfile -Command "[IO.File]::WriteAllBytes(\"C:\Temp\collect.ps1\",[Convert]::FromBase64String((Get-Content -Raw \"C:\Temp\collect.b64\")))"' \
  >/dev/null 2>&1 || { echo "decode failed" >&2; exit 1; }

# 3) run it once; no pipe, so the exit code is the remote one
ssh -o ControlPath="$CP" "$HOST" \
  "powershell -NoProfile -ExecutionPolicy Bypass -File C:\\Temp\\collect.ps1 -Project $PROJECT"
