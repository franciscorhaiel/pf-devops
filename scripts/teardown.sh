#!/usr/bin/env bash
# FinOps: destruir todo cuando no se usa. Un cluster kind olvidado consume
# RAM y CPU de la maquina; en cloud consumiria dinero.
set -euo pipefail
CLUSTER="${CLUSTER:-pf-cloud}"

echo "Destruyendo el cluster $CLUSTER..."
kind delete cluster --name "$CLUSTER"
docker image prune -f
echo "Listo. Recursos liberados."
