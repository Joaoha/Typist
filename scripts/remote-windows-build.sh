#!/usr/bin/env bash
# Builds the Typist Windows installers on the Windows PC over SSH, from this
# Mac, and copies them back into dist-windows/.
#
# One-time PC setup (at the PC, as administrator):
#   powershell -ExecutionPolicy Bypass -File build-windows.ps1 -EnableRemote -PublicKey "<key>"
# and an ~/.ssh/config entry for the PC (default name: typist-windows).
#
# Usage: scripts/remote-windows-build.sh [branch]      (default: typist-main)
# Env:   TYPIST_WIN_HOST   the ssh host/alias (default: typist-windows)
#
# The code travels as a git bundle of the COMMITTED branch, so the PC needs no
# GitHub login (a key-based Windows SSH session can't unlock stored
# credentials anyway). Uncommitted changes are not included.
set -euo pipefail

HOST="${TYPIST_WIN_HOST:-typist-windows}"
BRANCH="${1:-typist-main}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/dist-windows"
SSH=(ssh -o BatchMode=yes -o ConnectTimeout=10 "$HOST")

# Run a PowerShell script on the PC. -EncodedCommand (base64 UTF-16LE) gets it
# past cmd.exe, the default SSH shell on Windows, without quoting trouble.
remote_ps() {
  local encoded
  encoded=$(printf '%s' "$1" | iconv -f UTF-8 -t UTF-16LE | base64 | tr -d '\n')
  "${SSH[@]}" "powershell -NoProfile -ExecutionPolicy Bypass -EncodedCommand $encoded"
}

echo "==> Checking $HOST"
"${SSH[@]}" "echo ok" >/dev/null || {
  echo "Can't reach $HOST over SSH. Is the PC on, awake and on the home network?" >&2
  exit 1
}

if [ -n "$(git -C "$ROOT" status --porcelain)" ]; then
  echo "Note: uncommitted changes are NOT part of this build (only $BRANCH as committed)."
fi
echo "==> Sending $BRANCH @ $(git -C "$ROOT" rev-parse --short "$BRANCH")"
BUNDLE="$(mktemp -d)/typist.bundle"
git -C "$ROOT" bundle create "$BUNDLE" "$BRANCH" 2>/dev/null
scp -q -o BatchMode=yes "$BUNDLE" "$HOST:typist.bundle"
rm -rf "$(dirname "$BUNDLE")"

echo "==> Building on $HOST (streams the PC's output; first build 20-40 min)"
# git goes through cmd so its stderr progress isn't turned into fatal errors
# (see Invoke-Native in build-windows.ps1); the exit code decides.
remote_ps "
\$repo = Join-Path \$env:USERPROFILE 'Typist'
\$bundle = Join-Path \$env:USERPROFILE 'typist.bundle'
if (-not (Test-Path (Join-Path \$repo '.git'))) {
  cmd /c \"git clone --branch $BRANCH \`\"\$bundle\`\" \`\"\$repo\`\" 2>&1\"
} else {
  # The checkout is a build mirror of this Mac's branch: match it exactly.
  cmd /c \"git -C \`\"\$repo\`\" fetch \`\"\$bundle\`\" +${BRANCH}:refs/remotes/mac/${BRANCH} 2>&1\"
  if (\$LASTEXITCODE -eq 0) { cmd /c \"git -C \`\"\$repo\`\" checkout -f -B $BRANCH refs/remotes/mac/${BRANCH} 2>&1\" }
}
if (\$LASTEXITCODE -ne 0) { Write-Host 'Could not update the checkout from the bundle.'; exit 1 }
& (Join-Path \$repo 'scripts\\build-windows.ps1') -SkipInstall -NoFetch -Branch '$BRANCH' -OutDir (Join-Path \$env:USERPROFILE 'typist-installers')
exit \$LASTEXITCODE
"

echo "==> Copying the installers back"
mkdir -p "$OUT"
scp -q -o BatchMode=yes "$HOST:typist-installers/Typist_*" "$OUT/"
ls -l "$OUT"/Typist_* 2>/dev/null
echo "Done: $OUT"
