#!/bin/bash
# setup-cloudshell.sh — Instala kubectl y Terraform en AWS CloudShell
#
# AWS CloudShell incluye AWS CLI preconfigurado con las credenciales del Learner Lab.
# kubectl y Terraform NO persisten entre sesiones de CloudShell — debes ejecutar
# este script cada vez que abras una nueva sesión.
#
# Uso: bash commons/scripts/setup-cloudshell.sh
#
# Tiempo estimado: 1-2 minutos

set -e

TERRAFORM_VERSION="1.10.5"

echo "=================================================="
echo " Setup de AWS CloudShell — INY1105 EA3"
echo " $(date '+%Y-%m-%d %H:%M:%S')"
echo "=================================================="
echo ""

# ── kubectl ───────────────────────────────────────────────────────────────────

if command -v kubectl &>/dev/null; then
    echo "[kubectl] Ya instalado: $(kubectl version --client --short 2>/dev/null || kubectl version --client)"
else
    echo "[1/4] Descargando kubectl..."
    KUBE_VERSION=$(curl -Ls https://dl.k8s.io/release/stable.txt)
    curl -sLO "https://dl.k8s.io/release/${KUBE_VERSION}/bin/linux/amd64/kubectl"

    echo "[2/4] Verificando checksum de kubectl..."
    curl -sLO "https://dl.k8s.io/release/${KUBE_VERSION}/bin/linux/amd64/kubectl.sha256"
    if echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check --quiet; then
        echo "      Checksum OK"
    else
        echo "ERROR: checksum inválido. Descarga corrupta, intenta de nuevo."
        rm -f kubectl kubectl.sha256
        exit 1
    fi
    rm -f kubectl.sha256

    echo "[3/4] Instalando kubectl..."
    chmod +x kubectl
    mkdir -p "$HOME/.local/bin"
    mv kubectl "$HOME/.local/bin/kubectl"

    # Agregar al PATH si no está
    if ! echo "$PATH" | grep -q "$HOME/.local/bin"; then
        export PATH="$HOME/.local/bin:$PATH"
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
    fi

    echo "      kubectl $(kubectl version --client --short 2>/dev/null || kubectl version --client) instalado."
fi

echo ""

# ── Terraform ─────────────────────────────────────────────────────────────────

if command -v terraform &>/dev/null; then
    echo "[terraform] Ya instalado: $(terraform version | head -1)"
else
    echo "[4/4] Descargando Terraform ${TERRAFORM_VERSION}..."
    TF_ZIP="terraform_${TERRAFORM_VERSION}_linux_amd64.zip"
    curl -sLO "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/${TF_ZIP}"

    echo "      Extrayendo Terraform..."
    unzip -q "$TF_ZIP"
    rm -f "$TF_ZIP"

    mkdir -p "$HOME/.local/bin"
    mv terraform "$HOME/.local/bin/terraform"

    if ! echo "$PATH" | grep -q "$HOME/.local/bin"; then
        export PATH="$HOME/.local/bin:$PATH"
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
    fi

    echo "      $(terraform version | head -1) instalado."
fi

echo ""

# ── git ───────────────────────────────────────────────────────────────────────

echo "[git] $(git --version)"

# ── Verificación AWS ──────────────────────────────────────────────────────────

echo ""
echo "[AWS] Verificando credenciales..."
aws sts get-caller-identity --query "{Account:Account, Arn:Arn}" --output table

echo ""
echo "=================================================="
echo " Setup completado."
echo " Herramientas disponibles en esta sesión:"
echo "   kubectl  : $(kubectl version --client --short 2>/dev/null | head -1 || echo 'listo')"
echo "   terraform: $(terraform version | head -1)"
echo "   aws cli  : $(aws --version)"
echo "   git      : $(git --version)"
echo ""
echo " RECUERDA: kubectl y Terraform no persisten entre"
echo " sesiones de CloudShell. Ejecuta este script cada"
echo " vez que abras CloudShell."
echo "=================================================="
