#!/bin/bash
# delete-cluster.sh — Elimina el cluster EKS para liberar presupuesto del Learner Lab
# Uso: bash commons/scripts/delete-cluster.sh
#
# IMPORTANTE: Ejecuta este script al terminar cada clase.
# El cluster EKS genera costo continuo aunque no lo estés usando.

CLUSTER_NAME="iny1105-ea3-cluster"
REGION="us-east-1"

echo "=================================================="
echo " ELIMINAR CLUSTER EKS: $CLUSTER_NAME"
echo " Esta operación liberará los recursos de AWS."
echo "=================================================="
echo ""

read -p "¿Confirmas que quieres eliminar el cluster? (escribe 'eliminar' para confirmar): " CONFIRM
if [ "$CONFIRM" != "eliminar" ]; then
    echo "Operación cancelada."
    exit 0
fi
echo ""

# Verificar que el cluster existe
echo "[1/3] Verificando cluster..."
STATUS=$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$REGION" \
    --query "cluster.status" --output text 2>/dev/null || echo "NOT_FOUND")
if [ "$STATUS" == "NOT_FOUND" ]; then
    echo "El cluster $CLUSTER_NAME no existe o ya fue eliminado."
    exit 0
fi
echo "Estado actual: $STATUS"
echo ""

# Eliminar TODOS los nodegroups (no solo standard-workers)
echo "[2/3] Eliminando todos los Node Groups..."
NODEGROUPS=$(aws eks list-nodegroups \
    --cluster-name "$CLUSTER_NAME" \
    --region "$REGION" \
    --query "nodegroups[]" \
    --output text 2>/dev/null)

if [ -n "$NODEGROUPS" ]; then
    for NG in $NODEGROUPS; do
        echo "  Eliminando Node Group: $NG"
        aws eks delete-nodegroup \
            --cluster-name "$CLUSTER_NAME" \
            --nodegroup-name "$NG" \
            --region "$REGION" \
            --output table 2>/dev/null || echo "  Node Group $NG no encontrado o ya eliminado."
    done

    echo "  Esperando a que todos los Node Groups se eliminen (3-5 min)..."
    ELAPSED=0
    TIMEOUT=600
    while true; do
        REMAINING=$(aws eks list-nodegroups \
            --cluster-name "$CLUSTER_NAME" \
            --region "$REGION" \
            --query "length(nodegroups)" \
            --output text 2>/dev/null || echo "0")
        if [ "$REMAINING" == "0" ]; then
            echo "✓ Todos los Node Groups eliminados"
            break
        fi
        if [ "$ELAPSED" -ge "$TIMEOUT" ]; then
            echo "TIMEOUT: Los Node Groups tardaron más de 10 minutos en eliminarse."
            echo "Verifica en la consola AWS → EKS → $CLUSTER_NAME → Compute"
            exit 1
        fi
        echo "  Node Groups restantes: $REMAINING — esperando... ($ELAPSED s)"
        sleep 30
        ELAPSED=$((ELAPSED + 30))
    done
else
    echo "  No hay Node Groups activos."
fi
echo ""

# Eliminar el cluster
echo "[3/3] Eliminando cluster: $CLUSTER_NAME..."
aws eks delete-cluster \
    --name "$CLUSTER_NAME" \
    --region "$REGION" \
    --output table

if [ $? -ne 0 ]; then
    echo "ERROR: No se pudo eliminar el cluster. Verifica en la consola AWS."
    exit 1
fi

echo "Esperando a que el cluster se elimine..."
ELAPSED=0
TIMEOUT=900
while true; do
    STATUS=$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$REGION" \
        --query "cluster.status" --output text 2>/dev/null || echo "DELETED")
    if [ "$STATUS" == "DELETED" ] || [ -z "$STATUS" ]; then
        echo "✓ Cluster eliminado"
        break
    fi
    if [ "$ELAPSED" -ge "$TIMEOUT" ]; then
        echo "TIMEOUT: El cluster tardó más de 15 minutos en eliminarse."
        echo "Verifica en la consola AWS → EKS → Clusters"
        exit 1
    fi
    echo "  Estado: $STATUS — esperando... ($ELAPSED s)"
    sleep 30
    ELAPSED=$((ELAPSED + 30))
done
echo ""

echo "=================================================="
echo " Cluster $CLUSTER_NAME eliminado correctamente."
echo " Los recursos EC2 asociados también fueron liberados."
echo "=================================================="
echo ""

# ── Recordatorio: secreto de Act 3.3 en AWS Secrets Manager ──────────────
# El secreto persiste entre sesiones (no se borra con el cluster). Puedes
# conservarlo para la próxima clase o eliminarlo si ya no lo necesitas.
SM_SECRET="iny1105/wordpress/mysql"
if aws secretsmanager describe-secret --region "$REGION" \
       --secret-id "$SM_SECRET" >/dev/null 2>&1; then
    echo "NOTA (Act 3.3): el secreto '$SM_SECRET' sigue en AWS Secrets Manager."
    echo "  Para eliminarlo (opcional):"
    echo "    aws secretsmanager delete-secret --region $REGION \\"
    echo "      --secret-id $SM_SECRET --force-delete-without-recovery"
fi
