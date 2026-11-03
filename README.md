# Module 6: Service Discovery, Readiness & Recovery on Kubernetes

A small Inventory service (2 replicas) and a client that calls it **by Kubernetes Service name**, used to demonstrate service discovery, readiness probes, and Pod replacement.

Works on minikube, kind, or Docker Desktop Kubernetes.

## Repository layout

```
inventory/            Inventory app (Python stdlib HTTP server) + Dockerfile
client/               Client that calls http://inventory-service/items in a loop + Dockerfile
k8s/                  Deployment + Service manifests
scripts/demo.sh       Runs the whole demo and saves output to evidence/
evidence/             Terminal output captured by demo.sh
```

## Architecture

```
                 +--------------------------------------+
                 |            Kubernetes cluster         |
                 |                                      |
 +-----------+   |   DNS name        +-----------------+ |   +----------------------+
 |  client   |---|-> inventory-      | Service         |-|-->| inventory Pod #1     |
 | (1 Pod)   |   |   service:80      | inventory-      | |   | readiness: /ready    |
 +-----------+   |                   | service         | |   +----------------------+
                 |                   | (stable name +  | |   +----------------------+
                 |                   |  ClusterIP)     |-|-->| inventory Pod #2     |
                 |                   +-----------------+ |   | readiness: /ready    |
                 |   Only Pods that pass readiness        |   +----------------------+
                 |   are listed as Service endpoints      |
                 +--------------------------------------+
```

The Service selects Pods with label `app=inventory`. The client never uses Pod IPs; it uses the DNS name `inventory-service`.

## How it works

- `inventory/app.py` returns `{"pod": <pod name>, "items": [...]}` from `/items`, so every response shows which replica answered.
- `/ready` returns 200 normally and **503 if the file `/tmp/not-ready` exists**. This is how we make one Pod fail readiness without killing it.
- `/health` is a liveness endpoint that always returns 200.
- The Deployment's `readinessProbe` hits `/ready`; the Service only routes to Pods that are Ready.

## Deploying the application

Prerequisites: Docker, kubectl, and one of minikube / kind / Docker Desktop Kubernetes (running).

```bash
# 1. Build images
docker build -t inventory:1.0 inventory/
docker build -t inventory-client:1.0 client/

# 2. Make the images available to your cluster (pick ONE)
minikube image load inventory:1.0 && minikube image load inventory-client:1.0     # minikube
kind load docker-image inventory:1.0 inventory-client:1.0                          # kind
# Docker Desktop Kubernetes: nothing to do, it shares the local image store

# 3. Deploy
kubectl apply -f k8s/
kubectl rollout status deployment/inventory
kubectl get pods -o wide
kubectl get svc inventory-service

# 4. Watch the client talk to the Service name
kubectl logs -f deploy/client
```

To run every demo step below automatically and save the output:

```bash
CLUSTER=minikube ./scripts/demo.sh      # or kind / docker-desktop
```

## Demonstrations

### 1. Deployment, Service, and load across replicas

Commands:

```bash
kubectl get pods -o wide
kubectl get endpoints inventory-service
kubectl logs deploy/client --tail=12
```

What to look for: both Pods `Running` and `1/1 Ready`; the client log lines alternate between the two different `pod=` names, proving requests reach more than one replica through the Service name.

**Evidence:** see [`evidence/1-deploy.txt`](evidence/1-deploy.txt)

<!-- Paste screenshot here, e.g. ![deploy](evidence/1-deploy.png) -->

### 2. Readiness failure and recovery

Make one Pod fail readiness (it stays running):

```bash
kubectl exec <inventory-pod> -- touch /tmp/not-ready
kubectl get pods -l app=inventory          # one shows 0/1 READY but STATUS Running
kubectl get endpoints inventory-service    # only the ready Pod's IP remains
kubectl logs deploy/client --tail=8        # all responses come from the ready Pod
```

Restore it:

```bash
kubectl exec <inventory-pod> -- rm /tmp/not-ready
kubectl get pods -l app=inventory          # back to 1/1 READY
kubectl logs deploy/client --tail=10       # both Pods serve again
```

Observed: the unready Pod is **still running**, it is **removed from the Service endpoints** and stops receiving normal traffic, and the **other Pod keeps serving**. After restoring, it rejoins the endpoints.

**Evidence:** see [`evidence/2-readiness.txt`](evidence/2-readiness.txt)

<!-- Paste screenshot here -->

### 3. Pod deletion and replacement

```bash
kubectl get pods -l app=inventory
kubectl delete pod <inventory-pod>
kubectl get pods -l app=inventory          # a new Pod with a DIFFERENT name appears
kubectl get svc inventory-service          # same Service name and ClusterIP
kubectl logs deploy/client --tail=10       # client keeps working
```

Observed: the Deployment's ReplicaSet creates a replacement Pod with a new name/identity, the Service name (`inventory-service`) and ClusterIP are unchanged, and the client continues communicating through the Service without any configuration change.

**Evidence:** see [`evidence/3-pod-recovery.txt`](evidence/3-pod-recovery.txt)

<!-- Paste screenshot here -->

## Reflection

<!-- Replace/edit with your own words before submitting. 3-5 sentences. -->

Pods are temporary: when one fails, is rescheduled, or is replaced, it gets a new name and a new IP address, so any client that hard-coded a Pod address would break. A Kubernetes Service gives the group of Pods one stable DNS name and virtual IP, and it automatically keeps its list of endpoints up to date based on labels and readiness. In this lab the client always called `inventory-service`, yet traffic moved away from the unready Pod and onto the replacement Pod without the client changing at all. This decouples clients from the lifecycle of individual Pods, which is what makes failures, rolling updates, and scaling invisible to callers.

## Cleanup

```bash
kubectl delete -f k8s/
```
