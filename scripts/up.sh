#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
for tool in docker kind kubectl helm openssl; do command -v "$tool" >/dev/null; done
mkdir -p "$STATE"
chmod 700 "$STATE"
if kind get clusters 2>/dev/null | grep -qx "$CLUSTER_NAME"; then
  kind export kubeconfig --name "$CLUSTER_NAME" --kubeconfig "$KUBECONFIG"
else
  kind create cluster --name "$CLUSTER_NAME" --image "$NODE_IMAGE" \
    --config "$ROOT/manifests/kind.yaml" --kubeconfig "$KUBECONFIG" --wait 120s
fi
helm repo add istio https://istio-release.storage.googleapis.com/charts --force-update
helm repo add cnpg https://cloudnative-pg.github.io/charts --force-update
helm repo update
helm upgrade --install istio-base istio/base --version "$ISTIO_VERSION" \
  -n istio-system --create-namespace --wait --timeout 5m
helm upgrade --install istiod istio/istiod --version "$ISTIO_VERSION" \
  -n istio-system --set pilot.resources.requests.cpu=100m --wait --timeout 5m
helm upgrade --install istio-ingressgateway istio/gateway --version "$ISTIO_VERSION" \
  -n istio-system -f "$ROOT/manifests/gateway-values.yaml" --wait --timeout 5m
helm upgrade --install cnpg cnpg/cloudnative-pg --version "$CNPG_CHART_VERSION" \
  -n cnpg-system --create-namespace --wait --timeout 5m
kubectl create namespace databases --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespace databases istio-injection=disabled --overwrite
for tenant in a b; do
  mkdir -p "$STATE/passwords"
  if [[ ! -f "$STATE/passwords/$tenant" ]]; then
    (umask 077; printf %s "$(openssl rand -hex 24)" > "$STATE/passwords/$tenant")
  fi
  kubectl -n databases create secret generic "pg-$tenant-app" \
    --type=kubernetes.io/basic-auth --from-literal=username=demo \
    --from-file=password="$STATE/passwords/$tenant" \
    --dry-run=client -o yaml | kubectl apply -f -
  cat <<YAML | kubectl apply -f -
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: pg16-$tenant
  namespace: databases
spec:
  instances: 1
  imageName: $PG_IMAGE
  storage:
    size: 1Gi
  resources:
    requests:
      cpu: 100m
      memory: 256Mi
    limits:
      memory: 512Mi
  postgresql:
    pg_hba:
      - hostnossl app demo all scram-sha-256
      - host all all all reject
  bootstrap:
    initdb:
      database: app
      owner: demo
      secret:
        name: pg-$tenant-app
      postInitApplicationSQL:
        - CREATE TABLE public.cluster_identity (name text PRIMARY KEY)
        - INSERT INTO public.cluster_identity VALUES ('pg-$tenant')
        - GRANT SELECT ON public.cluster_identity TO demo
YAML
done
"$ROOT/scripts/gateway-certs.sh"
kubectl apply -f "$ROOT/manifests/routing.yaml"
for tenant in a b; do
  kubectl -n databases wait --for=condition=Ready "cluster/pg16-$tenant" --timeout=600s
done
echo 'Ready: ./scripts/verify.sh'
