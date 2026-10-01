#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
tenant=${1:?Usage: psql.sh a|b [psql arguments]}
shift
[[ "$tenant" == a || "$tenant" == b ]] || { echo 'Expected a or b' >&2; exit 2; }
# Sharing the kind node network works with Linux and Docker Desktop alike.
# Connect through its NodePort: this is the same gateway exposed on localhost:15432.
export PGPASSWORD
PGPASSWORD=$(cat "$STATE/passwords/$tenant")
exec docker run --rm --network "container:$CLUSTER_NAME-control-plane" \
  -e PGPASSWORD --user "$(id -u):$(id -g)" -v "$STATE/client:/certs:ro" "$CLIENT_IMAGE" \
  psql -X -w "host=$tenant.db.test hostaddr=127.0.0.1 port=30432 dbname=app user=demo sslmode=verify-full sslnegotiation=direct sslrootcert=/certs/$tenant/server-ca.crt connect_timeout=5" "$@"
