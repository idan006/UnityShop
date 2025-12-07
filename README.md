# Welcome to UnityExpress Shop By Idan Agam!
A Full-Stack Kubernetes Demo App with Kafka, MongoDB, Node.js API, React UI, and NGINX Gateway

UnityExpress is a fully containerized microservice application designed for DevOps, SRE, and cloud-native learning environments.
This project demonstrates how to design, package, and deploy a multi-service application behind a unified gateway using best practices for cloud-native development.

The stack includes:

* **React Web Frontend**
* **Node.js API**
* **Kafka + Zookeeper**
* **MongoDB**
* **NGINX Gateway (single entrypoint for UI + API)**
* **Helm chart for automated deployment**
* **Kubernetes-ready, Minikube-friendly**

# Delpoy:
1. create new folder and run: git clone https://github.com/idan006/UnityShop.git

2. open command prompt and run:

3. cd [project_root_dir]

4. chmod +x ./scripts/prerequisites.sh

5. Run: ./scripts/prereuisites.sh 

6. run: make deploy


# Additional tools you can use:
make deploy
make destroy
make restart
make logs
make smoke
make health
make load-test

# Autoscaling methuds:
A. CPU Utilization (If the API pods consistently use more than 70% CPU, Kubernetes increases replicas)
B. Memory Utilization (When memory consumption goes above 80%, the HPA triggers new pod replicas)
C. Custom Application Latency Metric (If average request latency across pod exceeds 0.3 seconds, scale out)

# API autoscaling is hybrid, reacting to:
Infrastructure pressure
Resource saturation
Real user experience signals (latency)

# Autoscaling Flow Summary
1. Traffic Spike → Increased API latency / CPU / Memory
↓
2. HPA triggers scale-out
↓
3. New API pods start pulling messages and producing Kafka messages
↓
4. Kafka remains stable due to internal balancing
↓
5. UI and WebSocket subscribers remain real-time and responsive

NOTE: we can use Vertical autoscaling for lower costs

[![UnityExpress](https://img.shields.io/badge/UnityExpress-Cloud%20Native-blue.svg)](#)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](#)
[![Status](https://img.shields.io/badge/Status-Active-success.svg)](#)




# Scripts checklist



# Phase 2 additions:
1. Adding load tool to tests load and fail-over
2. improving CI\CI ETE tests (to make it "one click  like we spoke in our meeting")
3. Adding Unit tests
4. addind static code analysis as a part of the ci 



## CI\CD:

# API UNIT TESTS:
Test Coverage List

1. Creates a purchase successfully when valid input is provided.

2. Rejects purchase creation when required fields are missing.

3. Rejects purchase creation when price is invalid or negative.

4. Rejects purchase creation when timestamp is invalid.

5. Persists the purchase in MongoDB after successful creation.

6. Returns all existing purchases through GET /api/purchases.

7. Returns purchases sorted by newest timestamp first.

8. Returns an empty array when no purchases exist.

9. Calls Kafka publish function on successful purchase creation.

10. Handles Kafka publish failures without crashing the API.

11. Returns HTTP 500 when MongoDB save operation fails.

12. Ensures no Kafka publish occurs when DB save fails.

