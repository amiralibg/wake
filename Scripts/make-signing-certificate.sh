#!/bin/bash
# Makes the self-signed code signing certificate that release builds are signed
# with when there's no Apple Developer ID. Run once, from anywhere:
#
#   Scripts/make-signing-certificate.sh
#
# macOS doesn't trust it, and doesn't need to: Gatekeeper treats the app like an
# ad hoc signed one. What it adds is one identity for every release, so macOS
# recognises an updated Wake as the same app and keeps its data, keychain items
# and privacy permissions. An ad hoc signature is different on every build.
#
# Writes ~/.wake-release/signing-certificate.p12 and its password next to it. Keep
# both: a new certificate is a new identity, and users go through that once more.
set -euo pipefail

DIR="$HOME/.wake-release"
P12="$DIR/signing-certificate.p12"
PASSWORD_FILE="$DIR/signing-certificate-password"
NAME="Wake Self-Signed Code Signing"

if [ -e "$P12" ]; then
  echo "$P12 already exists. Delete it first to make a new identity (users would see it as a different app once)." >&2
  exit 1
fi

mkdir -p "$DIR" && chmod 700 "$DIR"
WORK=$(mktemp -d) && trap 'rm -rf "$WORK"' EXIT
umask 077

cat > "$WORK/openssl.cnf" <<EOF
[req]
distinguished_name = dn
prompt = no
x509_extensions = ext
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
subjectKeyIdentifier = hash
EOF

# macOS's LibreSSL writes a .p12 that `security import` reads; OpenSSL 3 needs -legacy.
OPENSSL=/usr/bin/openssl
"$OPENSSL" req -x509 -newkey rsa:3072 -sha256 -days 7300 -nodes \
  -config "$WORK/openssl.cnf" -keyout "$WORK/key.pem" -out "$WORK/cert.pem" 2> /dev/null
"$OPENSSL" rand -base64 24 | tr -d '\n' > "$PASSWORD_FILE"
"$OPENSSL" pkcs12 -export -name "$NAME" -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
  -out "$P12" -passout file:"$PASSWORD_FILE"

echo "Made $P12"
echo "Leaf SHA-256: $("$OPENSSL" x509 -in "$WORK/cert.pem" -noout -fingerprint -sha256 | cut -d= -f2)"
echo
echo "Add it to the release workflow's secrets:"
echo "  base64 -i \"$P12\" | gh secret set SELF_SIGNED_CERTIFICATE"
echo "  gh secret set SELF_SIGNED_CERTIFICATE_PASSWORD < \"$PASSWORD_FILE\""
