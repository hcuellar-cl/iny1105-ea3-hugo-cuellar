# Act 3.2 — Objetos de Kubernetes: Deployments, Services y ConfigMaps

## Manifiestos de esta actividad

Los manifiestos ya vienen configurados. Revísalos para entender cada objeto:

| Archivo | Objeto Kubernetes | Contenido |
|---|---|---|
| `manifests/namespace.yaml` | Namespace | `monitoring` — aísla los recursos de la actividad |
| `manifests/configmap.yaml` | ConfigMap | `prometheus-config` — APP_ENV, LOG_LEVEL, PROMETHEUS_RETENTION_TIME |
| `manifests/deployment.yaml` | Deployment | `prometheus-v2` — 2 réplicas, imagen, resources, envFrom |
| `manifests/service.yaml` | Service | `prometheus-v2` — tipo ClusterIP |

## Aplicar los manifiestos directamente

Aplica cada manifiesto con `kubectl apply -f`, **respetando este orden** (el
namespace debe existir antes que los objetos que viven dentro de él):

```bash
# 1. Crear el namespace (debe ir primero)
kubectl apply -f manifests/namespace.yaml

# 2. Crear el ConfigMap (el Deployment lo consume con envFrom)
kubectl apply -f manifests/configmap.yaml

# 3. Crear el Deployment (levanta los 2 Pods)
kubectl apply -f manifests/deployment.yaml

# 4. Crear el Service (expone los Pods)
kubectl apply -f manifests/service.yaml
```

> Alternativa: `kubectl apply -f manifests/` aplica todos los archivos del
> directorio, pero NO garantiza el orden. Por eso, la primera vez aplícalos
> uno por uno como se muestra arriba.

## Verificar el despliegue

```bash
# Ver todos los objetos del namespace
kubectl get all -n monitoring

# Confirmar que las variables del ConfigMap llegaron al contenedor
POD=$(kubectl get pods -n monitoring -l app=prometheus-v2 -o jsonpath="{.items[0].metadata.name}")
kubectl exec -n monitoring "$POD" -- env | grep APP_ENV

# Ver detalle del ConfigMap
kubectl describe configmap prometheus-config -n monitoring
```

## Experimentar (Fase 3)

```bash
# Escalar a 3 réplicas
kubectl scale deployment prometheus-v2 -n monitoring --replicas=3

# Verificar el rollout
kubectl rollout status deployment/prometheus-v2 -n monitoring

# Probar la autorecuperación: elimina un Pod y observa cómo se recrea
kubectl delete pod <nombre-pod> -n monitoring
kubectl get pods -n monitoring -w

# Exponer por NodePort 30092: edita service.yaml
#   type: NodePort  +  nodePort: 30092  bajo el puerto
kubectl apply -f manifests/service.yaml
```
