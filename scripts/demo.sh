#!/usr/bin/env bash
# Runs the full demo against your local cluster and saves terminal output to
# evidence/*.txt  (paste/screenshot these into the README).
# Usage:  CLUSTER=minikube ./scripts/demo.sh     (or CLUSTER=kind, or CLUSTER=docker-desktop)
set -u
cd "$(dirname "$0")/.."
CLUSTER="${CLUSTER:-minikube}"
EV=evidence
mkdir -p "$EV"

run() { echo "\$ $*"; "$@" 2>&1; echo; }
log() { echo; echo "=== $* ==="; }

# ---------- 0. Build + load images ----------
log "Build images"
docker build -t inventory:1.0 inventory/
docker build -t inventory-client:1.0 client/
case "$CLUSTER" in
  minikube)       minikube image load inventory:1.0; minikube image load inventory-client:1.0 ;;
  kind)           kind load docker-image inventory:1.0 inventory-client:1.0 ;;
  docker-desktop) : ;;  # shares the local docker image store
esac

# ---------- 1. Deploy ----------
{
  log "1. Deploy"
  run kubectl apply -f k8s/
  run kubectl rollout status deployment/inventory --timeout=90s
  run kubectl rollout status deployment/client --timeout=90s
  run kubectl get pods -o wide
  run kubectl get svc inventory-service
  run kubectl get endpoints inventory-service
  sleep 6
  log "Client logs: requests reaching MORE THAN ONE replica (via Service name)"
  run kubectl logs deploy/client --tail=12
  log "Per-Pod server logs (both replicas receive requests)"
  for p in $(kubectl get pods -l app=inventory -o name); do
    echo "--- $p"; kubectl logs "$p" --tail=5
  done
} | tee "$EV/1-deploy.txt"

# ---------- 2. Readiness ----------
{
  log "2. Readiness test"
  BAD=$(kubectl get pods -l app=inventory -o jsonpath='{.items[0].metadata.name}')
  echo "Pod chosen to fail readiness: $BAD"; echo
  run kubectl exec "$BAD" -- touch /tmp/not-ready
  sleep 8
  run kubectl get pods -l app=inventory
  run kubectl get endpoints inventory-service
  log "Client logs now only show the READY pod"
  run kubectl logs deploy/client --tail=8
  log "Restore readiness"
  run kubectl exec "$BAD" -- rm /tmp/not-ready
  sleep 8
  run kubectl get pods -l app=inventory
  run kubectl get endpoints inventory-service
  sleep 5
  log "Client logs: both pods serving again"
  run kubectl logs deploy/client --tail=10
} | tee "$EV/2-readiness.txt"

# ---------- 3. Pod deletion ----------
{
  log "3. Pod failure and recovery"
  run kubectl get pods -l app=inventory
  VICTIM=$(kubectl get pods -l app=inventory -o jsonpath='{.items[0].metadata.name}')
  echo "Deleting pod: $VICTIM"; echo
  run kubectl delete pod "$VICTIM"
  sleep 3
  run kubectl get pods -l app=inventory
  run kubectl rollout status deployment/inventory --timeout=90s
  run kubectl get pods -l app=inventory
  run kubectl get svc inventory-service
  run kubectl get endpoints inventory-service
  sleep 5
  log "Client keeps working through the unchanged Service name"
  run kubectl logs deploy/client --tail=10
} | tee "$EV/3-pod-recovery.txt"

echo "Done. Evidence saved in $EV/. Take screenshots of these terminal outputs too if you like."
