# UnityExpress – Cloud-Native Event-Driven Demo Platform

A complete, production-style microservices project showcasing Kubernetes, Helm, CI/CD patterns, Kafka event streaming, MongoDB persistence, autoscaling with KEDA, NGINX gateway routing, and Docker-based local development.

UnityExpress is intentionally built as a **Senior DevOps Engineer portfolio project**, demonstrating modern cloud-native patterns end to end.

---

## Overview

UnityExpress includes the following services:

- **API Service (Node.js)**
- **Web UI (NGINX + Static Frontend)**
- **Kafka + Zookeeper**
- **MongoDB StatefulSet**
- **KEDA autoscaling based on Kafka consumer lag**
- **Prometheus Operator CRDs for observability**
- **Helm-based deployment**
- **Makefile automation**
- **Minikube + Docker Desktop local environment**

This project is fully reproducible and can run on **any computer** capable of running Docker Desktop.

---

# Architecture

### High-Level System Flow

```
Client Browser
      │
      ▼
NGINX Gateway (NodePort)
 • Routes /api → API service
 • Serves UI
      │
      ▼
API Server (Node.js)
 • REST endpoints
 • Publishes Kafka events
 • Writes to MongoDB
      │
      ▼
Kafka Broker
 • Stores purchase events
 • KEDA monitors lag → autoscaling
      │
      ▼
MongoDB StatefulSet
 • Persistent purchase history
```

---

# Project Structure

```
UnityExpress/
├── api-server/
│   ├── src/
│   ├── Dockerfile
│   └── package.json
│
├── web-server/
│   ├── html/
│   ├── nginx.conf
│   └── Dockerfile
│
├── charts/
│   └── unityexpress/   # Helm chart (single, declarative)
│
├── scripts/
│   ├── smoke_test.py
│   ├── load-test.py
│   └── verify-health.py
│
├── makefile
└── README.md
```

---

# Prerequisites

### Required tools

| Tool          | Purpose                       |
|---------------|-------------------------------|
| Docker Desktop | Build + local registry       |
| Minikube (Docker driver) | Local Kubernetes |
| kubectl       | Cluster command-line          |
| Helm 3        | Deployment engine             |
| Python 3      | For automated smoke tests     |

### Start the cluster

```
minikube start --driver=docker --cpus=4 --memory=8192
```

---

# Deployment Workflow

### Step 1 — Build images

```
make build
```

### Step 2 — Load them into Minikube

```
make load
```

### Step 3 — Deploy all components

```
make deploy
```

### Step 4 — Open the UI

```
make open
```

Or:

```
minikube service unityexpress-gateway -n unityexpress
```

---

# Features

### Kubernetes-native design  
100% declarative, infrastructure-as-code using Helm.

### Event-driven autoscaling  
KEDA automatically scales API replicas when Kafka lag increases.

### Local reproducibility  
Works on **any** machine running Docker + Minikube.

### Secure architecture & multi-service pattern  
Gateway, API, Kafka, MongoDB, KEDA — all isolated and reproducible.

---

# Recommended Helm Improvements

## 1. Add CPU & memory requests/limits

```yaml
resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 500m
    memory: 512Mi
```

## 2. Add readiness/liveness probes

```yaml
livenessProbe:
  httpGet:
    path: /health
    port: 3000
  initialDelaySeconds: 30

readinessProbe:
  httpGet:
    path: /ready
    port: 3000
  initialDelaySeconds: 5
```

## 3. Remove hardcoded secrets & credentials  
Use Kubernetes Secrets or external managers (Vault, SOPS, SealedSecrets).

## 4. Add security contexts

```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 1000
  capabilities:
    drop: ["ALL"]
```

## 5. Increase replicas for scalability and HA

```
replicas: 3
```

## 6. Improve Kafka for production  
Use multi-broker, persistent storage, external access, TLS, SASL, etc.

---

# Testing

### Smoke Test

```
make smoke
```

### General Status

```
make status
```

### Logs

```
make logs
```

---

# Summary

UnityExpress is a full cloud-native microservice environment designed to demonstrate:

- DevOps automation
- Event-driven design
- CI/CD-oriented workflows
- Kubernetes scaling with KEDA
- Observability best practices
- Helm-driven configuration
- Containerized microservices architecture

It is a powerful, realistic project that reflects the skillset and design thinking of a **Senior DevOps Engineer**.

---

If you want, I can also generate:

- GitHub Actions CI/CD pipeline
- High-level system diagram in PNG/SVG
- CONTRIBUTING.md
- SECURITY.md
- Architecture Decision Records (ADRs)
- Production-grade Helm values schema

Just tell me. 🚀
