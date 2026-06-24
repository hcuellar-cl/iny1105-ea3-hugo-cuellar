#!/bin/bash
# ============================================================================
# 06-stress-test.sh — Generador de carga HTTP para el HPA de Redmine.
#
# Levanta Pods temporales de busybox que envían peticiones continuas al servicio
# interno de Redmine para forzar el consumo de CPU y activar el auto-escalado.
#
# Uso:
#   bash manifests/06-stress-test.sh           # Iniciar la prueba de carga
#   bash manifests/06-stress-test.sh stop      # Detener la prueba de carga
# ============================================================================
set -uo pipefail
NS="pmotrack"
GENERATORS=3        # Cantidad de Pods generadores de carga

if [ "${1:-}" = "stop" ]; then
    echo "Deteniendo generadores de carga..."
    kubectl delete pod -n "$NS" -l role=load-generator --ignore-not-found
    echo "Listo. El HPA reducirá las réplicas en unos minutos (cooldown ~5 min)."
    exit 0
fi

echo "=================================================="
echo " PRUEBA DE CARGA — Autoscaling de Redmine (HPA)"
echo "=================================================="
echo "Lanzando $GENERATORS Pods para bombardear http://redmine con peticiones..."

for i in $(seq 1 "$GENERATORS"); do
    cat <<EOF | kubectl apply -f - >/dev/null
apiVersion: v1
kind: Pod
metadata:
  name: load-generator-$i
  namespace: $NS
  labels:
    role: load-generator
spec:
  restartPolicy: Never
  containers:
  - name: load
    image: public.ecr.aws/docker/library/busybox:latest
    command: ["sh","-c","while true; do wget -q -O /dev/null http://redmine; done"]
EOF
    echo "  load-generator-$i lanzado exitosamente"
done

echo ""
echo "=================================================="
echo " Carga iniciada. Monitorea el escalado ejecutando:"
echo "=================================================="
echo "   kubectl get hpa -n $NS -w"
echo "   kubectl get pods -n $NS -l app=redmine -w"
echo ""
echo " En 1-3 minutos el HPA debería crear nuevas réplicas (hasta un máx de 5)."
echo " Para detener el stress test ejecuta:"
echo "   bash manifests/06-stress-test.sh stop"
echo "=================================================="
