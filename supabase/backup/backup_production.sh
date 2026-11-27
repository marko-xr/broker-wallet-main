#!/usr/bin/env bash
# Broker Wallet production database backup. Procedure and rules:
# docs/PRODUCTION_DATABASE_BACKUP_RUNBOOK.md.
#
#   backup_production.sh <linked-scratch-dir> <work-dir> [destination-root]
#
# <linked-scratch-dir>  a folder outside the repo where `supabase link` ran
# <work-dir>            holds baseline.json (from baseline.sql); receives counts only
# [destination-root]    owner-approved location, default /f/BrokerWallet/ProductionBackups
#
# Streams the Supabase CLI dumps straight into GnuPG: no plaintext file is ever
# written. The passphrase is typed by the owner, never echoed and never stored.
# Run it in an interactive Git Bash; it asks for the passphrase three times.
set -euo pipefail
umask 077

REF=rbvcnvqpdqrhywcgxkne
LINK_DIR=${1:?linked scratch folder required}
WORK=${2:?work folder required}
DEST_ROOT=${3:-/f/BrokerWallet/ProductionBackups}
HERE=$(cd "$(dirname "$0")" && pwd)
export PATH="/c/Program Files/PostgreSQL/17/bin:$PATH"
export PGSSLMODE=require
GPG_COMMON=(--batch --no-symkey-cache --pinentry-mode loopback --passphrase-fd 3)

OK=0
FILE=''
finish() {
  unset P1 P2 P3 2>/dev/null || true
  if [ "$OK" != 1 ] && [ -n "$FILE" ] && [ -e "$FILE" ]; then
    mv -f "$FILE" "$FILE.INCOMPLETE"
    echo "FAILED: the partial output was renamed to .INCOMPLETE"
  fi
}
trap finish EXIT

cd "$LINK_DIR"
[ "$(cat supabase/.temp/project-ref)" = "$REF" ] || { echo "STOP: $LINK_DIR is not linked to $REF"; exit 1; }
[ -s "$WORK/baseline.json" ] || { echo "STOP: $WORK/baseline.json missing (run baseline.sql first)"; exit 1; }
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
OUT_DIR="$DEST_ROOT/$STAMP"
[ ! -e "$OUT_DIR" ] || { echo "STOP: $OUT_DIR already exists"; exit 1; }
NAME="broker-wallet-production-$STAMP.sql.gpg"

echo "Broker Wallet production backup -> $OUT_DIR"
echo "First create and SAVE a new passphrase (20+ characters) in your password manager."
read -rs -p "Backup passphrase: " P1; echo
read -rs -p "Repeat passphrase: " P2; echo
if [ "$P1" != "$P2" ]; then echo "STOP: the two entries differ"; exit 1; fi
unset P2
if [ ${#P1} -lt 20 ]; then echo "STOP: use at least 20 characters"; exit 1; fi

mkdir -p "$OUT_DIR"
FILE="$OUT_DIR/$NAME"
rm -f "$WORK/plain.sha256"
# Windows pg_dump does not accept the abbreviated flag in the CLI's script.
FIX='s/--quote-all-identifier\b/--quote-all-identifiers/'

# One section of the stream. The CLI's script holds a temporary login: it stays
# in memory and goes straight to bash. Never print it.
part() {
  local name=$1; shift
  local script
  script=$(supabase db dump --linked "$@" --dry-run 2>/dev/null) || { echo "STOP: the CLI could not prepare $name" >&2; return 1; }
  case "$script" in *pg_dump*) ;; *) echo "STOP: no dump script for $name" >&2; return 1 ;; esac
  printf -- '-- BW-BACKUP-PART %s\n' "$name"
  printf '%s\n' "$script" | sed "$FIX" | bash || { echo "STOP: dump of $name failed" >&2; return 1; }
  echo "  dumped: $name" >&2
}

echo "Dumping and encrypting (nothing is written unencrypted)..."
{
  part roles --role-only || exit 1
  part schema || exit 1
  printf -- '-- BW-BACKUP-PART restore-setting\nSET session_replication_role = replica;\n'
  part data --data-only --use-copy || exit 1
  printf -- '-- BW-BACKUP-PART restore-setting\nSET session_replication_role = DEFAULT;\n'
  part history_schema --schema supabase_migrations || exit 1
  part history_data --data-only --use-copy --schema supabase_migrations || exit 1
  printf -- '-- BW-BACKUP-PART end\n'
} | tee >(sha256sum | cut -c1-64 > "$WORK/plain.sha256") \
  | gpg "${GPG_COMMON[@]}" --symmetric --cipher-algo AES256 --s2k-mode 3 \
      --s2k-digest-algo SHA512 --s2k-count 65011712 --output "$FILE" 3< <(printf '%s' "$P1")
unset P1
OK=1

for _ in $(seq 1 100); do [ -s "$WORK/plain.sha256" ] && break; sleep 0.1; done
PLAIN_SHA=$(cat "$WORK/plain.sha256")
ENC_SHA=$(sha256sum "$FILE" | cut -c1-64)
SIZE=$(stat -c %s "$FILE")
(cd "$OUT_DIR" && printf '%s  %s\n' "$ENC_SHA" "$NAME" > SHA256SUMS)
echo "Encrypted file: $SIZE bytes, SHA-256 $ENC_SHA"
echo "Decrypted-stream SHA-256: $PLAIN_SHA"

echo
echo "Verification: paste the passphrase FROM YOUR PASSWORD MANAGER (this proves it was saved)."
VERIFIED=0
for attempt in 1 2 3; do
  read -rs -p "Passphrase from password manager: " P3; echo
  set +e
  gpg "${GPG_COMMON[@]}" --quiet --decrypt "$FILE" 3< <(printf '%s' "$P3") \
    | node "$HERE/verify_backup.mjs" "$WORK/baseline.json" "$PLAIN_SHA" > "$WORK/verify.json"
  status=("${PIPESTATUS[@]}")
  set -e
  unset P3
  if [ "${status[0]}" = 0 ]; then VERIFIED=1; break; fi
  echo "Decryption failed (attempt $attempt of 3)."
done
[ "$VERIFIED" = 1 ] || { echo "VERIFY FAILED: the file could not be decrypted with the saved passphrase"; exit 2; }
gpgconf --kill gpg-agent 2>/dev/null || true
echo "Decryption with the saved passphrase: OK (GnuPG integrity check passed)"
echo "Content check: $(node -e "const r=require(process.argv[1]);console.log(r.verdict)" "$WORK/verify.json") (details: $WORK/verify.json, counts only)"
echo "DONE."
