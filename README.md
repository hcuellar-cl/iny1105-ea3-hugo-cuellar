# Evaluación Parcial N°3: Despliegue de Redmine + PostgreSQL en Kubernetes (AWS EKS)

**Asignatura:** Infraestructura de Aplicaciones I (INY1105)  
**Estudiante:** Hugo Cuéllar  
**Docente:** Rodrigo Aguilar G.  
**Fecha:** Junio de 2026  

---

## 1. Descripción de la Arquitectura Desplegada

Este proyecto consiste en el despliegue de una solución de dos capas de alta disponibilidad y persistencia para la consultora **PMOTrack**:
*   **Capa Frontend (Redmine v5):** Aplicación web que permite administrar proyectos y tareas. Se conecta a la base de datos PostgreSQL de forma interna mediante DNS interno de Kubernetes.
*   **Capa Base de Datos (PostgreSQL v16):** Almacenamiento de datos del sistema, persistido a través de volumen local (`hostPath`) enlazado a un nodo específico del cluster mediante etiquetas (`nodeSelector`) y un par `PersistentVolume`/`PersistentVolumeClaim`.

Toda la infraestructura está aislada bajo el Namespace `pmotrack` dentro de un cluster gestionado de AWS EKS. El tráfico hacia el frontend web se expone a través de un servicio de tipo `NodePort`. El escalado de la aplicación frontend se maneja automáticamente mediante un objeto `HorizontalPodAutoscaler` (HPA) que consume métricas desde el Kubernetes Metrics Server.

```
                  [ Navegador Web del Usuario ]
                                ↓ (Puerto Público NodePort 30093)
                     [ Nodo EKS (Instancia EC2) ]
                                ↓
                 [ Servicio NodePort: redmine ] (pmotrack)
                                ↓
        ┌───────────────────────┴───────────────────────┐
        ▼ (Réplica 1)           ▼ (Réplica 2 - HPA)     ▼ (Réplica N - HPA)
  [ Pod Redmine ]         [ Pod Redmine ]         [ Pod Redmine ]
        └───────────────────────┬───────────────────────┘
                                ↓ (Conexión TCP 5432)
                     [ Servicio ClusterIP: postgres ]
                                ↓
                      [ Pod PostgreSQL ] (1 réplica)
                                ↓ (Montaje de Volumen)
                    [ PVC / PV: postgres-pvc ]
                                ↓ (Persistencia Local)
                    [ hostPath: /mnt/data/postgres ]
```

---

## 2. Decisiones Técnicas Tomadas

1.  **Imágenes Utilizadas:**
    *   **PostgreSQL 16:** Se seleccionó la versión oficial `postgres:16` por su estabilidad, rendimiento mejorado en la indexación y amplio soporte de extensiones.
    *   **Redmine 5:** Se utilizó `redmine:5` (basado en Debian), versión madura de la aplicación compatible con PostgreSQL 16 y optimizada para operar en contenedores Docker.
2.  **Estrategia de Almacenamiento Persistente:**
    *   Se optó por el uso de `hostPath` apuntando a `/mnt/data/postgres` en el disco local del nodo.
    *   Dado que `hostPath` ata físicamente los datos al nodo físico que ejecuta el Pod, se configuró un `nodeSelector` (`postgres-node: "true"`) en el Deployment de PostgreSQL. Esto asegura que si el Pod se recrea por fallos o mantenimiento, siempre se levante en el mismo nodo donde se crearon los archivos iniciales.
    *   *Nota de producción:* En entornos reales fuera del Learner Lab de AWS se utilizaría el driver de almacenamiento EBS (gp3) o EFS para permitir una persistencia independiente de la vida útil del nodo.
3.  **Tipos de Service:**
    *   **PostgreSQL (ClusterIP):** Expuesto únicamente dentro del cluster en el puerto `5432` para evitar brechas de seguridad por exposición externa.
    *   **Redmine (NodePort):** Expuesto mediante el puerto estático `30093`. Al no contar con permisos de IAM suficientes en el laboratorio para crear Balanceadores de Carga de AWS (ALB/NLB) a través de un controlador, `NodePort` permite la entrada directa al puerto público de los nodos EC2.
4.  **Autoscaling del Frontend (HPA):**
    *   Se configuró un HPA sobre el Deployment de Redmine para oscilar de forma reactiva entre **1 y 5 réplicas**.
    *   El criterio de escalado se fijó al **50% de uso promedio de CPU** en base a las solicitudes del Pod. Para que esto funcione, se agregaron definiciones explícitas de recursos solicitados (`resources.requests.cpu: "250m"`) al contenedor de Redmine.

---

## 3. Instrucciones de Despliegue Paso a Paso

Siga estos pasos desde AWS CloudShell para desplegar la aplicación completa:

### Paso 1: Inicializar el Entorno y el Cluster
1.  Configure las herramientas necesarias (kubectl, terraform, etc.) si es una sesión nueva:
    ```bash
    bash commons/scripts/setup-cloudshell.sh
    ```
2.  Cree el cluster EKS (este proceso puede demorar entre 10 y 15 minutos):
    ```bash
    bash commons/scripts/create-cluster.sh
    ```
3.  Verifique que los nodos estén activos y en estado `Ready`:
    ```bash
    kubectl get nodes
    ```

### Paso 2: Preparar el Namespace y el Nodo Persistente
1.  Aplique el namespace:
    ```bash
    kubectl apply -f manifests/00-namespace.yaml
    ```
2.  Obtenga el nombre del primer nodo disponible y etiquételo para asociarle el volumen local:
    ```bash
    NODO=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
    kubectl label node "$NODO" postgres-node=true
    ```
3.  Compruebe que la etiqueta se haya aplicado correctamente:
    ```bash
    kubectl get nodes --show-labels | grep postgres-node
    ```

### Paso 3: Aplicar Secretos y Almacenamiento
1.  Despliegue el Secret con las credenciales de la base de datos:
    ```bash
    kubectl apply -f manifests/01-postgres-secret.yaml
    ```
2.  Aplique el volumen persistente (PV) y su reclamo (PVC):
    ```bash
    kubectl apply -f manifests/02-postgres-storage.yaml
    ```
3.  Verifique que el PVC esté asociado correctamente (estado `Bound`):
    ```bash
    kubectl get pvc -n pmotrack
    ```

### Paso 4: Desplegar PostgreSQL y Redmine
1.  Levante la capa de base de datos PostgreSQL:
    ```bash
    kubectl apply -f manifests/03-postgres.yaml
    ```
    *(Espere a que el Pod esté en estado Running con `kubectl get pods -n pmotrack -w`)*
2.  Levante el frontend Redmine y su servicio NodePort:
    ```bash
    kubectl apply -f manifests/04-redmine.yaml
    ```
3.  Verifique el estado de todos los recursos desplegados en el namespace:
    ```bash
    kubectl get all -n pmotrack
    ```

### Paso 5: Habilitar Acceso Externo
1.  Abra el puerto `30093` en el Security Group de los nodos EKS usando el script provisto:
    ```bash
    bash commons/scripts/open-nodeport.sh 30093
    ```
2.  El script imprimirá la URL pública en el formato: `http://<IP-NODO>:30093`. Abra esta dirección en su navegador para validar el acceso web.

### Paso 6: Configurar el Autoscaling (HPA)
1.  Instale el Metrics Server (requerido para capturar estadísticas de CPU/Memoria):
    ```bash
    kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
    ```
2.  Espere 60 segundos y confirme que el comando de monitoreo devuelva métricas:
    ```bash
    kubectl top pods -n pmotrack
    ```
3.  Aplique la regla de auto-escalado:
    ```bash
    kubectl apply -f manifests/05-redmine-hpa.yaml
    ```
4.  Compruebe el estado del HPA (inicialmente puede mostrar `<unknown>` en la columna `TARGETS` mientras recopila métricas; tras unos segundos debe cambiar a `0%/50%`):
    ```bash
    kubectl get hpa -n pmotrack
    ```

---

## 4. Instrucciones para Pruebas y Evidencias

### Prueba de Carga (Autoscaling)
1.  Inicie el bombardeo HTTP para simular alta demanda:
    ```bash
    bash manifests/06-stress-test.sh
    ```
2.  Abra otra terminal o pestaña y observe en tiempo real cómo aumenta la métrica y se crean réplicas adicionales:
    ```bash
    kubectl get hpa -n pmotrack -w
    # O también:
    kubectl get pods -n pmotrack -l app=redmine -w
    ```
3.  Una vez verificado el escalado (debe llegar a 3 o más réplicas), detenga la prueba:
    ```bash
    bash manifests/06-stress-test.sh stop
    ```

### Prueba de Persistencia
1.  Acceda a Redmine, cree una cuenta de administrador de prueba o configure un nuevo proyecto básico (ej. "Proyecto PMOTrack").
2.  Elimine el Pod de PostgreSQL simulando una caída abrupta:
    ```bash
    POD_DB=$(kubectl get pods -n pmotrack -l app=postgres -o jsonpath='{.items[0].metadata.name}')
    kubectl delete pod "$POD_DB" -n pmotrack
    ```
3.  Compruebe que Kubernetes levanta de inmediato un nuevo Pod de PostgreSQL.
4.  Refresque el navegador e ingrese nuevamente a Redmine. El proyecto creado anteriormente debe seguir visible, confirmando que la información persistió en el volumen físico.

---

## 5. Estructura de Evidencias en el Repositorio

Para obtener la calificación máxima, guarde las capturas de pantalla de sus terminales y navegador en la carpeta `evidencias/` con los siguientes nombres:

*   `evidencias/01-nodes.png`: Muestra el output de `kubectl get nodes` demostrando el cluster activo.
*   `evidencias/02-get-all.png`: Captura de `kubectl get all -n pmotrack` listando todos los recursos en ejecución.
*   `evidencias/03-pvc-bound.png`: Captura de `kubectl get pvc -n pmotrack` enseñando el estado `Bound`.
*   `evidencias/04-redmine-browser.png`: Pantallazo de Redmine abierto en el navegador indicando la URL `http://<IP>:30093`.
*   `evidencias/05-hpa-autoscaling.png`: Muestra la terminal con `kubectl get hpa -n pmotrack` después de aplicar carga, evidenciando el aumento de réplicas.
*   `evidencias/06-persistencia.png`: Pantallazo de Redmine con el proyecto creado visible tras haber eliminado el Pod de base de datos.

---

## 6. Limpieza de Recursos (Obligatorio al finalizar)

Para evitar agotar el crédito de AWS Learner Lab de forma anticipada, elimine el cluster al terminar sus pruebas:
```bash
bash commons/scripts/delete-cluster.sh
```
