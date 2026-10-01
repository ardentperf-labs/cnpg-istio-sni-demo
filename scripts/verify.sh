#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
query="SELECT i.name, s.ssl, current_setting('server_version_num')::int / 10000 FROM public.cluster_identity i CROSS JOIN pg_stat_ssl s WHERE s.pid = pg_backend_pid()"
run() {
  local host=$1 trust=$2 identity=$3 negotiation=${4:-direct} sni=${5:-1}
  local PGPASSWORD
  if [[ "$identity" == none ]]; then
    PGPASSWORD=
  else
    PGPASSWORD=$(cat "$STATE/passwords/$identity")
  fi
  export PGPASSWORD
  docker run --rm --network "container:$CLUSTER_NAME-control-plane" \
    -e PGPASSWORD --user "$(id -u):$(id -g)" -v "$STATE/client:/certs:ro" "$CLIENT_IMAGE" \
    psql -X -w -At "host=$host hostaddr=127.0.0.1 port=30432 dbname=app user=demo sslmode=verify-full sslnegotiation=$negotiation sslsni=$sni sslrootcert=/certs/$trust/server-ca.crt connect_timeout=5" -c "$query"
}
expect_failure() {
  local label=$1 pattern=$2
  shift 2
  local output
  if output=$(run "$@" 2>&1); then
    echo "FAIL: $label unexpectedly succeeded: $output" >&2; exit 1
  fi
  if ! grep -Eiq "$pattern" <<< "$output"; then
    echo "FAIL: $label failed for an unexpected reason: $output" >&2; exit 1
  fi
  printf 'PASS: %s rejected\n' "$label"
}
for tenant in a b; do
  result=$(run "$tenant.db.test" "$tenant" "$tenant")
  [[ "$result" == "pg-$tenant|f|16" ]] || { echo "FAIL: unexpected backend $result"; exit 1; }
  echo "PASS: $tenant.db.test + password $tenant -> pg16-$tenant (PostgreSQL 16, plaintext backend session)"
done
expect_failure 'password A on cluster B' 'password authentication failed' b.db.test b a
expect_failure 'password B on cluster A' 'password authentication failed' a.db.test a b
expect_failure 'missing password' 'no password supplied' a.db.test a none
expect_failure 'wrong server CA' 'certificate verify failed' a.db.test b a
expect_failure 'unknown SNI' 'closed|reset|EOF|SSL SYSCALL' unknown.db.test a a
expect_failure 'missing SNI' 'closed|reset|EOF|SSL SYSCALL' a.db.test a a direct 0
expect_failure 'legacy PostgreSQL SSL negotiation' 'timeout|closed|reset|EOF' a.db.test a a postgres
echo 'All routing and authentication checks passed.'
