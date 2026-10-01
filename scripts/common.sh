#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
STATE="$ROOT/.state"
export KUBECONFIG="$STATE/kubeconfig"
CLUSTER_NAME=cnpg-sni-demo
ISTIO_VERSION=1.30.5
CNPG_CHART_VERSION=0.29.1
NODE_IMAGE=kindest/node:v1.35.0
PG_IMAGE=ghcr.io/cloudnative-pg/postgresql:16.13-standard-bookworm
CLIENT_IMAGE=postgres:17.9-bookworm
