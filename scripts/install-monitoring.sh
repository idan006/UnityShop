#!/usr/bin/env bash
set -e

echo "[*] Installing kube-prometheus-stack and prometheus-adapter into 'monitoring' namespace"

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace

helm upgrade --install prometheus-adapter prometheus-community/prometheus-adapter \
  -n monitoring -f monitoring/prometheus-adapter-values.yaml
