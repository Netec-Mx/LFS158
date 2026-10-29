# Capítulo 2 — Análisis de una aplicación monolítica

## Propósito del laboratorio

Aplicar los conceptos de arquitectura monolítica a un caso práctico. El estudiante analizará una aplicación de comercio electrónico, identificará sus componentes, configuración, dependencias y puertos, y explicará las implicaciones de su arquitectura para la disponibilidad, el escalado y las actualizaciones.

La práctica es de análisis y uso de la terminal. **No se desplegará la aplicación en Kubernetes todavía.** Los hallazgos se guardarán en `~/k8s-intro/analisis/monolito.md` para reutilizarlos en una práctica posterior.

Al finalizar, podrás:

- Reconocer cómo se agrupan los módulos de una aplicación monolítica.
- Diferenciar componentes internos y dependencias externas.
- Identificar variables de configuración y puertos.
- Explicar los riesgos de una instancia única y de una actualización global.
- Describir por qué escalar una función del monolito puede requerir replicar toda la aplicación.
- Documentar requisitos iniciales que luego podrán relacionarse con Kubernetes.

**Duración orientativa:** 15–20 minutos, dependiendo del tiempo de análisis y discusión.

## Prerrequisitos

- Haber completado el laboratorio del capítulo 1.
- Tener acceso a una terminal Bash.
- Tener disponible el directorio `~/k8s-intro`.
- Conocer el significado general de aplicación monolítica, contenedor, puerto y dependencia externa.

En esta práctica no necesitas crear Pods, Deployments, Services ni otros recursos de Kubernetes.

## 1. Comprobar el entorno y preparar el directorio

Comprueba que el clúster utilizado en el laboratorio anterior sigue accesible:

```bash
kubectl config current-context
minikube status -p minikube
```

El contexto esperado es `minikube`. Los componentes principales de Minikube deben estar en estado operativo.

Prepara el directorio donde guardarás el análisis:

```bash
mkdir -p ~/k8s-intro/analisis
cd ~/k8s-intro/analisis
pwd
```

**Observa:** `pwd` debe mostrar la ruta del directorio de análisis.

Si el clúster no está disponible, informa al instructor o sigue el procedimiento de diagnóstico del capítulo 1. No elimines ni recrees el clúster como primer intento de solución.

## 2. Analizar el caso `tienda-monolito`

Lee el siguiente caso. Utiliza esta descripción como fuente de información para tus conclusiones.

### Caso práctico

`tienda-monolito` es una aplicación de comercio electrónico distribuida como una única imagen de contenedor y ejecutada, para este caso, como un único proceso de aplicación. Expone una interfaz web y una API HTTP en el puerto TCP `8080`.

La aplicación agrupa los siguientes módulos funcionales:

- Autenticación
- Catálogo
- Inventario
- Pedidos
- Pagos
- Notificaciones
- Generación de informes

La interfaz web y la API constituyen la capa de presentación. Los módulos funcionales implementan la lógica de negocio. La aplicación utiliza un servicio externo de datos compartido para almacenar usuarios, catálogo, inventario y pedidos.

La aplicación requiere estas variables de configuración:

| Variable | Uso |
|---|---|
| `DB_HOST` | Dirección del servicio externo de datos. |
| `DB_PORT` | Puerto TCP del servicio de datos; el valor previsto es `5432`. |
| `DB_NAME` | Nombre de la base de datos. |
| `DB_USER` | Usuario de acceso a datos. |
| `DB_PASSWORD` | Contraseña de acceso a datos. |
| `PAYMENTS_URL` | URL HTTPS del proveedor externo de pagos. |
| `SMTP_HOST` | Dirección del servidor externo de correo SMTP. |
| `LOG_LEVEL` | Nivel de detalle de los registros de la aplicación. |

Sus dependencias externas son el servicio de datos, el proveedor de pagos y el servidor SMTP.

Actualmente existe una sola instancia de la aplicación y no hay balanceador de carga. Para actualizarla, se detiene la instancia anterior y después se inicia la nueva. Por tanto, la tienda deja de atender solicitudes durante ese intervalo.

Durante una campaña comercial, el catálogo recibe más carga que el módulo de pagos. Sin embargo, para aumentar la capacidad solo se pueden crear instancias completas de `tienda-monolito`. Cada instancia contiene todos los módulos y se conecta al mismo servicio externo de datos.

Si se modifica únicamente el módulo de notificaciones, hay que construir, probar y publicar una nueva versión de la aplicación completa. Un error en esa versión puede afectar a todas las funciones de la tienda.

## 3. Explorar y extraer información con comandos

En esta sección practicarás cómo consultar, buscar y contar información desde la terminal. Crea un archivo con los datos clave del caso para realizar búsquedas reproducibles:

```bash
cat > tienda-monolito.txt <<'EOF'
Aplicacion: tienda-monolito
Unidad de despliegue: una imagen y un proceso de aplicacion
Puerto de aplicacion: TCP 8080
DB_HOST: direccion del servicio de datos
DB_PORT: 5432
DB_NAME: nombre de la base de datos
DB_USER: usuario de acceso a datos
DB_PASSWORD: credencial sensible
PAYMENTS_URL: proveedor externo de pagos HTTPS
SMTP_HOST: servidor externo de correo SMTP
LOG_LEVEL: nivel de detalle de los registros
Dependencias externas: servicio de datos, proveedor de pagos, servidor SMTP
Instancias actuales: una
Balanceador de carga: no existe
Actualizacion: detener la instancia anterior y arrancar la nueva
Escalado: se replican todos los modulos de la aplicacion
EOF
```

Consulta el archivo:

```bash
cat tienda-monolito.txt
```

Busca las líneas relacionadas con puertos y configuración:

```bash
grep -E 'Puerto|DB_|PAYMENTS_URL|SMTP_HOST|LOG_LEVEL' tienda-monolito.txt
```

Busca la información sobre disponibilidad y escalado:

```bash
grep -E 'Instancias|Balanceador|Actualizacion|Escalado' tienda-monolito.txt
```

Cuenta las líneas del archivo:

```bash
wc -l tienda-monolito.txt
```

### ¿Qué debes observar?

- `cat` muestra el contenido de un archivo.
- `grep` encuentra líneas que coinciden con un patrón.
- `-E` permite buscar utilizando expresiones regulares extendidas.
- `wc -l` cuenta las líneas.

Estos comandos no analizan automáticamente la arquitectura por ti: ayudan a localizar información que después debes interpretar.

**Responde antes de continuar:**

1. ¿Qué puerto expone la aplicación?
2. ¿Qué puerto utiliza, según el caso, el servicio externo de datos?
3. ¿Cuáles son las tres dependencias externas?
4. ¿Qué sucede con la disponibilidad cuando se actualiza la única instancia?
5. ¿Por qué no se puede escalar exclusivamente el catálogo en la arquitectura descrita?

## 4. Relacionar el caso con la teoría

Completa el análisis usando los datos del caso.

### 4.1. Unidad de despliegue y módulos

Identifica los módulos funcionales y explica por qué `tienda-monolito` se considera monolítica.

Recuerda: una aplicación puede tener módulos internos bien separados y seguir siendo monolítica si esos módulos se construyen, publican y ejecutan como una única unidad.

### 4.2. Configuración y dependencias

Identifica las ocho variables de configuración y las tres dependencias externas.

Distingue entre:

- **Configuración:** valores que permiten ajustar el comportamiento de la aplicación según el entorno.
- **Dependencia externa:** servicio que la aplicación necesita para realizar una función.

`DB_PASSWORD` representa información sensible. En un entorno real, no debe publicarse en el repositorio ni escribirse directamente en un manifiesto sin una estrategia de gestión de secretos.

### 4.3. Puertos

Registra los puertos indicados en el caso:

- TCP `8080`: interfaz web y API HTTP de la aplicación.
- TCP `5432`: puerto previsto para la conexión con el servicio externo de datos.

No confundas el puerto de la aplicación con el puerto de su dependencia. El caso indica que el servicio de datos es externo; no afirma que se ejecute dentro del contenedor de la aplicación.

### 4.4. Disponibilidad y puntos únicos de fallo

Explica qué implica tener una sola instancia y detenerla antes de iniciar la nueva versión.

Una instancia única puede ser un punto único de fallo para la atención de solicitudes. La estrategia descrita también produce indisponibilidad durante las actualizaciones. El servicio externo de datos es otra dependencia crítica, aunque el caso no especifica su arquitectura interna ni su nivel de disponibilidad.

### 4.5. Escalado

Durante una campaña, el catálogo recibe más carga que los pagos. Explica por qué replicar la aplicación completa puede consumir recursos adicionales en módulos que no necesitan la misma capacidad.

No concluyas que el monolito no puede escalar: puede escalarse mediante más instancias completas. La limitación del caso es que no permite escalar cada módulo de forma independiente.

### 4.6. Actualizaciones

Explica por qué una modificación en notificaciones requiere publicar la aplicación completa y qué riesgo introduce ese enfoque.

## 5. Crear el informe de análisis

Crea el informe que se utilizará como referencia en una práctica posterior:

```bash
cat > ~/k8s-intro/analisis/monolito.md <<'EOF'
# Análisis de tienda-monolito

## Unidad de despliegue
Describir la imagen, el proceso y cómo se publican los módulos.

## Componentes funcionales
Enumerar los módulos identificados en el caso.

## Capas de la aplicación
- Presentación:
- Lógica de negocio:
- Acceso a datos:

## Variables de configuración
Enumerar las ocho variables y su propósito. No incluir valores de credenciales reales.

## Dependencias externas
Enumerar el servicio de datos, el proveedor de pagos y el servidor SMTP.

## Puertos
- TCP 8080:
- TCP 5432:

## Disponibilidad y puntos únicos de fallo
Explicar los efectos de tener una instancia y detenerla durante una actualización.

## Escalado
Explicar qué implica replicar toda la aplicación para atender la carga del catálogo.

## Actualizaciones
Explicar por qué un cambio en un módulo requiere publicar la unidad completa.

## Requisitos iniciales para la futura orquestación
Registrar necesidades relacionadas con ejecución reproducible, configuración, protección de credenciales, disponibilidad, conectividad y actualización.
EOF
```

Abre el archivo en el editor disponible en tu entorno y reemplaza las instrucciones de cada sección por tus propias conclusiones. Por ejemplo, puedes utilizar:

```bash
nano ~/k8s-intro/analisis/monolito.md
```

Guarda los cambios y sal del editor.

Después, revisa el documento:

```bash
cat ~/k8s-intro/analisis/monolito.md
```

**Importante:** el informe debe contener conclusiones basadas en el caso, no solamente copiar los títulos. No inventes características que no se han descrito, como múltiples réplicas, un balanceador o una base de datos dentro del contenedor.

## 6. Verificar el resultado

Comprueba que el archivo existe y no está vacío:

```bash
test -s ~/k8s-intro/analisis/monolito.md \
  && echo "OK: informe creado y no vacío"
```

Consulta su tamaño y revisa los encabezados:

```bash
wc -l ~/k8s-intro/analisis/monolito.md
grep '^## ' ~/k8s-intro/analisis/monolito.md
```

Revisa que el informe mencione los conceptos principales:

```bash
grep -inE '8080|5432|DB_PASSWORD|disponibilidad|escalado|actualiz' \
  ~/k8s-intro/analisis/monolito.md
```

Finalmente, confirma que el clúster sigue accesible:

```bash
kubectl get nodes
```

Esta última comprobación solo verifica el estado del clúster. **No es necesario desplegar una aplicación en Kubernetes en este capítulo.**

## 7. Criterios de finalización

El laboratorio está completo cuando puedes demostrar que:

- [ ] Identificaste los módulos y explicaste por qué la aplicación es monolítica.
- [ ] Documentaste las ocho variables de configuración.
- [ ] Identificaste las tres dependencias externas.
- [ ] Diferenciaste el puerto `8080` de la aplicación del puerto `5432` del servicio de datos.
- [ ] Explicaste los riesgos de disponibilidad y actualización.
- [ ] Explicaste por qué el escalado del caso replica todos los módulos.
- [ ] Completaste `~/k8s-intro/analisis/monolito.md` con tus propias conclusiones.
- [ ] Confirmaste que el clúster sigue accesible y no desplegaste recursos de aplicación.

## 8. Preguntas de cierre

Discute tus respuestas con el instructor o con otro estudiante:

1. ¿Qué característica de `tienda-monolito` la convierte en una unidad monolítica de despliegue?
2. ¿Qué diferencia existe entre un módulo interno y una dependencia externa?
3. ¿Qué problemas puede causar tener una única instancia?
4. ¿Qué ventaja tendría poder escalar el catálogo sin replicar los módulos de pagos y notificaciones?
5. ¿Qué requisitos debería considerar una futura solución de orquestación para ejecutar esta aplicación?

## Resultado esperado

Al finalizar, tendrás un informe estructurado que describe la arquitectura de `tienda-monolito`, sus dependencias y sus principales limitaciones operativas. Este documento servirá como entrada para una práctica posterior en la que se estudiará cómo expresar requisitos de una aplicación mediante recursos de Kubernetes.

El objetivo no es concluir que toda aplicación monolítica es incorrecta ni que Kubernetes elimina automáticamente sus limitaciones. El objetivo es reconocer las características de la aplicación y utilizar esa información para tomar decisiones técnicas fundamentadas.
