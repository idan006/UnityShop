#!/usr/bin/env bash
set -e

echo "[*] Using Minikube Docker daemon"
eval "$(minikube docker-env)"

echo "[*] Building UnityExpress API image"
docker build -t unityexpress-api:local ./api-server

echo "[*] Building UnityExpress Web image"
docker build -t unityexpress-web:local ./web-server

echo "[*] Images built:"
docker images | grep unityexpress || true
