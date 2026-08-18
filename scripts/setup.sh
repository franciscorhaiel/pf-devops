#!/usr/bin/env bash
# Levanta el entorno completo de cero: cluster, ingress, metrics-server,
# app y monitoreo. Idempotente: se puede correr varias veces.
set -euo pipefail

CLUSTER="${CLUSTER:-pf-cloud}"
TAG="${TAG:-1.0.0}"
IMAGEN="pf-cloud-api:${TAG}"

info() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }

for bin in docker kind kubectl helm kustomize; do
  command -v "$bin" >/dev/null || { echo "Falta $bin en el PATH"; exit 1; }
done

info "1/7 Cluster kind"
if kind get clusters 2>/dev/null | grep -qx "$CLUSTER"; then
  echo "El cluster $CLUSTER ya existe, se reutiliza."
else
  kind create cluster --config scripts/kind-config.yaml
fi

info "2/7 ingress-nginx"
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller --timeout=300s

info "3/7 metrics-server (requisito del HPA)"
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
kubectl patch -n kube-system deployment metrics-server --type=json \
  -p '[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]' || true
kubectl wait -n kube-system --for=condition=available deployment/metrics-server --timeout=300s

info "4/7 Build de la imagen y carga en kind"
docker build --target runtime -t "$IMAGEN" .
kind load docker-image "$IMAGEN" --name "$CLUSTER"

info "5/7 Desplegar la aplicacion"
( cd k8s && kustomize edit set image "ghcr.io/franciscorhaiel/pf-cloud-api=$IMAGEN" )
kubectl apply -k k8s/
kubectl -n pf-app rollout status deployment/pf-cloud-api --timeout=300s

info "6/7 Monitoreo (Prometheus + Grafana)"
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
kubectl -n monitoring create secret generic grafana-admin \
  --from-literal=usuario=admin \
  --from-literal=password="${GRAFANA_PASSWORD:-$(openssl rand -base64 16)}" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n monitoring create configmap grafana-dashboard-pf-cloud \
  --from-file=monitoring/grafana-dashboard.json \
  --dry-run=client -o yaml | kubectl apply -f -
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null
helm repo update >/dev/null
helm upgrade --install monitoreo prometheus-community/kube-prometheus-stack \
  --namespace monitoring --version 66.2.1 \
  -f monitoring/values-prometheus.yaml --timeout 15m --wait
kubectl apply -f monitoring/servicemonitor.yaml
kubectl apply -f monitoring/alertas.yaml

info "7/7 Estado final"
kubectl -n pf-app get pods,svc,ingress,hpa

cat <<TXT

Listo. Accesos:

  App        agregar "127.0.0.1 pf-cloud.local" a /etc/hosts
             curl http://pf-cloud.local/healthz

  Grafana    kubectl -n monitoring port-forward svc/monitoreo-grafana 3000:80
             http://localhost:3000  (usuario admin)
             password: kubectl -n monitoring get secret grafana-admin -o jsonpath='{.data.password}' | base64 -d

  Prometheus kubectl -n monitoring port-forward svc/monitoreo-kube-prometheus-prometheus 9090:9090

Para probar el auto-escalado:  ./scripts/load-test.sh
TXT
