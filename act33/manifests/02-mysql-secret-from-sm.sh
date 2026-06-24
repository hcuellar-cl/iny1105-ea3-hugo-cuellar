#!/bin/bash
# ============================================================================
# 02-mysql-secret-from-sm.sh
#
# Gestión de credenciales con AWS Secrets Manager (patrón profesional).
#
# En vez de versionar las contraseñas en un YAML (mala práctica), las
# guardamos en AWS Secrets Manager y, desde ahí, generamos el Secret de
# Kubernetes que consumen MySQL y WordPress.
#
# Flujo:
#   1) Crear el secreto en Secrets Manager (una sola vez).
#   2) Leerlo con la CLI y crear el Secret de Kubernetes (cada vez que
#      recrees el cluster, ya que los Secrets de K8s no persisten).
#
# USO:
#   bash act33/manifests/02-mysql-secret-from-sm.sh
#
# REQUISITOS: AWS CLI con credenciales del Learner Lab, jq, kubectl, y el
#             namespace 'wordpress' ya creado (01-namespace.yaml aplicado).
# ============================================================================
set -euo pipefail

REGION="${AWS_REGION:-us-east-1}"
SECRET_NAME="iny1105/wordpress/mysql"
NAMESPACE="wordpress"

echo "=================================================="
echo " Secrets Manager -> Secret de Kubernetes"
echo " Secreto: $SECRET_NAME | Región: $REGION"
echo "=================================================="

# ── 1. Crear el secreto en Secrets Manager (si no existe) ────────────────
EXISTE=$(aws secretsmanager describe-secret --region "$REGION" \
    --secret-id "$SECRET_NAME" --query "ARN" --output text 2>/dev/null || true)

if [ -z "$EXISTE" ] || [ "$EXISTE" = "None" ]; then
    echo "[1/2] Creando el secreto en AWS Secrets Manager..."
    aws secretsmanager create-secret --region "$REGION" \
        --name "$SECRET_NAME" \
        --description "Credenciales MySQL para WordPress (INY1105 Act 3.3)" \
        --secret-string '{
          "MYSQL_ROOT_PASSWORD": "rootpass123",
          "MYSQL_DATABASE": "wordpress",
          "MYSQL_USER": "wpuser",
          "MYSQL_PASSWORD": "wppass123"
        }' \
        --query "ARN" --output text
    echo "  Secreto creado."
else
    echo "[1/2] El secreto ya existe en Secrets Manager — se reutiliza."
fi

# ── 2. Leer el secreto y crear el Secret de Kubernetes ───────────────────
echo "[2/2] Leyendo el secreto y creando el Secret de Kubernetes..."

SECRET_JSON=$(aws secretsmanager get-secret-value --region "$REGION" \
    --secret-id "$SECRET_NAME" --query "SecretString" --output text)

ROOT_PASS=$(echo "$SECRET_JSON" | jq -r '.MYSQL_ROOT_PASSWORD')
DB_NAME=$(echo "$SECRET_JSON"   | jq -r '.MYSQL_DATABASE')
DB_USER=$(echo "$SECRET_JSON"   | jq -r '.MYSQL_USER')
DB_PASS=$(echo "$SECRET_JSON"   | jq -r '.MYSQL_PASSWORD')

# Crear (o recrear) el Secret de Kubernetes a partir de los valores leídos.
# --dry-run + apply lo hace idempotente (no falla si ya existe).
kubectl create secret generic mysql-secret \
    --namespace "$NAMESPACE" \
    --from-literal=MYSQL_ROOT_PASSWORD="$ROOT_PASS" \
    --from-literal=MYSQL_DATABASE="$DB_NAME" \
    --from-literal=MYSQL_USER="$DB_USER" \
    --from-literal=MYSQL_PASSWORD="$DB_PASS" \
    --dry-run=client -o yaml | kubectl apply -f -

echo ""
echo "=================================================="
echo " Listo. El Secret 'mysql-secret' fue creado en el namespace '$NAMESPACE'"
echo " a partir de AWS Secrets Manager — sin versionar contraseñas en git."
echo "=================================================="
echo " Verifica con:"
echo "   kubectl get secret mysql-secret -n $NAMESPACE"
echo "   kubectl describe secret mysql-secret -n $NAMESPACE"
