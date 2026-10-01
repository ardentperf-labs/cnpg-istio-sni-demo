#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
kind delete cluster --name "$CLUSTER_NAME"
echo 'Demo cluster and its database volumes deleted. Local passwords and CA certificates remain in .state/.'
