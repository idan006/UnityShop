# UnityExpress – Cloud-Native Event-Driven Demo Platform

A complete, production-style microservices project showcasing Kubernetes, Helm, CI/CD patterns, Kafka event streaming, MongoDB persistence, autoscaling with KEDA, NGINX gateway routing, and Docker-based local development.
UnityExpress is intentionally built as a **Senior DevOps Engineer portfolio project**, demonstrating modern cloud-native patterns end to end.

---

## Overview

UnityExpress includes the following services:

- **API Service (Node.js)** - REST API with comprehensive metrics
- **Web UI (NGINX + Static Frontend)** - User interface
- **Kafka + Zookeeper** - Event streaming platform
- **MongoDB StatefulSet** - Persistent data storage
- **KEDA autoscaling** - Event-driven autoscaling based on Kafka consumer lag
- **Prometheus metrics** - 30+ custom business and technical metrics
- **Helm-based deployment** - Infrastructure as Code
- **Makefile automation** - Simple deployment commands
- **Minikube + Docker Desktop** - Local development environment

This project is fully reproducible and can run on **any computer** capable of running Docker Desktop.

---

# Architecture

### High-Level System Architecture

```mermaid
graph TB
    Client[Client Browser]
    
    subgraph "Kubernetes Cluster - Namespace: unityexpress"
        Gateway[NGINX Gateway<br/>:80 NodePort]
        API[API Service<br/>Node.js :3000]
        Web[Web UI<br/>Static Files]
        Kafka[Kafka Broker<br/>:9092]
        Zookeeper[Zookeeper<br/>:2181]
        MongoDB[(MongoDB<br/>StatefulSet)]
        KEDA[KEDA Scaler<br/>Autoscaling]
        Prometheus[Prometheus<br/>Metrics]
    end
    
    Client -->|HTTP| Gateway
    Gateway -->|/api/*| API
    Gateway -->|/*| Web
    API -->|Publish Events| Kafka
    API -->|Read/Write| MongoDB
    API -->|Expose Metrics| Prometheus
    Kafka -->|Consumer Lag| KEDA
    KEDA -->|Scale Pods| API
    Zookeeper -.->|Coordination| Kafka
    
    style Client fill:#e1f5ff
    style Gateway fill:#fff3e0
    style API fill:#e8f5e9
    style Kafka fill:#f3e5f5
    style MongoDB fill:#fce4ec
    style KEDA fill:#fff9c4
    style Prometheus fill:#ffebee
```

### Request Flow

```mermaid
sequenceDiagram
    participant Client
    participant Gateway as NGINX Gateway
    participant API as API Service
    participant Kafka
    participant MongoDB
    participant Metrics as Prometheus
    
    Client->>Gateway: POST /api/purchases
    Gateway->>API: Forward request
    
    API->>API: Validate input (Joi)
    
    alt Valid Input
        API->>MongoDB: Save purchase
        MongoDB-->>API: Confirm saved
        API->>Kafka: Publish event
        API->>Metrics: Update metrics
        API-->>Gateway: 201 Created
        Gateway-->>Client: Success response
    else Invalid Input
        API->>Metrics: Track validation error
        API-->>Gateway: 400 Bad Request
        Gateway-->>Client: Error response
    end
```

### Data Flow Architecture

```mermaid
flowchart LR
    subgraph Input
        A[Client Request]
    end
    
    subgraph Processing
        B[Input Validation]
        C[Business Logic]
        D[Data Persistence]
    end
    
    subgraph Output
        E[Kafka Event]
        F[HTTP Response]
        G[Metrics Update]
    end
    
    A --> B
    B -->|Valid| C
    B -->|Invalid| F
    C --> D
    D --> E
    D --> F
    C --> G
    
    style B fill:#fff3e0
    style C fill:#e8f5e9
    style D fill:#fce4ec
    style E fill:#f3e5f5
    style F fill:#e1f5ff
    style G fill:#ffebee
```

### Deployment Architecture

```mermaid
graph TB
    subgraph "CI/CD Pipeline"
        GH[GitHub Actions]
        Build[Build & Test]
        Push[Push to GHCR]
    end
    
    subgraph "Minikube Cluster"
        subgraph "unityexpress namespace"
            Deploy[Helm Deployment]
            
            subgraph "Services"
                API