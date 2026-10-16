#!/bin/zsh
# Creates "Clipi Local Signing", a self-signed code signing certificate in the login keychain.
#
#   scripts/make-signing-cert.sh
#
# ./build.sh signs with it when it exists. Unlike ad-hoc signing, the identity stays the same
# across rebuilds, so macOS keeps Clipi's Accessibility and Full Disk Access permissions.
# To remove it: Keychain Access › login › My Certificates › "Clipi Local Signing" › Delete.
set -euo pipefail

NAME="Clipi Local Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1; then
    echo "✓ \"$NAME\" already exists"
    exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

cat > "$tmp/cert.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$tmp/cert.cnf" \
    -keyout "$tmp/key.pem" -out "$tmp/cert.pem" 2>/dev/null
password="$(uuidgen)"
openssl pkcs12 -export -inkey "$tmp/key.pem" -in "$tmp/cert.pem" -name "$NAME" \
    -out "$tmp/identity.p12" -passout "pass:$password" 2>/dev/null
# -T: codesign may use the key without asking each time
security import "$tmp/identity.p12" -k "$KEYCHAIN" -P "$password" -T /usr/bin/codesign >/dev/null

echo "✓ Created \"$NAME\" in the login keychain"
