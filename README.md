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
open command prompt and run:
cd [project_root_dir]
chmod +x prereuisites.sh
./prereuisites.sh 
make deploy


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
