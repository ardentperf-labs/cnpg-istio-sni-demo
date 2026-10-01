#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
umask 077
for tenant in a b; do
  dir="$STATE/gateway/$tenant"
  mkdir -p "$dir" "$STATE/client/$tenant"
  if [[ ! -f "$dir/server.crt" ]]; then
    openssl req -x509 -newkey rsa:2048 -nodes -days 30 \
      -subj "/CN=demo-gateway-ca-$tenant" \
      -addext 'basicConstraints=critical,CA:TRUE' \
      -addext 'keyUsage=critical,keyCertSign,cRLSign' \
      -keyout "$dir/ca.key" -out "$dir/ca.crt" 2>/dev/null
    openssl req -new -newkey rsa:2048 -nodes -subj "/CN=$tenant.db.test" \
      -keyout "$dir/server.key" -out "$dir/server.csr" 2>/dev/null
    printf 'subjectAltName=DNS:%s.db.test\nbasicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth\n' "$tenant" > "$dir/server.ext"
    openssl x509 -req -in "$dir/server.csr" -CA "$dir/ca.crt" -CAkey "$dir/ca.key" \
      -CAcreateserial -days 30 -extfile "$dir/server.ext" -out "$dir/server.crt" 2>/dev/null
  fi
  kubectl -n istio-system create secret tls "postgres-$tenant-tls" \
    --cert="$dir/server.crt" --key="$dir/server.key" --dry-run=client -o yaml | kubectl apply -f -
  cp "$dir/ca.crt" "$STATE/client/$tenant/server-ca.crt"
done
