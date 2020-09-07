#!/usr/bin/env bash
# based on: https://unix.stackexchange.com/questions/382786/the-correct-way-of-implementing-ssl-on-localhost

set -euo pipefail

HERE=$(dirname "$BASH_SOURCE")

# Where generated certs are stored
CERT_PATH="${HERE}/certificates" 

# Certs will last Approx 20 years
CERT_AGE=$((7 * 52 * 20))

test -d "$CERT_PATH" || mkdir -p -m0700 "$CERT_PATH"

# First, create a Certificate Authority cert if it's not already been done

CA_BASE_PATH="${CERT_PATH}/ca"

if [ ! -f "${CA_BASE_PATH}.key" ] || [ ! -f "${CA_BASE_PATH}.crt" ]
then
  read -p "Enter a name for your Certificate Authority: " CA_NAME
  echo "$CA_NAME" > "${CA_BASE_PATH}-name.txt"

  cat > "${CA_BASE_PATH}.cnf" <<EOT
[ req ]
prompt             = no
string_mask        = default
default_bits       = 2048
distinguished_name = req_distinguished_name
x509_extensions    = x509_ext
[ req_distinguished_name ]
countryName = gb
organizationName = ${CA_NAME}
commonName = ${CA_NAME}
[ x509_ext ]
basicConstraints=critical,CA:true,pathlen:0
keyUsage=critical,keyCertSign,cRLSign
EOT

  echo "Enter a password for your CA. You will need this when generating SSL certificates."
  read -s -p "Password: " CA_PASSWORD
  openssl req -x509 -days "$CERT_AGE" -new -keyout "${CA_BASE_PATH}.key" -out "${CA_BASE_PATH}.crt" -passout "pass:${CA_PASSWORD}" -config "${CA_BASE_PATH}.cnf"

  # Optionally install the CA certificate to this machine's trust store

  read -p "Install root CA to your keychain / trust store? y/n: " yn
  if [ "$yn" == "y" ]
  then
    echo
    echo "You may be prompted for your login password as this command uses sudo."
    echo
    if [ "$(uname -s)" == "Darwin" ]
    then
      sudo security add-trusted-cert -d -r trustRoot -k "/Library/Keychains/System.keychain" "${CA_BASE_PATH}.crt"
    else

      [ -d /usr/local/share/ca-certificates/extra ] || sudo mkdir -p /usr/local/share/ca-certificates/extra
      sudo cp "${CA_BASE_PATH}.crt" "/usr/local/share/ca-certificates/extra/${CA_NAME}.crt"
      sudo update-ca-certificates

      [ -d ~/.pki/nssdb ] || mkdir -p ~/.pki/nssdb

      set +e
      while true
      do
        certutil -d sql:$HOME/.pki/nssdb -D -n "$CA_NAME" >/dev/null 2>&1 || break
      done
      certutil -d sql:$HOME/.pki/nssdb -A -n "$CA_NAME" -i "${CA_BASE_PATH}.crt" -t TCP,TCP,TCP

    fi
  fi

fi

# Generate a key and certificate pair using our Certificate Authority

CA_NAME=$(cat "${CA_BASE_PATH}-name.txt")
echo "Generate an SSL certificate using your Certificate Authority."
echo "Enter one or more DNS names, space-separated, wildcards are allowed."
echo "e.g: localhost *.local *.example.local"

read -p "DNS names: " DNS_NAMES
if [ -z "$DNS_NAMES" ]
then
  echo "Aborting" >&2
  exit 1
fi

read -a DOMAINS <<< "$DNS_NAMES"

NAME=$(echo "${DOMAINS[0]}" | sed 's/\*/wildcard/')

CERT_BASE_PATH="${CERT_PATH}/${NAME}"

if [ -f "${CERT_BASE_PATH}.cnf" ]
then
  read -p "Overwrite existing ${NAME} certificate? y/n: " yn
  if [ "$yn" != "y" ]
  then
    echo "Aborting" >&2
    exit 1
  fi
fi

cat > "${CERT_BASE_PATH}.cnf" <<EOT
[ req ]
prompt             = no
string_mask        = default
default_bits       = 2048
distinguished_name = req_distinguished_name
x509_extensions    = x509_ext
[ req_distinguished_name ]
countryName = gb
organizationName = $CA_NAME
commonName = ${NAME}
[ x509_ext ]
keyUsage=critical,digitalSignature,keyAgreement
subjectAltName = @alt_names
[alt_names]
$(for i in ${!DOMAINS[@]}; do echo "DNS.$((i + 1)) = ${DOMAINS[$i]}"; done)
EOT

openssl req -days "$CERT_AGE" -nodes -new -keyout "${CERT_BASE_PATH}.key" -out "${CERT_BASE_PATH}.csr" -config "${CERT_BASE_PATH}.cnf"
openssl x509 -req -days "$CERT_AGE" -in "${CERT_BASE_PATH}.csr" -CA "${CA_BASE_PATH}.crt" -CAkey "${CA_BASE_PATH}.key" -set_serial $RANDOM -out "${CERT_BASE_PATH}.crt" -extfile "${CERT_BASE_PATH}.cnf" -extensions x509_ext

cat "${CERT_BASE_PATH}.key" "${CERT_BASE_PATH}.crt" > "${CERT_BASE_PATH}.pem"

echo
echo "Now copy the following 2 files to your HTTPS server config:"
echo "${CERT_BASE_PATH}.key"
echo "${CERT_BASE_PATH}.crt"
echo
echo "Or use this .pem file:"
echo "${CERT_BASE_PATH}.pem"
echo

