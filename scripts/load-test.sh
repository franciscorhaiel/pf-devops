#!/usr/bin/env bash
# Genera carga contra el endpoint /carga para disparar el HPA.
# Deja corriendo un watch del HPA en paralelo para capturar la evidencia.
set -euo pipefail

DURACION="${DURACION:-300}"
CONCURRENCIA="${CONCURRENCIA:-30}"

echo "Generando carga por ${DURACION}s con ${CONCURRENCIA} clientes..."
echo "Evidencia del escalado en: evidencias/hpa-escalado.log"
mkdir -p evidencias

kubectl -n pf-app port-forward svc/pf-cloud-api 8080:80 >/dev/null 2>&1 &
PF_PID=$!
trap 'kill $PF_PID 2>/dev/null || true; kill $(jobs -p) 2>/dev/null || true' EXIT
sleep 4

# Registra el estado del HPA cada 10 segundos
(
  echo "=== Escalado del HPA - $(date -u +%FT%TZ) ==="
  for _ in $(seq 1 $((DURACION / 10))); do
    printf '%s  ' "$(date -u +%T)"
    kubectl -n pf-app get hpa pf-cloud-api --no-headers
    sleep 10
  done
) | tee evidencias/hpa-escalado.log &

# Clientes concurrentes
for _ in $(seq 1 "$CONCURRENCIA"); do
  ( end=$((SECONDS + DURACION))
    while [ $SECONDS -lt $end ]; do
      curl -s "http://localhost:8080/carga?iteraciones=2000000" >/dev/null || true
    done ) &
done

wait
echo
echo "Estado final:"
kubectl -n pf-app get hpa,pods
kubectl -n pf-app describe hpa pf-cloud-api | tee -a evidencias/hpa-escalado.log
