#!/usr/bin/env bash
# Local platform: kind cluster + Kyverno policies + Argo CD syncing this repo.
#   ./scripts/bootstrap-kind.sh            then: kubectl -n argocd port-forward svc/argocd-server 8080:443
set -euo pipefail
KYVERNO_VERSION=${KYVERNO_VERSION:-v1.20.0}
CLUSTER=${CLUSTER:-devsecops}

kind get clusters | grep -qx "$CLUSTER" || kind create cluster --name "$CLUSTER" --wait 120s

echo "--> Kyverno $KYVERNO_VERSION"
kubectl apply --server-side -f "https://github.com/kyverno/kyverno/releases/download/${KYVERNO_VERSION}/install.yaml"
kubectl -n kyverno rollout status deploy/kyverno-admission-controller --timeout=300s
for _ in $(seq 1 24); do kubectl apply -f policies/kyverno/ && break; sleep 5; done   # webhook may lag the rollout

echo "--> Argo CD"
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply --server-side -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl -n argocd rollout status deploy/argocd-server --timeout=300s
kubectl apply -f gitops/argocd/root.yaml

echo
echo "Argo CD admin password:"
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
echo "UI: kubectl -n argocd port-forward svc/argocd-server 8080:443  ->  https://localhost:8080"
