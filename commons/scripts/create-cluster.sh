#!/bin/bash
# create-cluster.sh — Crea el cluster EKS en AWS Learner Lab
# Uso:
#   bash commons/scripts/create-cluster.sh
#   AZS="us-east-1a,us-east-1b" bash commons/scripts/create-cluster.sh
#
# Requisitos:
#   - AWS CLI configurado con credenciales del Learner Lab
#   - Región: us-east-1
#   - Rol disponible: LabEksClusterRole
#
# Sobre las AZ:
#   EKS necesita subnets en al menos 2 zonas de disponibilidad (AZ) distintas.
#   Algunas AZ del Learner Lab no soportan EKS o no tienen capacidad (ej:
#   us-east-1e suele fallar). Si la creación falla por la AZ elegida, fija las
#   AZ buenas con la variable AZS, por ejemplo:
#       AZS="us-east-1a,us-east-1b" bash commons/scripts/create-cluster.sh

CLUSTER_NAME="iny1105-ea3-cluster"
REGION="us-east-1"
K8S_VERSION="1.32"          # Versión de Kubernetes fija para el cluster
# AZ a usar (separadas por coma). Vacío = el script elige 2 AZ automáticamente.
# Sobreescribible por variable de entorno: AZS="us-east-1a,us-east-1b" bash ...
AZS="${AZS:-}"
NODE_GROUP="standard-workers"
NODE_TYPE="t3.small"
NODES_DESIRED=2
NODES_MIN=1
NODES_MAX=3

echo "=================================================="
echo " Creando cluster EKS: $CLUSTER_NAME"
echo " Región: $REGION"
echo "=================================================="
echo ""

# Verificar credenciales AWS
echo "[1/5] Verificando credenciales AWS..."
aws sts get-caller-identity --query "{Account:Account, Arn:Arn}" --output table || {
    echo "ERROR: AWS CLI no está configurado. Ejecuta: aws configure"
    exit 1
}
echo ""

# Detectar roles EKS (nombres aleatorios por sesión en Learner Lab)
echo "[2/5] Buscando roles EKS (LabEksClusterRole y LabEksNodeRole)..."
ROLE_ARN=$(aws iam list-roles \
    --query "Roles[?contains(RoleName, 'LabEksClusterRole')].Arn" \
    --output text | tr '\t' '\n' | head -1)
if [ -z "$ROLE_ARN" ]; then
    echo "ERROR: No se encontró ningún rol con 'LabEksClusterRole' en el nombre."
    echo "Roles disponibles con 'eks' en el nombre:"
    aws iam list-roles --query "Roles[].RoleName" --output text | tr '\t' '\n' | grep -i eks || echo "(ninguno)"
    exit 1
fi
echo "  Rol de cluster : $ROLE_ARN"

NODE_ROLE_ARN=$(aws iam list-roles \
    --query "Roles[?contains(RoleName, 'LabEksNodeRole')].Arn" \
    --output text | tr '\t' '\n' | head -1)
if [ -z "$NODE_ROLE_ARN" ]; then
    echo "ERROR: No se encontró ningún rol con 'LabEksNodeRole' en el nombre."
    echo "Roles disponibles con 'eks' en el nombre:"
    aws iam list-roles --query "Roles[].RoleName" --output text | tr '\t' '\n' | grep -i eks || echo "(ninguno)"
    exit 1
fi
echo "  Rol de nodos   : $NODE_ROLE_ARN"
echo ""

# Verificar límite de instancias EC2 activas
echo "[3/5] Verificando instancias EC2 activas..."
RUNNING=$(aws ec2 describe-instances \
    --region "$REGION" \
    --filters "Name=instance-state-name,Values=running" \
    --query "length(Reservations[].Instances[])" \
    --output text)
echo "Instancias EC2 corriendo actualmente: $RUNNING (límite del Learner Lab: 9)"
if [ "$RUNNING" -gt 7 ]; then
    echo "ADVERTENCIA: Tienes $RUNNING instancias activas. El Node Group agregará $NODES_DESIRED más."
    echo "Considera detener instancias no usadas antes de continuar."
    read -p "¿Continuar de todas formas? (s/N): " CONFIRM
    if [[ "$CONFIRM" != "s" && "$CONFIRM" != "S" ]]; then
        echo "Operación cancelada."
        exit 1
    fi
fi
echo ""

# Obtener subnets públicas de la VPC por defecto, en 2 AZ distintas.
echo "[4/5] Obteniendo subnets de la VPC por defecto..."

if [ -n "$AZS" ]; then
    # AZ fijadas por el usuario (ej: "us-east-1a,us-east-1b")
    IFS=',' read -ra AZ_ARRAY <<< "$AZS"
    echo "  AZ solicitadas: $AZS"
    SUBNET_IDS=""
    for AZ in "${AZ_ARRAY[@]}"; do
        AZ_TRIM=$(echo "$AZ" | tr -d '[:space:]')
        SUBNET=$(aws ec2 describe-subnets \
            --region "$REGION" \
            --filters "Name=default-for-az,Values=true" \
                      "Name=availability-zone,Values=$AZ_TRIM" \
            --query "Subnets[0].SubnetId" \
            --output text 2>/dev/null)
        if [ -n "$SUBNET" ] && [ "$SUBNET" != "None" ]; then
            echo "    $AZ_TRIM -> $SUBNET"
            SUBNET_IDS="$SUBNET_IDS $SUBNET"
        else
            echo "    ADVERTENCIA: no hay subnet por defecto en $AZ_TRIM (se omite)."
        fi
    done
    SUBNET_IDS=$(echo "$SUBNET_IDS" | sed 's/^ *//')
else
    # Selección automática: una subnet por AZ, tomando las 2 primeras AZ
    echo "  Sin AZS fijadas — eligiendo 2 AZ automáticamente."
    echo "  (Si falla por la AZ, reintenta con: AZS=\"us-east-1a,us-east-1b\" bash $0)"
    SUBNET_IDS=$(aws ec2 describe-subnets \
        --region "$REGION" \
        --filters "Name=default-for-az,Values=true" \
        --query "Subnets[].{AZ:AvailabilityZone,Id:SubnetId}" \
        --output text 2>/dev/null \
        | sort -u -k1,1 \
        | head -2 \
        | awk '{print $2}')
fi

# Verificar que tenemos al menos 2 subnets en 2 AZ distintas
SUBNET_COUNT=$(echo "$SUBNET_IDS" | wc -w)
if [ "$SUBNET_COUNT" -lt 2 ]; then
    echo "ERROR: EKS requiere subnets en al menos 2 AZ distintas; se encontraron $SUBNET_COUNT."
    echo "       AZ disponibles con subnet por defecto en $REGION:"
    aws ec2 describe-subnets --region "$REGION" \
        --filters "Name=default-for-az,Values=true" \
        --query "Subnets[].AvailabilityZone" --output text | tr '\t' '\n' | sort -u | sed 's/^/         /'
    echo "       Reintenta fijando 2 AZ buenas, ej:"
    echo "         AZS=\"us-east-1a,us-east-1b\" bash $0"
    exit 1
fi

# Convertir de espacio/tab a coma para el parámetro subnetIds
SUBNET_IDS_COMMA=$(echo "$SUBNET_IDS" | tr '[:space:]' ',' | sed 's/,$//' | sed 's/^,//')
# Convertir a array para --subnets del nodegroup
read -ra SUBNET_ARRAY <<< "$SUBNET_IDS"
echo "Subnets ($SUBNET_COUNT): $SUBNET_IDS_COMMA"
echo ""

echo "[5/5] Cluster EKS..."

# Verificar si el cluster ya existe
CLUSTER_STATUS=$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$REGION" \
    --query "cluster.status" --output text 2>/dev/null)

if [ -z "$CLUSTER_STATUS" ]; then
    echo "Creando cluster EKS (esto tardará 10-15 minutos)..."

    # Usar la versión de Kubernetes fija definida arriba ($K8S_VERSION)
    echo "Versión de Kubernetes solicitada: $K8S_VERSION"
    K8S_VERSION_ARGS=("--kubernetes-version" "$K8S_VERSION")

    aws eks create-cluster \
        --name "$CLUSTER_NAME" \
        --region "$REGION" \
        "${K8S_VERSION_ARGS[@]}" \
        --role-arn "$ROLE_ARN" \
        --resources-vpc-config \
            "subnetIds=$SUBNET_IDS_COMMA,endpointPublicAccess=true,endpointPrivateAccess=false" \
        --output table

    if [ $? -ne 0 ]; then
        echo "ERROR: Falló la creación del cluster. Revisa los mensajes anteriores."
        exit 1
    fi
    CLUSTER_STATUS="CREATING"
else
    echo "  Cluster ya existe (estado: $CLUSTER_STATUS) — omitiendo creación."
fi

if [ "$CLUSTER_STATUS" != "ACTIVE" ]; then
    echo "Esperando a que el cluster esté ACTIVE (puede tardar 10 min)..."
    TIMEOUT=1200
    ELAPSED=0
    while true; do
        CLUSTER_STATUS=$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$REGION" \
            --query "cluster.status" --output text 2>/dev/null)
        if [ "$CLUSTER_STATUS" == "ACTIVE" ]; then
            echo "✓ Cluster ACTIVE"
            break
        elif [ "$CLUSTER_STATUS" == "FAILED" ]; then
            echo "ERROR: El cluster quedó en estado FAILED."
            echo "Revisa los permisos de LabEksClusterRole e intenta de nuevo."
            exit 1
        fi
        if [ "$ELAPSED" -ge "$TIMEOUT" ]; then
            echo "TIMEOUT: El cluster tardó más de 20 minutos. Verifica en la consola AWS."
            exit 1
        fi
        echo "  Estado: $CLUSTER_STATUS — esperando... ($ELAPSED s)"
        sleep 30
        ELAPSED=$((ELAPSED + 30))
    done
else
    echo "✓ Cluster ACTIVE"
fi
echo ""

# Verificar si el Node Group ya existe
NG_STATUS=$(aws eks describe-nodegroup \
    --cluster-name "$CLUSTER_NAME" \
    --nodegroup-name "$NODE_GROUP" \
    --region "$REGION" \
    --query "nodegroup.status" --output text 2>/dev/null)

if [ -z "$NG_STATUS" ]; then
    echo "Creando Node Group: $NODE_GROUP..."
    aws eks create-nodegroup \
        --cluster-name "$CLUSTER_NAME" \
        --nodegroup-name "$NODE_GROUP" \
        --region "$REGION" \
        --node-role "$NODE_ROLE_ARN" \
        --subnets "${SUBNET_ARRAY[@]}" \
        --instance-types "$NODE_TYPE" \
        --scaling-config "minSize=$NODES_MIN,maxSize=$NODES_MAX,desiredSize=$NODES_DESIRED" \
        --output table

    if [ $? -ne 0 ]; then
        echo "ERROR: Falló la creación del Node Group."
        exit 1
    fi
    NG_STATUS="CREATING"
else
    echo "  Node Group ya existe (estado: $NG_STATUS) — omitiendo creación."
fi

if [ "$NG_STATUS" != "ACTIVE" ]; then
    echo "Esperando a que los nodos estén ACTIVE (3-5 min adicionales)..."
    ELAPSED=0
    TIMEOUT=600
    while true; do
        NG_STATUS=$(aws eks describe-nodegroup \
            --cluster-name "$CLUSTER_NAME" \
            --nodegroup-name "$NODE_GROUP" \
            --region "$REGION" \
            --query "nodegroup.status" --output text 2>/dev/null)
        if [ "$NG_STATUS" == "ACTIVE" ]; then
            echo "✓ Node Group ACTIVE"
            break
        elif [ "$NG_STATUS" == "CREATE_FAILED" ]; then
            echo "ERROR: El Node Group quedó en estado CREATE_FAILED."
            echo "Verifica los permisos de $NODE_ROLE_ARN."
            exit 1
        fi
        if [ "$ELAPSED" -ge "$TIMEOUT" ]; then
            echo "TIMEOUT: Los nodos tardaron más de 10 minutos."
            exit 1
        fi
        echo "  Estado: $NG_STATUS — esperando... ($ELAPSED s)"
        sleep 30
        ELAPSED=$((ELAPSED + 30))
    done
else
    echo "✓ Node Group ACTIVE"
fi
echo ""

# Configurar kubectl
echo "Configurando kubectl..."
aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER_NAME"
echo ""

echo "✓ Cluster listo. Verificando nodos:"
kubectl get nodes
echo ""

# Habilitar enforcement de NetworkPolicy (necesario para Act 3.3).
# El VPC CNI solo APLICA las NetworkPolicies si se instala como addon de EKS
# con enableNetworkPolicy=true. No requiere permisos IAM.
echo "Habilitando enforcement de NetworkPolicy en el VPC CNI..."
aws eks create-addon --cluster-name "$CLUSTER_NAME" --region "$REGION" \
    --addon-name vpc-cni \
    --configuration-values '{"enableNetworkPolicy":"true"}' \
    --resolve-conflicts OVERWRITE >/dev/null 2>&1 \
    && echo "  Addon vpc-cni configurado (tarda ~90s en quedar ACTIVE)." \
    || echo "  NOTA: no se pudo configurar el addon vpc-cni (las NetworkPolicies se" \
            "aceptarán pero podrían no aplicarse)."
echo ""

echo "=================================================="
echo " Cluster $CLUSTER_NAME listo para usar"
echo " RECUERDA: Al terminar la clase ejecuta:"
echo "   bash commons/scripts/delete-cluster.sh"
echo "=================================================="
