#!/bin/bash
# ============================================================================
# 08-stress-test.sh — Genera carga sobre WordPress para ver el autoscaling.
#
# Lanza varios Pods que hacen peticiones HTTP continuas al Service de WordPress.
# Esto sube el uso de CPU y dispara el HorizontalPodAutoscaler (HPA), que
# escala el Deployment de 1 hasta 5 réplicas.
#
# USO:
#   bash act33/manifests/08-stress-test.sh           # inicia la carga
#   bash act33/manifests/08-stress-test.sh stop      # detiene la carga
#
# MIENTRAS CORRE, observa el escalado en OTRA terminal con:
#   kubectl get hpa -n wordpress -w
#   kubectl get pods -n wordpress -l app=wordpress -w
# ============================================================================
set -uo pipefail
NS="wordpress"
GENERATORS=3        # cuántos Pods generadores de carga lanzar

if [ "${1:-}" = "stop" ]; then
    echo "Deteniendo generadores de carga..."
    kubectl delete pod -n "$NS" -l role=load-generator --ignore-not-found
    echo "Listo. El HPA reducirá las réplicas en unos minutos (cooldown ~5 min)."
    exit 0
fi

echo "=================================================="
echo " PRUEBA DE CARGA — Autoscaling de WordPress"
echo "=================================================="
echo "Lanzando $GENERATORS Pods que bombardean http://wordpress con peticiones..."

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
    # Bucle infinito de peticiones HTTP al Service interno de WordPress
    command: ["sh","-c","while true; do wget -q -O /dev/null http://wordpress; done"]
EOF
    echo "  load-generator-$i lanzado"
done

echo ""
echo "=================================================="
echo " Carga iniciada. Observa el autoscaling en vivo:"
echo "=================================================="
echo "   kubectl get hpa -n $NS -w"
echo "   kubectl get pods -n $NS -l app=wordpress"
echo ""
echo " En 1-3 min el HPA debería subir las réplicas de WordPress (hasta 5)."
echo " Para DETENER la carga:"
echo "   bash act33/manifests/08-stress-test.sh stop"
echo "=================================================="
