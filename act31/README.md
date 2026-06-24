# Act 3.1 — Introducción a Kubernetes y AWS EKS

## Archivos a completar

| Archivo | Qué completar |
|---|---|
| `Dockerfile` | FROM, LABEL, VOLUME, EXPOSE |
| `manifests/deployment.yaml` | replicas, image URI, variable de entorno |
| `manifests/service.yaml` | nodePort, type |

## Comandos de esta actividad

```bash
# Crear el namespace
kubectl create namespace monitoring

# Aplicar manifiestos
kubectl apply -f manifests/deployment.yaml
kubectl apply -f manifests/service.yaml

# Verificar estado
kubectl get pods -n monitoring
kubectl get svc -n monitoring

# Obtener IP pública de los nodos
kubectl get nodes -o wide

# Acceder a Prometheus: http://<EXTERNAL-IP>:30090
```
