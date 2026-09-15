#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
OUT_DIR="$ROOT_DIR/.sparkle"
PEM_PATH="$OUT_DIR/eddsa_private.pem"
KEY_PATH="$OUT_DIR/eddsa_priv.key"
PUB_PATH="$OUT_DIR/eddsa_pub.txt"

mkdir -p "$OUT_DIR"
chmod 700 "$OUT_DIR"

if [ -f "$KEY_PATH" ] || [ -f "$PEM_PATH" ]; then
    printf '%s\n' "Sparkle keys already exist in $OUT_DIR; refusing to overwrite." >&2
    exit 1
fi

openssl genpkey -algorithm ED25519 -out "$PEM_PATH"
chmod 600 "$PEM_PATH"

python3 - "$PEM_PATH" "$KEY_PATH" "$PUB_PATH" <<'PY'
import base64
import subprocess
import sys
from pathlib import Path

pem_path, key_path, pub_path = map(Path, sys.argv[1:])
der = subprocess.check_output(["openssl", "pkey", "-in", str(pem_path), "-outform", "DER"])
pub_der = subprocess.check_output(["openssl", "pkey", "-in", str(pem_path), "-pubout", "-outform", "DER"])
public_key = pub_der[-32:]
seed_index = der.find(b"\x04\x20")
if seed_index < 0:
    raise SystemExit("Unable to locate Ed25519 seed in PKCS#8 key")
seed = der[seed_index + 2:seed_index + 34]
if len(public_key) != 32 or len(seed) != 32:
    raise SystemExit("Unexpected Ed25519 key length")
key_path.write_text(base64.b64encode(seed).decode() + "\n")
key_path.chmod(0o600)
pub_path.write_text(base64.b64encode(public_key).decode() + "\n")
print(pub_path.read_text().strip())
PY

printf 'Wrote private key to %s\n' "$KEY_PATH"
printf 'Put the printed public key in Resources/Info.plist as SUPublicEDKey.\n'
printf 'Store the private key as GitHub secret SPARKLE_ED_PRIVATE_KEY. Do not commit %s.\n' "$OUT_DIR"
