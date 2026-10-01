#!/usr/bin/env bash
# Create separate PG16 data volumes; never downgrade the existing PG17 clusters.
source "$(dirname "$0")/common.sh"
PG16_IMAGE=ghcr.io/cloudnative-pg/postgresql:16.13-standard-bookworm
mkdir -p "$STATE/pg16"
for tenant in a b; do
  kubectl -n databases get cluster "pg-$tenant" -o json |
    python3 -c '
import json, sys
cluster = json.load(sys.stdin)
tenant, image = sys.argv[1:]
spec = cluster["spec"]
spec["imageName"] = image
print(json.dumps({"apiVersion": cluster["apiVersion"], "kind": "Cluster",
    "metadata": {"name": "pg16-" + tenant, "namespace": "databases"}, "spec": spec}))
' "$tenant" "$PG16_IMAGE" | kubectl apply -f -
done
for tenant in a b; do
  kubectl -n databases wait --for=condition=Ready "cluster/pg16-$tenant" --timeout=600s
done
# Restore exactly the previous route destinations, even if a check fails.
for tenant in a b; do
  kubectl -n databases get virtualservice "postgres-$tenant" -o jsonpath='{.spec.tcp}' \
    > "$STATE/pg16/route-$tenant.json"
done
restore_routes() {
  local status=$?
  trap - EXIT
  for tenant in a b; do
    patch=$(python3 -c 'import json,sys; print(json.dumps({"spec":{"tcp":json.load(open(sys.argv[1]))}}))' "$STATE/pg16/route-$tenant.json")
    kubectl -n databases patch virtualservice "postgres-$tenant" --type=merge -p "$patch" || status=1
  done
  exit "$status"
}
trap restore_routes EXIT
for tenant in a b; do
  kubectl -n databases patch virtualservice "postgres-$tenant" --type=json \
    -p "[{\"op\":\"replace\",\"path\":\"/spec/tcp/0/route/0/destination/host\",\"value\":\"pg16-$tenant-rw.databases.svc.cluster.local\"}]"
done
# Wait for Envoy to receive both routes, rather than assuming immediate propagation.
for tenant in a b; do
  ready=false
  for attempt in {1..30}; do
    version=$("$ROOT/scripts/psql.sh" "$tenant" -Atc 'SHOW server_version_num' 2>/dev/null) || version=
    if [[ "$version" =~ ^16[0-9]{4}$ ]]; then ready=true; break; fi
    sleep 1
  done
  "$ready" || { echo "PG16 route $tenant did not become ready" >&2; exit 1; }
done
EXPECTED_SERVER_MAJOR=16 "$ROOT/scripts/verify.sh"
for tenant in a b; do
  "$ROOT/scripts/psql.sh" "$tenant" -c "SELECT i.name, version(), s.ssl AS backend_ssl FROM cluster_identity i CROSS JOIN pg_stat_ssl s WHERE s.pid = pg_backend_pid()"
done
echo 'PostgreSQL 16 verified. Restoring original routes; pg16-a and pg16-b remain for inspection.'
