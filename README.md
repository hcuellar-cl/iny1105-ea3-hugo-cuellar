# INY1105 — EA3: Orquestación de Contenedores con Kubernetes y AWS EKS

**INY1105 — Infraestructura de Aplicaciones I**  
DuocUC · Escuela de Informática y Telecomunicaciones · 2026/1

---

## Instrucciones

### 1. Crea tu propio repositorio desde este template

1. Haz clic en el botón **"Use this template"** → **"Create a new repository"**
2. En el campo **Repository name** escribe: `iny1105-ea3-nombre-apellido` (usa tu nombre real)
3. Selecciona **Private**
4. Haz clic en **"Create repository"**

> **Importante:** El repositorio debe quedar en **tu cuenta personal** de GitHub.  
> El nombre debe seguir el formato `iny1105-ea3-nombre-apellido` exactamente.

---

### 2. Clona tu repositorio

```bash
git clone https://github.com/tu-usuario/iny1105-ea3-nombre-apellido.git
cd iny1105-ea3-nombre-apellido
```

---

### 3. Estructura del repositorio

```
iny1105-ea3-nombre-apellido/
├── act31/                  ← Act 3.1: Introducción a Kubernetes y AWS EKS
│   ├── Dockerfile          ← completar: imagen base Prometheus
│   ├── manifests/
│   │   ├── deployment.yaml ← completar: secciones TODO
│   │   └── service.yaml    ← completar: secciones TODO
│   └── README.md
├── act32/                  ← Act 3.2: Objetos de Kubernetes
│   ├── manifests/
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   └── configmap.yaml  ← completar: secciones TODO
│   └── README.md
├── act33/                  ← Act 3.3: WordPress + MySQL (almacenamiento, networking y autoscaling)
│   ├── manifests/          ← PVC (EBS/EFS), Deployments, Services, Ingress (ALB),
│   │                          HPA y NetworkPolicy
│   └── README.md
├── commons/
│   └── scripts/
│       ├── setup-cloudshell.sh ← instala kubectl y Terraform en AWS CloudShell
│       ├── create-cluster.sh   ← crea el cluster EKS
│       ├── delete-cluster.sh   ← elimina el cluster EKS
│       └── apply-manifests.sh  ← SOLO act31: aplica todos los manifiestos de una vez
├── .gitignore
└── README.md               ← este archivo
```

---

### 4. Flujo de trabajo por actividad

```
[1] Leer el README.md de la carpeta actXX/
        ↓
[2] Completar los archivos marcados con # TODO
        ↓
[3] Aplicar los manifiestos con kubectl apply
        ↓
[4] Verificar el despliegue con kubectl get pods/svc
        ↓
[5] Hacer commit y push con tus cambios
```

---

### 5. Scripts de utilidad

Desde la raíz del repositorio:

```bash
# Crear el cluster EKS (necesario al inicio de cada clase)
bash commons/scripts/create-cluster.sh

# Eliminar el cluster EKS (obligatorio al terminar cada clase)
bash commons/scripts/delete-cluster.sh

# Aplicar todos los manifiestos de UNA actividad (solo act31)
bash commons/scripts/apply-manifests.sh act31
```

> **Importante:** El script `apply-manifests.sh` se usa **solo en la Act 3.1**,
> como introducción. En las actividades 3.2, 3.3 y 3.4 aplicarás los manifiestos
> **manualmente** con `kubectl apply -f manifests/<archivo>.yaml`, respetando el
> orden indicado en el README de cada actividad. Así aprendes las dependencias
> entre objetos de Kubernetes.

---

### 6. Subir tu trabajo

```bash
git add .
git commit -m "feat: act3X completada - Nombre Apellido"
git push origin main
```

---

*Docente: Rodrigo Aguilar G. — r.aguilarg@profesor.duoc.cl*
