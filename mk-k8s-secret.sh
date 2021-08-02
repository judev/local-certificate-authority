#!/usr/bin/env bash

NAME="$1"
KEY="$2"
CRT="$3"

set -euo pipefail

usage() {
  echo "Usage: $0 secret-name path/to/tls.key path/to/tls.crt" >&2
  exit 1
}

if [ -z "$NAME" ]
then
  usage
fi

if [ ! -f "$KEY" ] || ! grep -F 'BEGIN PRIVATE KEY' "$KEY"
then
  usage
fi

if [ ! -f "$CRT" ] || ! grep -F 'BEGIN CERTIFICATE' "$CRT"
then
  usage
fi

if [ "$(uname -s)" == "Darwin" ]
then
  WFLAG="-b0"
else
  WFLAG="-w0"
fi

cat <<EOT
apiVersion: v1
kind: Secret
metadata:
  name: $NAME
type: kubernetes.io/tls
data:
  tls.crt: $(base64 $WFLAG "$CRT")
  tls.key: $(base64 $WFLAG "$KEY")
EOT