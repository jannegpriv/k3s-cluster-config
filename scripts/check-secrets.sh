#!/usr/bin/env bash
# Stop secrets from reaching this public repository.
#   scripts/check-secrets.sh          check what is staged (used by .githooks/pre-commit)
#   scripts/check-secrets.sh --all    check every tracked file (used by CI)
# Enable the hook once per clone:  git config core.hooksPath .githooks
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

# name<TAB>extended regex
PATTERNS=$(cat <<'P'
Mattermost incoming webhook	hooks/[a-z0-9]{26}([^a-z0-9]|$)
Anthropic API key	sk-ant-[A-Za-z0-9_-]{20,}
Slack token	xox[abpr]-[A-Za-z0-9-]{10,}
GitHub token	gh[pousr]_[A-Za-z0-9]{30,}
Private key	-----BEGIN [A-Z ]*PRIVATE KEY-----
P
)

if [ "${1:-}" = "--all" ]; then
  mode=all
  files=$(git ls-files)
else
  mode=staged
  files=$(git diff --cached --name-only --diff-filter=ACMR)
fi
[ -z "$files" ] && exit 0

fail=0
while IFS= read -r f; do
  [ -z "$f" ] && continue
  [ "$f" = "scripts/check-secrets.sh" ] && continue
  if [ "$mode" = all ]; then
    [ -f "$f" ] || continue
    content=$(cat -- "$f" 2>/dev/null | LC_ALL=C tr -d '\000')
  else
    content=$(git show ":$f" 2>/dev/null | LC_ALL=C tr -d '\000')
  fi
  while IFS=$'\t' read -r name re; do
    n=$(printf '%s\n' "$content" | LC_ALL=C grep -E -c -- "$re" || true)
    if [ "${n:-0}" -gt 0 ]; then
      echo "SECRET? $f: $name ($n line(s))" >&2
      fail=1
    fi
  done <<<"$PATTERNS"
  # A file named *.enc.yaml must really be SOPS-encrypted.
  case "$f" in
    *.enc.yaml|*.enc.yml)
      if ! printf '%s\n' "$content" | grep -q '^sops:'; then
        echo "NOT ENCRYPTED: $f has no sops block (run: sops -e -i $f)" >&2
        fail=1
      fi ;;
  esac
done <<<"$files"

# gitleaks adds its own rule set when it is installed (brew install gitleaks).
if [ "$mode" = staged ] && command -v gitleaks >/dev/null 2>&1; then
  gitleaks protect --staged --redact --no-banner -c .gitleaks.toml || fail=1
fi

if [ "$fail" -ne 0 ]; then
  cat >&2 <<'MSG'

Commit stopped: the repository is public.
Put the value in a SOPS-encrypted *.enc.yaml secret and reference it
(n8n: $env.MATTERMOST_HOOK_<CHANNEL>, see n8n-workflows/README.md).
MSG
  exit 1
fi
