# Capítulo 3 — Reconocimiento de necesidades de orquestación

## Propósito del laboratorio

Relacionar los problemas operativos de una aplicación monolítica con capacidades concretas de Kubernetes. Partirás del análisis del capítulo 2, compararás la ejecución manual de un contenedor con la gestión declarativa y construirás una matriz que asocia cada necesidad con el recurso de Kubernetes que ayuda a resolverla, y también con lo que ese recurso **no** resuelve.

La práctica es de análisis y uso de la terminal. **No se desplegará ninguna aplicación.** Usarás:

- `kubectl create ... --dry-run=client`, que genera el YAML de un recurso **sin enviarlo al clúster**.
- `kubectl explain` y `kubectl api-resources`, que consultan la API de Kubernetes sin modificarla.

Los hallazgos se guardarán en `~/k8s-intro/analisis/necesidades-orquestacion.md` para reutilizarlos en el capítulo 4.

Al finalizar, podrás:

- Identificar qué debe hacer manualmente un operador que ejecuta contenedores con `docker run`.
- Leer un manifiesto de Kubernetes y localizar campos clave: réplicas, imagen, labels, selector y puertos.
- Explicar cómo un `Service` encuentra los Pods mediante labels y selectors.
- Diferenciar `ConfigMap` y `Secret`, y explicar por qué base64 no es cifrado.
- Asociar cada necesidad de la aplicación con el recurso de Kubernetes adecuado.
- Reconocer qué problemas no se resuelven solo con Kubernetes.
- Documentar el resultado con evidencia que puedas verificar.

**Duración orientativa:** 25–30 minutos, dependiendo del tiempo de análisis y discusión.

## Prerrequisitos

- Haber completado los laboratorios de los capítulos 1 y 2.
- Tener el archivo `~/k8s-intro/analisis/monolito.md` creado en el capítulo 2.
- Tener acceso a una terminal Bash y a `kubectl` con el contexto `minikube`.
- Conocer a nivel introductorio los conceptos `Pod`, `Deployment`, `Service`, `ConfigMap`, `Secret`, `Namespace`, labels y selectors. Se reforzarán durante la práctica.

En esta práctica no necesitas crear Pods, Deployments, Services ni otros recursos en el clúster.

## 1. Comprobar el entorno y recuperar el análisis previo

Verifica que el clúster sigue accesible:

```bash
kubectl config current-context
minikube status -p minikube
```

El contexto esperado es `minikube`. Los componentes principales de Minikube deben estar en estado operativo.

Comprueba que existe tu análisis del capítulo anterior y prepara el directorio de trabajo:

```bash
mkdir -p ~/k8s-intro/analisis
ls -l ~/k8s-intro/analisis/monolito.md
cd ~/k8s-intro/analisis
pwd
```

Si el archivo no existe, revisa la sección **Solución de problemas** al final de esta práctica. No inventes observaciones como si provinieran del capítulo 2.

Recupera del informe las líneas que hablan de los problemas operativos:

```bash
grep -inE 'instancia|disponibilidad|escalado|actualiz|DB_PASSWORD|balanceador' \
  ~/k8s-intro/analisis/monolito.md
```

**Observa:** las líneas que aparecen son tus propias conclusiones del capítulo 2. Son la materia prima de esta práctica.

## 2. Recordar los problemas de `tienda-monolito`

En el capítulo 2 analizaste `tienda-monolito`: una aplicación de comercio electrónico con una sola imagen, un solo proceso, una sola instancia y el puerto TCP `8080`. Estos son los problemas que usarás en esta práctica. Distingue entre lo que el caso **afirma** y lo que tú **infieres**:

| ID | Problema | Origen |
|---|---|---|
| P1 | Existe una sola instancia: si falla, la tienda deja de atender solicitudes. | Descrito en el caso |
| P2 | Para actualizar se detiene la instancia anterior y luego se inicia la nueva: hay indisponibilidad. | Descrito en el caso |
| P3 | Para escalar el catálogo hay que crear instancias completas de la aplicación, una por una. | Descrito en el caso |
| P4 | Hay ocho variables de configuración, entre ellas `DB_PASSWORD`, que es información sensible. | Descrito en el caso |
| P5 | No hay balanceador de carga ni una dirección estable para llegar a las instancias. | Descrito en el caso |
| P6 | No hay separación entre entornos o equipos (por ejemplo, pruebas y producción). | **Inferido** (hipótesis) |
| P7 | Si la aplicación escribiera archivos locales, se perderían al recrear el contenedor. | **Inferido** (hipótesis) |

Una inferencia no es un hecho. Más adelante registrarás las hipótesis como hipótesis, no como conclusiones.

**Responde antes de continuar:**

1. ¿Cuáles de los problemas P1 a P7 están descritos directamente en el caso y cuáles son inferencias?
2. ¿Qué riesgo implica que `DB_PASSWORD` se escriba en el comando con el que se inicia la aplicación?

## 3. Ejecución manual: ¿qué hace el operador?

Para entender qué aporta un orquestador, primero observa lo que implica ejecutar la aplicación a mano. Crea un archivo de texto con el comando que se usaría para iniciar `tienda-monolito` con Docker:

```bash
cat > ~/k8s-intro/analisis/comando-manual.txt <<'EOF'
docker run -d --name tienda-monolito \
  -p 8080:8080 \
  -e DB_HOST=db.ejemplo.local -e DB_PORT=5432 -e DB_NAME=tienda \
  -e DB_USER=tienda_app -e DB_PASSWORD=valor-de-ejemplo \
  -e PAYMENTS_URL=https://pagos.ejemplo.local \
  -e SMTP_HOST=smtp.ejemplo.local -e LOG_LEVEL=info \
  tienda-monolito:1.0
EOF
```

**Importante:** el comando está en un archivo de texto y **no se ejecuta**. La imagen `tienda-monolito:1.0` es solo un ejemplo ilustrativo.

Analiza el comando con la terminal:

```bash
cat ~/k8s-intro/analisis/comando-manual.txt
grep -o -- '-e [A-Z_]*' ~/k8s-intro/analisis/comando-manual.txt | wc -l
grep -n 'DB_PASSWORD' ~/k8s-intro/analisis/comando-manual.txt
grep -n -- '-p ' ~/k8s-intro/analisis/comando-manual.txt
```

**Observa:**

- El segundo comando cuenta las variables pasadas con `-e`.
- La contraseña queda escrita en texto plano dentro del comando, del historial de la terminal y de cualquier script que lo contenga.
- `-p 8080:8080` publica el puerto `8080` del servidor (host). Un mismo host solo puede usar ese puerto una vez.

**Responde antes de continuar:**

1. ¿Cuántas variables de configuración se pasan con `-e`?
2. ¿Dónde queda visible `DB_PASSWORD`?
3. Si el catálogo necesita tres instancias, ¿qué pasa al repetir este mismo comando en el mismo host?

Resume lo que el operador debe resolver por su cuenta:

| Situación | Con `docker run` manual | Con Kubernetes (declarativo) |
|---|---|---|
| Se necesitan más instancias | Repetir el comando cambiando nombres y puertos. | Se declara el número de réplicas. |
| Una instancia falla | Docker puede reiniciarla en el mismo host con `--restart`, pero no la reprograma en otro servidor ni mantiene un número de réplicas coordinado. | Un controlador compara el estado actual con el declarado e intenta corregir la diferencia. |
| Cambian las instancias | Quien llama a la aplicación debe conocer la nueva dirección o puerto. | Un `Service` ofrece una dirección estable. |
| Configuración y credenciales | Van en el comando o en archivos del host. | `ConfigMap` y `Secret` las separan de la imagen. |
| Localizar las instancias de una aplicación | Depende de convenciones de nombres. | Labels y selectors las agrupan. |

Kubernetes **no reemplaza** el proceso de construir, probar y publicar la imagen: sigue consumiendo una imagen versionada y declara cómo y cuántas veces ejecutarla.

## 4. Gestión declarativa: ver el estado deseado sin desplegar nada

Ahora generarás los manifiestos equivalentes. La opción `--dry-run=client` produce el YAML localmente y **no crea nada en el clúster**.

Crea un directorio para los ejemplos:

```bash
mkdir -p ~/k8s-intro/analisis/dry-run
cd ~/k8s-intro/analisis/dry-run
```

Genera los manifiestos:

```bash
kubectl create namespace laboratorio-k8s --dry-run=client -o yaml > namespace.yaml

kubectl create configmap tienda-config \
  --from-literal=LOG_LEVEL=info \
  --from-literal=DB_PORT=5432 \
  --dry-run=client -o yaml > configmap.yaml

kubectl create secret generic tienda-db \
  --from-literal=DB_PASSWORD=valor-de-ejemplo \
  --dry-run=client -o yaml > secret.yaml

kubectl create deployment tienda-monolito \
  --image=nginx:1.27.4-alpine --replicas=3 --port=8080 \
  --dry-run=client -o yaml > deployment.yaml

kubectl create service clusterip tienda-monolito \
  --tcp=8080:8080 \
  --dry-run=client -o yaml > service.yaml

kubectl run tienda-pod \
  --image=nginx:1.27.4-alpine --port=8080 \
  --dry-run=client -o yaml > pod.yaml

ls -l
```

**Observa:** la imagen `nginx:1.27.4-alpine` se usa solo como imagen de ejemplo para obtener un manifiesto válido. Aquí no se ejecuta ningún contenedor. Debes ver seis archivos `.yaml`.

### 4.1. Deployment: estado deseado y réplicas

```bash
cat deployment.yaml
grep -nE 'replicas|app: |image:|containerPort' deployment.yaml
```

**Observa:**

- `replicas: 3` es el estado deseado: tres instancias.
- `image:` indica la imagen versionada que se usará.
- `app: tienda-monolito` aparece como label del recurso, en `matchLabels` y en la plantilla del Pod.
- La sección `template` contiene la descripción del Pod que el Deployment creará y mantendrá.

### 4.2. Pod: la unidad mínima

```bash
cat pod.yaml
grep -nE 'containers:|image:|run:' pod.yaml
grep -c replicas pod.yaml
```

**Observa:** el último comando devuelve `0`. Un Pod es una sola instancia y no tiene campo de réplicas. Quien mantiene un número de Pods es un controlador como `Deployment`. Compara la sección `containers:` de `pod.yaml` con la de `deployment.yaml`: la descripción del contenedor es la misma, pero en el Deployment queda dentro de `template`.

### 4.3. Service: dirección estable y selector

```bash
cat service.yaml
grep -nE 'app:|port|selector' service.yaml
```

**Observa:** el `Service` no conoce nombres de Pods. Utiliza `selector: app: tienda-monolito` para encontrar los Pods que tengan esa label, la misma que el Deployment asigna a su plantilla de Pod. Si los Pods se reemplazan, el Service sigue seleccionando los que cumplan la label.

Compara ambas etiquetas de forma directa:

```bash
grep -n 'app: tienda-monolito' deployment.yaml service.yaml
```

### 4.4. ConfigMap: configuración que no es sensible

```bash
cat configmap.yaml
```

**Observa:** en `data:` aparecen `LOG_LEVEL` y `DB_PORT` como texto legible. Son valores de configuración sin riesgo; no deben alojar contraseñas.

### 4.5. Secret: dato sensible, pero no cifrado

```bash
cat secret.yaml
grep DB_PASSWORD secret.yaml | awk '{print $2}' | base64 -d; echo
```

**Observa:** el valor guardado en el `Secret` no se ve a simple vista, pero el segundo comando lo recupera con `base64 -d`. Base64 es una **codificación reversible**, no cifrado. Un `Secret` separa la credencial de la imagen y del comando de ejecución, pero por sí solo no la protege por completo.

### 4.6. Namespace: separación lógica

```bash
cat namespace.yaml
```

**Observa:** el manifiesto solo declara un nombre. Un `Namespace` agrupa y delimita nombres de recursos. Se utilizará en prácticas posteriores; no uses `kube-system` para aplicaciones del curso.

### 4.7. Confirmar que no se creó nada en el clúster

```bash
kubectl get deployments,services,configmaps,secrets -A | grep tienda \
  || echo "OK: no existe ningún recurso 'tienda' en el clúster"
kubectl get namespace laboratorio-k8s 2>&1 | tail -n 1
```

**Observa:** el primer comando debe imprimir el mensaje `OK`. El segundo debe indicar que el namespace `laboratorio-k8s` no existe todavía (`NotFound`). Eso demuestra que `--dry-run=client` solo generó archivos locales. Estos YAML son para leer; no los apliques con `kubectl apply`, eso se practicará en capítulos posteriores.

**Responde antes de continuar:**

1. ¿Qué campo del `Deployment` define cuántas instancias se desean?
2. ¿Qué label comparten el `Deployment` y el `Service`, y para qué sirve?
3. ¿Por qué `pod.yaml` no tiene réplicas?
4. ¿El valor de `DB_PASSWORD` en `secret.yaml` está cifrado?
5. ¿Qué comprobaste para saber que no se creó nada en el clúster?

## 5. Consultar la API: capacidades para actualizar, almacenar y autorizar

Algunas necesidades se ven mejor consultando la propia API del clúster. Comprueba que existen los recursos que usarás en la matriz:

```bash
kubectl api-resources --namespaced=true \
  | grep -E '^(NAME|pods|deployments|services|configmaps|secrets|persistentvolumeclaims|serviceaccounts|roles|rolebindings) '
kubectl api-resources --namespaced=false | grep -E '^(NAME|namespaces) '
```

**Observa:**

- La columna `NAMESPACED` es `true` para los recursos que viven dentro de un namespace.
- `namespaces` aparece con `false`: el propio Namespace no pertenece a otro namespace.

Consulta cómo se actualiza un Deployment y qué campos tienen el almacenamiento y los permisos:

```bash
kubectl explain deployment.spec.strategy.type
kubectl explain persistentvolumeclaim.spec.accessModes
kubectl explain persistentvolumeclaim.spec.resources
kubectl explain role.rules
kubectl explain rolebinding.subjects
```

**Observa:**

- `deployment.spec.strategy.type` indica las estrategias de actualización (`RollingUpdate` y `Recreate`). `RollingUpdate` reemplaza los Pods gradualmente; esta idea responde al problema P2.
- `PersistentVolumeClaim` solicita almacenamiento mediante `accessModes` y `resources`; responde al problema P7.
- `Role` define reglas de permisos y `RoleBinding` los asigna a identidades (`subjects`).

Guarda en tu cuaderno el nombre del campo que mejor demuestra cada recurso. Los usarás en la matriz.

## 6. Construir la matriz de necesidades

Crea el informe con una plantilla. La necesidad de cada fila ya está redactada; **tú debes completar** el recurso, el campo o comando que lo demuestra y su límite. La fila `N1` está resuelta como ejemplo:

```bash
cat > ~/k8s-intro/analisis/necesidades-orquestacion.md <<'EOF'
# Necesidades de orquestación de tienda-monolito

**Fuente analizada:** `~/k8s-intro/analisis/monolito.md`
**Fecha de análisis:** FECHA_AQUI
**Clúster de contraste:** Kubernetes v1.31.0 en Minikube

## Diferencia entre ejecución manual y gestión declarativa

COMPLETAR: explica con tus palabras, en 3 a 5 líneas, qué debe hacer el operador con `docker run` y qué cambia al declarar el estado deseado en Kubernetes. Incluye un ejemplo observado en `deployment.yaml` o `service.yaml`.

## Matriz de necesidades y recursos candidatos

| ID | Necesidad operativa (problema relacionado) | Recurso candidato | Campo o comando que lo demuestra | Qué NO resuelve por sí solo |
|---|---|---|---|---|
| N1 | Mantener tres instancias y reemplazar las que fallen (P1, P3) | `Deployment` | `replicas: 3` en `deployment.yaml` | Errores funcionales de la aplicación ni una imagen defectuosa |
| N2 | Publicar una versión nueva sin detener todo el servicio (P2) | COMPLETAR | COMPLETAR | COMPLETAR |
| N3 | Llegar a la aplicación con una dirección estable aunque cambien las instancias (P5) | COMPLETAR | COMPLETAR | COMPLETAR |
| N4 | Sacar la configuración no sensible (`LOG_LEVEL`, `DB_PORT`) del comando de ejecución (P4) | COMPLETAR | COMPLETAR | COMPLETAR |
| N5 | Proteger `DB_PASSWORD` fuera de la imagen y del comando (P4) | COMPLETAR | COMPLETAR | COMPLETAR |
| N6 | Separar entornos o equipos dentro del mismo clúster (P6) | COMPLETAR | COMPLETAR | COMPLETAR |
| N7 | Agrupar y localizar las instancias que pertenecen a una aplicación (P5) | COMPLETAR | COMPLETAR | COMPLETAR |
| N8 | Ejecutar el contenedor de la aplicación como unidad mínima de despliegue (P1) | COMPLETAR | COMPLETAR | COMPLETAR |
| N9 | Conservar archivos generados al recrear el Pod (P7) | COMPLETAR | COMPLETAR | COMPLETAR |
| N10 | Dar a una identidad solo los permisos mínimos que necesita sobre la API | COMPLETAR | COMPLETAR | COMPLETAR |

## Necesidades fuera del alcance exclusivo de Kubernetes

COMPLETAR: escribe al menos tres problemas de un monolito que Kubernetes no corrige por sí solo.

## Hipótesis por validar

COMPLETAR: anota al menos una suposición que no puedas confirmar con el caso y cómo la comprobarías.
EOF
```

Escribe la fecha real del laboratorio:

```bash
sed -i "s/FECHA_AQUI/$(date +%F)/" ~/k8s-intro/analisis/necesidades-orquestacion.md
```

Abre el archivo y sustituye cada `COMPLETAR` por tus conclusiones:

```bash
nano ~/k8s-intro/analisis/necesidades-orquestacion.md
```

**Sugerencias de edición:**

- En `nano`, usa `Ctrl+W`, escribe `COMPLETAR` y presiona Enter para saltar al siguiente pendiente.
- Conserva las barras `|` y no cambies los identificadores `N1` a `N10`.
- Las columnas "Campo o comando que lo demuestra" deben apoyarse en lo que observaste en las secciones 4 y 5.
- Para "Qué NO resuelve por sí solo", piensa qué seguirá fallando aunque el recurso esté bien configurado.

**Reglas del análisis:**

- No inventes capacidades que no hayas validado. Por ejemplo, un `Secret` no vuelve segura una aplicación, un `Service` no publica necesariamente fuera del clúster y un `Namespace` no implementa por sí solo aislamiento de red.
- Presenta las suposiciones como hipótesis, no como hechos.
- Guarda los cambios y sal del editor (`Ctrl+O`, Enter, `Ctrl+X`).

## 7. Verificar el resultado

Comprueba que el archivo existe y no está vacío:

```bash
test -s ~/k8s-intro/analisis/necesidades-orquestacion.md \
  && echo "OK: informe creado y no vacío"
```

Comprueba que no quedaron marcadores sin completar:

```bash
grep -nE 'COMPLETAR|FECHA_AQUI' ~/k8s-intro/analisis/necesidades-orquestacion.md \
  || echo "OK: no quedan marcadores pendientes"
```

Si el comando muestra líneas, esas son las que aún debes completar.

Cuenta las filas de la matriz y revisa los encabezados:

```bash
echo "Filas de la matriz: $(grep -c '^| N[0-9]' ~/k8s-intro/analisis/necesidades-orquestacion.md)"
grep '^## ' ~/k8s-intro/analisis/necesidades-orquestacion.md
```

Debe indicar `10` filas y mostrar las secciones del informe.

Verifica que mencionaste los recursos principales:

```bash
for r in Deployment Pod Service ConfigMap Secret Namespace PersistentVolumeClaim ServiceAccount Role RoleBinding; do
  grep -qw "$r" ~/k8s-intro/analisis/necesidades-orquestacion.md \
    && echo "OK     $r" || echo "FALTA  $r"
done
grep -qi 'selector' ~/k8s-intro/analisis/necesidades-orquestacion.md \
  && echo "OK     labels y selectors" || echo "FALTA  labels y selectors"
```

Verifica que el informe documenta límites:

```bash
grep -inE 'diseño|datos|respaldo|copias de seguridad|pruebas' \
  ~/k8s-intro/analisis/necesidades-orquestacion.md
```

Finalmente, confirma que el clúster sigue accesible y sin recursos nuevos:

```bash
kubectl get nodes
kubectl get deployments,services,configmaps,secrets -A | grep tienda \
  || echo "OK: no se creó ningún recurso de la aplicación"
```

**Importante:** el informe debe contener tus conclusiones, no solo la plantilla. Si dudas de una afirmación, verifícala con `kubectl explain` o con los YAML generados.

## 8. Criterios de finalización

El laboratorio está completo cuando puedes demostrar que:

- [ ] Distinguiste los problemas descritos en el caso de los inferidos.
- [ ] Explicaste qué debe resolver manualmente un operador con `docker run`.
- [ ] Generaste y leíste los manifiestos de `Deployment`, `Pod`, `Service`, `ConfigMap`, `Secret` y `Namespace` con `--dry-run=client`.
- [ ] Explicaste cómo el `Service` selecciona Pods mediante labels y selectors.
- [ ] Recuperaste el valor del `Secret` con `base64 -d` y explicaste por qué no es cifrado.
- [ ] Consultaste con `kubectl explain` los campos de estrategia de actualización, almacenamiento y permisos.
- [ ] Completaste las diez filas de la matriz en `~/k8s-intro/analisis/necesidades-orquestacion.md`.
- [ ] Documentaste al menos tres límites de Kubernetes y una hipótesis por validar.
- [ ] Confirmaste que el clúster sigue accesible y que no se desplegaron recursos de aplicación.

## 9. Preguntas de cierre

Discute tus respuestas con el instructor o con otro estudiante:

1. ¿Qué diferencia existe entre indicar cómo iniciar una instancia y declarar el estado deseado de una aplicación?
2. ¿Por qué un `Service` no necesita conocer los nombres de los Pods a los que envía tráfico?
3. ¿Qué haría falta, además de usar un `Secret`, para proteger de verdad una credencial?
4. Menciona dos problemas del monolito que Kubernetes no resuelve por sí solo y explica por qué.
5. ¿Qué filas de tu matriz te gustaría comprobar con recursos reales en los capítulos siguientes?

## Solución de problemas

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| `monolito.md` no existe o `Permission denied` | No se completó el capítulo 2 o se usó otro directorio. | Ejecuta `find ~/k8s-intro -name monolito.md -type f`. Si lo encuentras, cópialo a `~/k8s-intro/analisis/`. Si no existe, completa primero el capítulo 2. |
| `kubectl config current-context` no devuelve `minikube` | Se seleccionó otro clúster. | Ejecuta `kubectl config use-context minikube` y verifica de nuevo. |
| `minikube status` muestra componentes detenidos o `kubectl explain` indica que no puede conectarse | El clúster está detenido. | Ejecuta `minikube start -p minikube`. No elimines ni recrees el clúster como primer intento. |
| `base64: invalid input` | El valor copiado está incompleto. | Usa exactamente el comando de la sección 4.5, que extrae el valor con `awk`. |
| El conteo de filas no es `10` | Se modificó el formato de la tabla. | Cada fila debe comenzar con `\| N1`, `\| N2`, ..., `\| N10`. |
| Siguen apareciendo líneas con `COMPLETAR` | Quedan celdas sin completar. | Usa el comando de la sección 7 para localizar las líneas pendientes. |

## Limpieza

Esta práctica no crea Pods, Deployments, Services ni otros recursos en el clúster, así que no hay nada que eliminar de Kubernetes.

Conserva estos archivos, porque se usarán más adelante:

```text
~/k8s-intro/analisis/monolito.md
~/k8s-intro/analisis/necesidades-orquestacion.md
~/k8s-intro/analisis/dry-run/
```

El directorio `dry-run/` contiene ejemplos para consultar. No los apliques al clúster todavía.

## Resultado esperado

Al finalizar, tendrás una matriz de diez necesidades de orquestación, cada una asociada con un recurso de Kubernetes, con evidencia observada en la terminal y con el límite de lo que ese recurso no resuelve. También tendrás un conjunto de manifiestos de ejemplo que muestran cómo se expresa en YAML el estado deseado de la aplicación. Estos documentos servirán como entrada para el capítulo 4, donde contrastarás esta matriz con las capacidades reales del clúster.

El objetivo no es concluir que Kubernetes resuelve todos los problemas de una aplicación monolítica. El objetivo es reconocer qué necesidades cubre cada recurso, qué necesidades siguen dependiendo del diseño de la aplicación y de decisiones humanas, y usar esa información para tomar decisiones técnicas fundamentadas.

---

## Apéndice para autoevaluación

Consulta esta sección solo después de intentar tus propias respuestas.

<details>
<summary>Respuestas a las preguntas intermedias</summary>

**Sección 2**

1. Descritos en el caso: P1 a P5. Inferidos: P6 y P7.
2. Queda en texto plano en el comando, en el historial de la terminal y en cualquier script o registro que lo contenga.

**Sección 3**

1. Ocho variables.
2. En el comando, en el historial de la terminal y en cualquier archivo que lo contenga.
3. El segundo contenedor intentaría usar de nuevo el puerto `8080` del host y fallaría por conflicto de puerto; habría que cambiar nombres y puertos manualmente.

**Sección 4**

1. `spec.replicas` (`replicas: 3`).
2. `app: tienda-monolito`. El `Deployment` la asigna a los Pods y el `Service` la usa en su `selector` para encontrarlos.
3. Un Pod es una sola instancia. Las réplicas las gestiona un controlador como `Deployment`.
4. No. Está codificado en base64, que se revierte con `base64 -d`.
5. Que `kubectl get ... | grep tienda` no devolvió resultados y que el namespace `laboratorio-k8s` no existe.

</details>

<details>
<summary>Matriz de referencia (N2 a N10)</summary>

| ID | Recurso | Campo o comando de ejemplo | Qué no resuelve por sí solo |
|---|---|---|---|
| N2 | `Deployment` (estrategia `RollingUpdate`) | `kubectl explain deployment.spec.strategy.type` | Una imagen defectuosa o un cambio incompatible con la base de datos. |
| N3 | `Service` | `selector` y `ports` en `service.yaml` | Exponer la aplicación fuera del clúster por sí mismo; el diseño de la API. |
| N4 | `ConfigMap` | `data:` en `configmap.yaml` | Proteger contraseñas, tokens o claves privadas. |
| N5 | `Secret` | `base64 -d` sobre `secret.yaml` | Cifrado completo, rotación automática o una política de gestión de secretos. |
| N6 | `Namespace` | `namespace.yaml` y `kubectl api-resources --namespaced=false` | Aislamiento de red o seguridad completa. |
| N7 | Labels y selectors | `app: tienda-monolito` en `deployment.yaml` y `service.yaml` | Una taxonomía útil si las etiquetas son ambiguas o inconsistentes. |
| N8 | `Pod` | `containers:` en `pod.yaml` | Réplicas o recreación automática por sí solo; para eso se usa un `Deployment`. |
| N9 | `PersistentVolumeClaim` | `kubectl explain persistentvolumeclaim.spec.resources` | Respaldos, consistencia, retención y estrategia de recuperación de datos. |
| N10 | `ServiceAccount`, `Role` y `RoleBinding` | `kubectl explain role.rules` | Autenticación corporativa, revisión de privilegios o seguridad del código de la aplicación. |

</details>