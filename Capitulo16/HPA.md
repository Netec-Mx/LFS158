# Laboratorio — Escalado automático con HPA (Horizontal Pod Autoscaler)

## Propósito del laboratorio

Ver en acción cómo Kubernetes **añade y quita Pods automáticamente según la carga**. Habilitarás `metrics-server` en Minikube, desplegarás una aplicación que consume CPU, crearás un HPA y lanzarás una prueba de estrés para ver cómo sube la carga, cómo el HPA decide escalar y cómo vuelve a reducir las réplicas cuando la carga termina.

Al finalizar, podrás:

- Explicar qué es un HPA y qué necesita para funcionar.
- Habilitar `metrics-server` y consultar consumo con `kubectl top`.
- Crear un HPA basado en CPU con un manifiesto declarativo.
- Generar carga y observar el escalado hacia arriba y hacia abajo.
- Calcular cuántas réplicas pedirá el HPA con su fórmula.

**Duración orientativa:** 20–25 minutos (incluye esperas del escalado).

## Prerrequisitos

- Un clúster Minikube iniciado y el contexto de `kubectl` activo apuntando a él.
- Conexión a Internet para descargar las imágenes `registry.k8s.io/hpa-example` y `busybox:1.28`.
- Haber trabajado con `Deployment` y `Service`.

## Cómo funciona un HPA

Un HPA es un **controlador** que revisa cada ~15 segundos la métrica de un `Deployment` y ajusta su número de réplicas para acercarse a un objetivo.

```text
 Pods ──► metrics-server ──► API de métricas ──► HPA ──► cambia spec.replicas del Deployment
 (usan CPU)   (mide)            (kubectl top)    (decide)        (Kubernetes crea o elimina Pods)
```

**Fórmula que usa el HPA:**

```text
réplicas deseadas = ceil( réplicas actuales × métrica actual / métrica objetivo )
```

Ejemplo: 1 réplica al 250 % de CPU con objetivo del 50 % → `ceil(1 × 250 / 50) = 5` réplicas (limitado por `maxReplicas`).

**Tres requisitos para que funcione:**

| Requisito | Por qué |
|---|---|
| `metrics-server` instalado | Sin él, el HPA no recibe métricas. |
| `resources.requests.cpu` en los Pods | El porcentaje se calcula como **uso ÷ request**. Sin request, el HPA no puede calcularlo. |
| Un controlador que escale (`Deployment`) | El HPA modifica sus réplicas. |

## 1. Preparar el entorno y habilitar metrics-server

Guarda el nombre del perfil (en Minikube coincide con el nombre del contexto) y comprueba el clúster:

```bash
PERFIL=$(kubectl config current-context)
echo "Perfil: $PERFIL"
minikube status -p "$PERFIL"
kubectl get nodes
```

Habilita el complemento:

```bash
minikube addons enable metrics-server -p "$PERFIL"
kubectl rollout status deployment/metrics-server -n kube-system --timeout=120s
```

Comprueba que las métricas ya están disponibles:

```bash
kubectl top nodes
kubectl top pods -A
```

**Observa:**

- `kubectl top nodes` muestra CPU y memoria del nodo.
- Si aparece `error: Metrics API not available`, espera uno o dos minutos y repite: `metrics-server` necesita recolectar sus primeras mediciones.

## 2. Desplegar la aplicación de prueba

Crea el namespace y el manifiesto. La aplicación `hpa-example` hace cálculos que consumen CPU en cada petición:

```bash
mkdir -p ~/k8s-intro/manifests ~/k8s-intro/artifacts
kubectl create namespace hpa-lab

cat > ~/k8s-intro/manifests/php-apache.yaml <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: php-apache
  namespace: hpa-lab
spec:
  replicas: 1
  selector:
    matchLabels:
      app: php-apache
  template:
    metadata:
      labels:
        app: php-apache
    spec:
      containers:
        - name: php-apache
          image: registry.k8s.io/hpa-example
          ports:
            - containerPort: 80
          resources:
            requests:
              cpu: 200m
            limits:
              cpu: 500m
---
apiVersion: v1
kind: Service
metadata:
  name: php-apache
  namespace: hpa-lab
spec:
  selector:
    app: php-apache
  ports:
    - port: 80
      targetPort: 80
EOF

kubectl apply -f ~/k8s-intro/manifests/php-apache.yaml
kubectl rollout status deployment/php-apache -n hpa-lab --timeout=180s
kubectl get deployment,pods,service -n hpa-lab
```

**Observa:** el campo clave es `resources.requests.cpu: 200m` (0,2 CPU). **Ese valor es la base del 100 %** que usará el HPA: si un Pod consume 100m, está al 50 %.

## 3. Crear el HPA

```bash
cat > ~/k8s-intro/manifests/php-apache-hpa.yaml <<'EOF'
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: php-apache
  namespace: hpa-lab
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: php-apache
  minReplicas: 1
  maxReplicas: 5
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 50
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 60
EOF

kubectl apply -f ~/k8s-intro/manifests/php-apache-hpa.yaml
kubectl get hpa -n hpa-lab
```

| Campo | Significado |
|---|---|
| `scaleTargetRef` | Qué recurso escala (el Deployment `php-apache`). |
| `minReplicas` / `maxReplicas` | Límites inferior y superior de réplicas. |
| `averageUtilization: 50` | Objetivo: mantener la CPU media al 50 % del `request`. |
| `behavior.scaleDown.stabilizationWindowSeconds: 60` | Espera 60 s antes de reducir. El valor por defecto es 300 s; se acorta para que el laboratorio sea más corto. |

**Observa:** la columna `TARGETS` muestra `cpu: 0%/50%` (uso actual / objetivo) y `REPLICAS` muestra `1`. Si aparece `<unknown>/50%`, espera un minuto: el HPA aún no recibió las primeras métricas.

> **Alternativa imperativa:** `kubectl autoscale deployment php-apache -n hpa-lab --cpu-percent=50 --min=1 --max=5` crea un HPA equivalente, pero no permite configurar `behavior` y no queda en un archivo versionable.

## 4. Prueba de estrés: generar carga

Abre **tres terminales** (todas con el mismo contexto de `kubectl`).

**Terminal 2 — observar el HPA en vivo y guardar la evidencia:**

```bash
kubectl get hpa php-apache -n hpa-lab -w | tee ~/k8s-intro/artifacts/hpa-watch.txt
```

**Terminal 3 — observar el consumo de los Pods:**

```bash
watch -n 5 kubectl top pods -n hpa-lab
```

**Terminal 1 — lanzar el generador de carga.** Este Pod hace peticiones HTTP continuas al Service:

```bash
kubectl run load-generator -n hpa-lab --image=busybox:1.28 --restart=Never -- \
  /bin/sh -c "while true; do wget -q -O- http://php-apache; done"
```

**Qué debes ver, en este orden:**

| Momento | Terminal 3 (`top`) | Terminal 2 (HPA) |
|---|---|---|
| Inicio | CPU del Pod cerca de `1m` | `cpu: 0%/50%`, 1 réplica |
| ~30–60 s | CPU sube hacia el `limit` (`500m`) | `TARGETS` sube, por ejemplo `250%/50%` |
| ~1–2 min | Aparecen Pods nuevos y la CPU se reparte | `REPLICAS` pasa de 1 a 4 o 5 |
| Estabilización | CPU por Pod baja hacia el 50 % | `TARGETS` se acerca a `50%/50%` |

Si la carga no es suficiente para escalar, lanza un segundo generador:

```bash
kubectl run load-generator-2 -n hpa-lab --image=busybox:1.28 --restart=Never -- \
  /bin/sh -c "while true; do wget -q -O- http://php-apache; done"
```

### 4.1. Leer la decisión del HPA

Con la carga activa, consulta los eventos del HPA:

```bash
kubectl describe hpa php-apache -n hpa-lab
kubectl get pods -n hpa-lab
```

**Observa:**

- En `Metrics` aparece el uso actual frente al objetivo (por ejemplo, `250% (500m) / 50%`).
- En `Events` hay mensajes `SuccessfulRescale` del tipo `New size: 4; reason: cpu resource utilization (percentage of request) above target`. Esa es la **evidencia de que el HPA tomó la decisión**.
- El número de Pods es el que la fórmula predice, limitado por `maxReplicas: 5`.

Verifica el cálculo con tus datos: `ceil(réplicas × uso% / 50)`.

## 5. Terminar la carga y observar la reducción

Elimina el generador (y el segundo, si lo creaste):

```bash
kubectl delete pod load-generator load-generator-2 -n hpa-lab --ignore-not-found
```

Observa las terminales 2 y 3 durante 2 a 3 minutos:

- La CPU por Pod cae a `~0%`.
- Tras la ventana de estabilización (60 s en este laboratorio), `REPLICAS` baja progresivamente hasta `1`.

**Importante:** el HPA escala hacia arriba rápido y hacia abajo con cautela. La ventana de estabilización evita que el número de réplicas oscile cuando la carga es irregular.

## 6. Guardar la evidencia

Cuando las réplicas hayan vuelto a `1`, detén el `watch` de la terminal 2 con `Ctrl+C` y guarda el resumen:

```bash
{
  echo "=== HPA ==="
  kubectl get hpa php-apache -n hpa-lab
  echo
  echo "=== Eventos de escalado ==="
  kubectl get events -n hpa-lab --field-selector reason=SuccessfulRescale \
    --sort-by=.metadata.creationTimestamp
  echo
  echo "=== Descripción del HPA ==="
  kubectl describe hpa php-apache -n hpa-lab
} > ~/k8s-intro/artifacts/hpa-evidencia.txt

grep -E 'SuccessfulRescale|New size' ~/k8s-intro/artifacts/hpa-evidencia.txt
grep -E '[0-9]+%/50%' ~/k8s-intro/artifacts/hpa-watch.txt | head -n 15
```

**Observa:** los eventos muestran el escalado hacia arriba (`New size: 4` o `5`) y hacia abajo (`New size: 1`), y `hpa-watch.txt` registra cómo subió el porcentaje de CPU.

## 7. Criterios de finalización

- [ ] `metrics-server` está habilitado y `kubectl top nodes` devuelve datos.
- [ ] El Deployment tiene `resources.requests.cpu` y el HPA muestra un porcentaje, no `<unknown>`.
- [ ] Con carga, el HPA aumentó `REPLICAS` por encima de 1.
- [ ] Encontraste en `describe hpa` el evento `SuccessfulRescale`.
- [ ] Sin carga, las réplicas volvieron a `1`.
- [ ] Guardaste `hpa-evidencia.txt` y `hpa-watch.txt`.

## 8. Preguntas de cierre

1. ¿Por qué el HPA necesita `resources.requests.cpu` para calcular el porcentaje?
2. Si 2 réplicas están al 90 % de CPU y el objetivo es 60 %, ¿cuántas réplicas pedirá el HPA?
3. ¿Por qué la reducción de réplicas es más lenta que el aumento?
4. ¿Qué pasaría con el HPA si `maxReplicas` fuera `2`?
5. ¿Qué diferencia hay entre escalar con un HPA y ejecutar `kubectl scale`?

## Solución de problemas

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| `error: Metrics API not available` | `metrics-server` aún no recolectó datos. | Espera 1–2 minutos. Revisa `kubectl get pods -n kube-system -l k8s-app=metrics-server`. |
| `TARGETS` muestra `<unknown>/50%` | Faltan métricas o `requests.cpu`. | Revisa `kubectl describe hpa php-apache -n hpa-lab`; el mensaje indica la causa (por ejemplo, `missing request for cpu`). |
| `ImagePullBackOff` en `php-apache` o en `load-generator` | Sin acceso a `registry.k8s.io` o a Docker Hub. | Comprueba la conexión a Internet con `kubectl describe pod`. |
| El HPA no escala | La carga es baja o el generador no está en `Running`. | `kubectl get pods -n hpa-lab`; revisa `kubectl logs load-generator -n hpa-lab`; lanza `load-generator-2`. |
| Las réplicas no bajan | La ventana de estabilización no ha terminado. | Espera al menos 60 s extra y confirma que el generador fue eliminado. |
| Pods en `Pending` al escalar | El nodo no tiene CPU o memoria suficientes. | `kubectl describe pod <pod> -n hpa-lab`. Reduce `maxReplicas` o libera recursos del equipo. |

## Limpieza

Elimina los recursos del laboratorio:

```bash
kubectl delete namespace hpa-lab
```

Opcionalmente, deshabilita `metrics-server` si no lo necesitas en otros laboratorios:

```bash
minikube addons disable metrics-server -p "$PERFIL"
```

Conserva `~/k8s-intro/manifests/php-apache.yaml` y `~/k8s-intro/manifests/php-apache-hpa.yaml` como referencia.

## Resultado esperado

Habrás visto el ciclo completo del escalado automático: el generador sube la CPU, `metrics-server` la mide, el HPA calcula las réplicas necesarias con su fórmula, Kubernetes crea los Pods nuevos y, al terminar la carga, el HPA reduce las réplicas con cautela. La evidencia queda en `hpa-watch.txt` y `hpa-evidencia.txt`.

---

## Apéndice para autoevaluación

<details>
<summary>Respuestas a las preguntas de cierre</summary>

1. Porque el porcentaje se calcula como uso ÷ request; sin request, no hay base para el 100 %.
2. `ceil(2 × 90 / 60) = ceil(3) = 3` réplicas.
3. Para evitar oscilaciones: reducir de inmediato ante una caída breve de carga obligaría a volver a crear Pods enseguida. Por eso existe la ventana de estabilización.
4. El HPA no pasaría de 2 réplicas aunque la CPU siguiera por encima del objetivo; el porcentaje se mantendría alto.
5. `kubectl scale` fija un número de réplicas manualmente y una sola vez; el HPA lo ajusta continuamente según la métrica.

</details>