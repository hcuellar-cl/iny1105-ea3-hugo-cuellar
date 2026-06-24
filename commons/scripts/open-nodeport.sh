#!/bin/bash
# ============================================================================
# open-nodeport.sh — Abre un puerto NodePort en el Security Group de los nodos
#                    EKS, para acceder al servicio desde el navegador.
#
# Los nodos EC2 del cluster tienen un Security Group que bloquea el tráfico
# entrante por defecto. Este script detecta ese SG y le agrega una regla de
# entrada para el puerto indicado (TCP, desde 0.0.0.0/0).
#
# USO:
#   bash commons/scripts/open-nodeport.sh <puerto>
#   bash commons/scripts/open-nodeport.sh 30093
# ============================================================================
set -uo pipefail

REGION="${AWS_REGION:-us-east-1}"
CLUSTER_NAME="${CLUSTER_NAME:-iny1105-ea3-cluster}"
PORT="${1:-}"

if [ -z "$PORT" ]; then
    echo "Uso: bash commons/scripts/open-nodeport.sh <puerto>"
    echo "Ejemplo: bash commons/scripts/open-nodeport.sh 30093"
    exit 1
fi

echo "=================================================="
echo " Abrir puerto NodePort $PORT en el SG de los nodos"
echo " Cluster: $CLUSTER_NAME | Región: $REGION"
echo "=================================================="

# ── Detectar el Security Group de los nodos del cluster ──────────────────
# EKS etiqueta las instancias de los nodos con tag:aws:eks:cluster-name.
# Tomamos una instancia del nodegroup y leemos su Security Group.
echo "[1/2] Detectando el Security Group de los nodos..."
SG_ID=$(aws ec2 describe-instances --region "$REGION" \
    --filters "Name=tag:aws:eks:cluster-name,Values=$CLUSTER_NAME" \
              "Name=instance-state-name,Values=running" \
    --query "Reservations[0].Instances[0].SecurityGroups[0].GroupId" \
    --output text 2>/dev/null)

if [ -z "$SG_ID" ] || [ "$SG_ID" = "None" ]; then
    echo "ERROR: No se encontró el Security Group de los nodos."
    echo "  Verifica que el cluster '$CLUSTER_NAME' tenga nodos en ejecución:"
    echo "    kubectl get nodes"
    exit 1
fi
echo "  Security Group de los nodos: $SG_ID"

# ── Agregar la regla de entrada (idempotente) ────────────────────────────
echo "[2/2] Agregando regla de entrada: TCP $PORT desde 0.0.0.0/0..."
OUT=$(aws ec2 authorize-security-group-ingress --region "$REGION" \
    --group-id "$SG_ID" \
    --protocol tcp --port "$PORT" --cidr 0.0.0.0/0 2>&1)

if echo "$OUT" | grep -q "InvalidPermission.Duplicate"; then
    echo "  La regla ya existía — el puerto $PORT ya está abierto."
elif echo "$OUT" | grep -qi "error"; then
    echo "ERROR al agregar la regla:"
    echo "$OUT" | sed 's/^/    /'
    exit 1
else
    echo "  Regla agregada correctamente."
fi

echo ""
echo "=================================================="
echo " Puerto $PORT abierto en el SG $SG_ID."
echo "=================================================="
# Mostrar la IP pública de un nodo para acceder
NODE_IP=$(aws ec2 describe-instances --region "$REGION" \
    --filters "Name=tag:aws:eks:cluster-name,Values=$CLUSTER_NAME" \
              "Name=instance-state-name,Values=running" \
    --query "Reservations[0].Instances[0].PublicIpAddress" \
    --output text 2>/dev/null)
if [ -n "$NODE_IP" ] && [ "$NODE_IP" != "None" ]; then
    echo " Accede al servicio en:  http://$NODE_IP:$PORT"
fi
