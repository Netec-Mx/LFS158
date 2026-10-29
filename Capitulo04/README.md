# Capítulo 4 — Exploración de capacidades de Kubernetes

## Propósito del laboratorio

Explorar qué ofrece realmente la API de tu clúster Minikube y contrastarlo con la matriz de necesidades que construiste en el capítulo 3. Consultarás los recursos disponibles, distinguirás los de ámbito de clúster de los de ámbito de namespace, crearás de forma declarativa el namespace de trabajo `laboratorio-k8s` y comprobarás qué contiene un namespace recién creado.

Este es el primer laboratorio en el que **modificas el clúster**, y lo haces de forma controlada: solo se crea el namespace `laboratorio-k8s`. No se despliega ninguna aplicación. Los hallazgos se guardan en `~/k8s-intro/analisis/capacidades-kubernetes.md` y el manifiesto queda en `~/k8s-intro/manifests/` para los capítulos siguientes.

Al finalizar, podrás:

- Consultar los recursos y las versiones que expone la API de Kubernetes.
- Distinguir recursos de ámbito de clúster y de ámbito de namespace.
- Usar `kubectl explain` para entender los campos de un recurso.
- Explorar los namespaces del sistema sin modificarlos.
- Crear y actualizar un recurso de forma declarativa con `kubectl apply` y previsualizar cambios con `kubectl diff`.
- Explicar qué significa que `apply` sea idempotente.
- Relacionar los recursos de la API con las necesidades de tu matriz del capítulo 3.

**Duración orientativa:** 20–25 minutos, dependiendo del tiempo de análisis y discusión.

## Prerrequisitos

- Haber completado los laboratorios de los capítulos 1 a 3.
- Tener el archivo `~/k8s-intro/analisis/necesidades-orquestacion.md` del capítulo 3.
- Tener Minikube iniciado y el contexto `kubectl` configurado como `minikube`.
- Conocer la idea de estado deseado: tú declaras una configuración y los controladores trabajan para acercar el estado real a ese estado.

## 1. Comprobar el entorno

Verifica el contexto, las versiones y el nodo:

```bash
kubectl config current-context
kubectl version
kubectl get nodes
minikube status -p minikube
```

Prepara los directorios de trabajo:

```bash
mkdir -p ~/k8s-intro/manifests ~/k8s-intro/analisis
ls ~/k8s-intro
```

**Observa:**

- El contexto debe ser `minikube`.
- `kubectl version` muestra la versión del cliente y la del servidor; ambas deben ser `v1.31.0`.
- El nodo `minikube` debe aparecer con estado `Ready` y rol `control-plane`.

Si algo no coincide, no continúes: revisa la sección **Solución de problemas**.

## 2. Explorar la API de Kubernetes

Todo en Kubernetes es un recurso que se consulta y se modifica a través de la API. Primero mira la magnitud de lo disponible:

```bash
kubectl api-resources | wc -l
kubectl api-resources --namespaced=true | wc -l
kubectl api-resources --namespaced=false | wc -l
```

**Observa:** los números pueden variar entre clústeres. Una parte de los recursos vive dentro de un namespace y otra pertenece al clúster completo.

Consulta los grupos de la API y los recursos de uno de ellos:

```bash
kubectl api-versions | sort | head -n 15
kubectl api-resources --api-group=apps
```

**Observa:** `Deployment` pertenece al grupo `apps` (`apps/v1`), mientras que `Pod`, `Service`, `ConfigMap`, `Secret` y `Namespace` pertenecen al grupo principal (`v1`).

Filtra los seis recursos que usarás en el curso y guarda la evidencia:

```bash
kubectl api-resources \
  | awk 'NR == 1 || $1 ~ /^(pods|deployments|services|configmaps|secrets|namespaces)$/' \
  | tee ~/k8s-intro/analisis/api-resources-filtrados.txt
```

Comprueba el resultado:

```bash
grep -E '^(pods|deployments|services|configmaps|secrets|namespaces)[[:space:]]' \
  ~/k8s-intro/analisis/api-resources-filtrados.txt
```

**Observa:**

- Deben aparecer seis líneas.
- La columna `NAMESPACED` es `true` para `pods`, `deployments`, `services`, `configmaps` y `secrets`.
- `namespaces` aparece con `false`: es un recurso de clúster, no pertenece a ningún namespace.
- Que un recurso aparezca aquí confirma que la API lo ofrece. **No** significa que ya exista una instancia.

Ahora consulta los campos de un recurso con `kubectl explain`:

```bash
kubectl explain namespace
kubectl explain deployment.spec.replicas
kubectl explain pod.spec.containers.image
```

**Observa:** `explain` muestra la descripción oficial y el tipo de cada campo. Es la forma más rápida de saber qué escribir en un manifiesto sin buscar en internet.

**Responde antes de continuar:**

1. ¿En qué grupo de la API vive `Deployment` y en cuál vive `Pod`?
2. ¿Por qué `namespaces` aparece con `NAMESPACED` igual a `false`?
3. ¿Qué diferencia hay entre que la API ofrezca `Deployment` y que exista un Deployment en el clúster?

## 3. Inspeccionar los namespaces existentes

Lista los namespaces del clúster:

```bash
kubectl get namespaces
kubectl get namespace default -o wide
```

Observa qué hay en el namespace del sistema (solo lectura):

```bash
kubectl get pods -n kube-system
kubectl get pods -A
```

Comprueba si el namespace del curso ya existe:

```bash
kubectl get namespace laboratorio-k8s
```

**Observa:**

- Existen `default`, `kube-node-lease`, `kube-public` y `kube-system`.
- Los Pods del sistema (como `coredns`, `etcd`, `kube-apiserver` y `kube-proxy`) viven en `kube-system`. Los namespaces permiten que el trabajo del curso no se mezcle con ellos.
- Si el último comando responde `NotFound`, el namespace todavía no existe; eso es lo esperado.

**Importante:** no modifiques ni elimines `kube-system`, `kube-public` ni `kube-node-lease`, y no uses `default` para las aplicaciones del curso. Todo el trabajo se hará en `laboratorio-k8s`.

## 4. Crear el namespace de forma declarativa

Escribe el manifiesto del namespace:

```bash
cat > ~/k8s-intro/manifests/namespace-laboratorio-k8s.yaml <<'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: laboratorio-k8s
  labels:
    curso: kubernetes-introduccion
    entorno: laboratorio
EOF
```

Revísalo y aplícalo:

```bash
cat ~/k8s-intro/manifests/namespace-laboratorio-k8s.yaml
kubectl apply -f ~/k8s-intro/manifests/namespace-laboratorio-k8s.yaml
```

**Observa:** debe mostrarse `namespace/laboratorio-k8s created`.

Comprueba el estado y las etiquetas:

```bash
kubectl get namespace laboratorio-k8s
kubectl get namespace laboratorio-k8s --show-labels
```

Consulta el recurso completo tal como lo almacena Kubernetes:

```bash
kubectl get namespace laboratorio-k8s -o yaml
```

**Observa:**

- `status.phase` es `Active`.
- Aparecen tus etiquetas `curso` y `entorno`.
- Kubernetes añadió por su cuenta la etiqueta `kubernetes.io/metadata.name`.
- Hay datos que tú no escribiste, como `uid` y `creationTimestamp`. El manifiesto es tu **estado deseado**; el objeto almacenado incluye además el **estado real**.

### 4.1. Idempotencia: aplicar de nuevo no cambia nada

Aplica el mismo archivo otra vez:

```bash
kubectl apply -f ~/k8s-intro/manifests/namespace-laboratorio-k8s.yaml
```

**Observa:** ahora el resultado es `namespace/laboratorio-k8s unchanged`. Aplicar un manifiesto cuyo contenido ya coincide con el estado real no produce cambios. A esta propiedad se le llama **idempotencia** y es la razón por la que `apply` se puede repetir sin riesgo.

### 4.2. Previsualizar y aplicar un cambio

Agrega una etiqueta a tu manifiesto:

```bash
nano ~/k8s-intro/manifests/namespace-laboratorio-k8s.yaml
```

Añade una línea bajo `labels:`, con la misma sangría que las demás:

```yaml
    responsable: estudiante
```

Antes de aplicar, mira qué cambiaría:

```bash
kubectl diff -f ~/k8s-intro/manifests/namespace-laboratorio-k8s.yaml
```

**Observa:** `kubectl diff` muestra las diferencias entre tu archivo y el clúster, y **no modifica nada**. Las líneas con `+` son las que se añadirán. Es normal que `diff` termine con código de salida 1 cuando hay diferencias.

Aplica el cambio y verifícalo:

```bash
kubectl apply -f ~/k8s-intro/manifests/namespace-laboratorio-k8s.yaml
kubectl get namespace laboratorio-k8s --show-labels
```

**Observa:** el resultado de `apply` es `configured` y la nueva etiqueta aparece en la lista.

### 4.3. Seleccionar recursos por etiqueta

Usa las etiquetas como en el capítulo 3:

```bash
kubectl get namespaces -l curso=kubernetes-introduccion
kubectl get namespaces -l entorno=laboratorio --show-labels
```

**Observa:** solo aparece `laboratorio-k8s`. Un selector filtra recursos por sus etiquetas; es el mismo mecanismo que usará un `Service` para encontrar Pods.

**Responde antes de continuar:**

1. ¿Por qué el segundo `apply` informó `unchanged`?
2. ¿Qué hizo `kubectl diff` y qué no hizo?
3. ¿Qué etiqueta añadió Kubernetes automáticamente al namespace?

## 5. Inspeccionar el estado inicial del namespace

Consulta lo que contiene un namespace recién creado y guarda la evidencia:

```bash
kubectl get all,configmap,secret -n laboratorio-k8s \
  | tee ~/k8s-intro/analisis/recursos-iniciales-laboratorio-k8s.txt
kubectl get serviceaccount -n laboratorio-k8s
```

**Observa:**

- `get all` no muestra Pods, Deployments ni Services: todavía no hay ninguna aplicación.
- Sí aparece el ConfigMap `kube-root-ca.crt`, que Kubernetes crea automáticamente en cada namespace.
- También existe la cuenta de servicio `default`. La usarás como punto de partida en el capítulo 10.
- Un namespace "vacío" no está del todo vacío: Kubernetes crea algunos objetos de apoyo.

## 6. Documentar las capacidades identificadas

Crea el informe con una plantilla. El nombre de cada recurso ya está escrito; **tú completas** el ámbito, el comando que lo demuestra y las filas de tu matriz del capítulo 3 con las que se relaciona:

```bash
cat > ~/k8s-intro/analisis/capacidades-kubernetes.md <<'EOF'
# Capacidades de Kubernetes identificadas

**Contexto verificado:** `minikube`
**Namespace de trabajo:** `laboratorio-k8s`
**Fecha de análisis:** FECHA_AQUI

## Recursos disponibles en la API

| Recurso | Ámbito (clúster o namespace) | Comando que lo demuestra | Filas N del capítulo 3 relacionadas |
|---|---|---|---|
| Pod | COMPLETAR | COMPLETAR | COMPLETAR |
| Deployment | COMPLETAR | COMPLETAR | COMPLETAR |
| Service | COMPLETAR | COMPLETAR | COMPLETAR |
| ConfigMap | COMPLETAR | COMPLETAR | COMPLETAR |
| Secret | COMPLETAR | COMPLETAR | COMPLETAR |
| Namespace | COMPLETAR | COMPLETAR | COMPLETAR |

## Relación con la matriz de necesidades

COMPLETAR: explica en 3 a 5 líneas cómo la API del clúster confirma las necesidades que identificaste en el capítulo 3. Indica una necesidad de la matriz que todavía NO puedes demostrar con lo visto hasta ahora.

## Lo que esta práctica no demuestra

COMPLETAR: escribe al menos dos cosas que no se pueden concluir solo porque la API ofrezca un recurso (por ejemplo, que ya exista una aplicación o que se apliquen controles de seguridad).

## Evidencias

- `api-resources-filtrados.txt`: recursos filtrados desde la API.
- `recursos-iniciales-laboratorio-k8s.txt`: estado inicial del namespace.
- `namespace-laboratorio-k8s.yaml`: manifiesto aplicado.
EOF
sed -i "s/FECHA_AQUI/$(date +%F)/" ~/k8s-intro/analisis/capacidades-kubernetes.md
```

Abre el archivo y reemplaza cada `COMPLETAR` con tus conclusiones:

```bash
nano ~/k8s-intro/analisis/capacidades-kubernetes.md
```

**Sugerencias:**

- En `nano`, usa `Ctrl+W`, escribe `COMPLETAR` y presiona Enter para saltar al siguiente pendiente.
- Para la columna "Ámbito", apóyate en `~/k8s-intro/analisis/api-resources-filtrados.txt`.
- Para las filas N, consulta tu archivo del capítulo 3:

  ```bash
  grep '^| N' ~/k8s-intro/analisis/necesidades-orquestacion.md
  ```

- No afirmes nada que no hayas visto en la terminal.

## 7. Verificar el resultado

Comprueba los tres archivos de evidencia:

```bash
ls -l \
  ~/k8s-intro/manifests/namespace-laboratorio-k8s.yaml \
  ~/k8s-intro/analisis/api-resources-filtrados.txt \
  ~/k8s-intro/analisis/recursos-iniciales-laboratorio-k8s.txt \
  ~/k8s-intro/analisis/capacidades-kubernetes.md
```

Comprueba que no quedan marcadores pendientes y que se mencionan los seis recursos:

```bash
grep -nE 'COMPLETAR|FECHA_AQUI' ~/k8s-intro/analisis/capacidades-kubernetes.md \
  || echo "OK: no quedan marcadores pendientes"

for r in Pod Deployment Service ConfigMap Secret Namespace; do
  grep -qw "$r" ~/k8s-intro/analisis/capacidades-kubernetes.md \
    && echo "OK     $r" || echo "FALTA  $r"
done
```

Comprueba el estado del clúster y del namespace:

```bash
kubectl config current-context
kubectl get nodes
kubectl get namespace laboratorio-k8s --show-labels
kubectl get namespace laboratorio-k8s -o jsonpath='{.status.phase}{"\n"}'
```

**Observa:** el contexto es `minikube`, el nodo está `Ready`, el namespace aparece con las etiquetas `curso`, `entorno` y `responsable`, y la fase es `Active`.

## 8. Criterios de finalización

El laboratorio está completo cuando puedes demostrar que:

- [ ] Confirmaste el contexto `minikube`, el nodo `Ready` y las versiones `v1.31.0`.
- [ ] Identificaste con `kubectl api-resources` los seis recursos y su ámbito.
- [ ] Usaste `kubectl explain` para consultar campos de recursos.
- [ ] Exploraste `kube-system` en modo lectura sin modificar nada.
- [ ] Creaste el namespace `laboratorio-k8s` con un manifiesto y `kubectl apply`.
- [ ] Observaste los resultados `created`, `unchanged` y `configured`.
- [ ] Usaste `kubectl diff` para previsualizar un cambio.
- [ ] Explicaste que el namespace contiene objetos de apoyo creados por Kubernetes.
- [ ] Completaste `capacidades-kubernetes.md` con tus propias conclusiones.

## 9. Preguntas de cierre

Discute tus respuestas con el instructor o con otro estudiante:

1. ¿Qué ventaja tiene guardar el namespace en un archivo YAML en lugar de crearlo con un comando suelto?
2. ¿Qué diferencia hay entre estado deseado y estado real, y dónde los viste en esta práctica?
3. ¿Por qué es útil ejecutar `kubectl diff` antes de `kubectl apply`?
4. ¿Por qué se trabaja en `laboratorio-k8s` y no en `default` ni en `kube-system`?
5. ¿Qué necesidades de tu matriz del capítulo 3 comprobarás con recursos reales en los capítulos siguientes?

## Solución de problemas

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| El contexto no es `minikube` | `kubectl` apunta a otro clúster. | `kubectl config use-context minikube` y verifica de nuevo. |
| `kubectl get nodes` muestra `NotReady` o error de conexión | Minikube o Docker están detenidos. | `minikube status -p minikube`; luego `minikube start -p minikube`. No elimines el clúster como primer intento. |
| `kubectl apply` falla con `error parsing` o `error converting YAML to JSON` | Sangría incorrecta en el YAML. | Revisa el archivo con `cat`. Cada nivel usa dos espacios; no uses tabuladores. |
| `kubectl apply` dice que el archivo no existe | Ruta o nombre incorrectos. | `ls -l ~/k8s-intro/manifests/` y corrige la ruta. |
| `kubectl diff` no muestra nada tras editar | No guardaste el archivo o no se añadió la etiqueta. | Reabre con `nano`, guarda con `Ctrl+O`, Enter, y repite. |
| El conteo de `grep` no muestra los seis recursos | `api-resources-filtrados.txt` está incompleto. | Repite el comando de la sección 2 con `tee`. |

## Limpieza

**No elimines el namespace `laboratorio-k8s`.** Es el estado persistente que usarán todas las prácticas siguientes. Conserva también los archivos de evidencia:

```bash
find ~/k8s-intro -maxdepth 2 -type f | sort
```

No ejecutes durante este curso, salvo que el instructor lo indique:

```bash
kubectl delete namespace laboratorio-k8s
kubectl delete namespace kube-system
minikube delete
```

## Resultado esperado

Al finalizar, tendrás el namespace `laboratorio-k8s` creado de forma declarativa y versionable, evidencias de los recursos que expone la API de tu clúster y un informe que los relaciona con la matriz del capítulo 3. También habrás practicado el ciclo básico de trabajo declarativo: escribir un manifiesto, previsualizar con `diff`, aplicar y verificar.

El objetivo no es memorizar la lista de recursos, sino aprender a consultar la API para comprobar qué ofrece el clúster, distinguir lo que está disponible de lo que realmente existe y trabajar de forma ordenada dentro de un namespace propio.

---

## Apéndice para autoevaluación

Consulta esta sección solo después de intentar tus propias respuestas.

<details>
<summary>Respuestas a las preguntas intermedias</summary>

**Sección 2**

1. `Deployment` vive en el grupo `apps` (`apps/v1`); `Pod` vive en el grupo principal (`v1`).
2. Porque un `Namespace` es un recurso de clúster: organiza otros recursos y no pertenece a ningún namespace.
3. Que la API ofrezca `Deployment` solo significa que puedes crear uno. Hasta que lo crees, no existe ninguna instancia.

**Sección 4**

1. Porque el contenido del archivo ya coincidía con el estado real del clúster (idempotencia).
2. Mostró las diferencias entre el archivo y el clúster. No modificó nada.
3. `kubernetes.io/metadata.name`, con el nombre del namespace.

</details>

<details>
<summary>Tabla de referencia para capacidades-kubernetes.md</summary>

| Recurso | Ámbito | Comando que lo demuestra | Filas N relacionadas |
|---|---|---|---|
| Pod | Namespace | `kubectl api-resources` (`NAMESPACED` = `true`) | N8 |
| Deployment | Namespace | `kubectl api-resources --api-group=apps` | N1, N2 |
| Service | Namespace | `kubectl api-resources` | N3 |
| ConfigMap | Namespace | `kubectl api-resources` | N4 |
| Secret | Namespace | `kubectl api-resources` | N5 |
| Namespace | Clúster | `kubectl api-resources --namespaced=false` | N6 |

La fila N7 (labels y selectors) se practicó con `kubectl get namespaces -l ...`, aunque todavía no con Pods y Services. Las filas N9 (`PersistentVolumeClaim`) y N10 (RBAC) todavía no se han demostrado con recursos reales; se practicarán en capítulos posteriores.

</details>