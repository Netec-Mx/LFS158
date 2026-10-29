# Capítulo 1 — Validación del entorno de trabajo

## Propósito del laboratorio

El propósito de esta práctica es que el estudiante empiece a utilizar la terminal y compruebe, mediante comandos y resultados observables, que el entorno de trabajo está preparado para las siguientes prácticas de Kubernetes.

Al finalizar, el estudiante podrá:

- Navegar por directorios y crear una estructura básica de trabajo.
- Comprobar que Docker, Minikube y `kubectl` están disponibles.
- Ejecutar un contenedor de prueba con Docker.
- Iniciar un clúster local de Kubernetes con Minikube.
- Identificar el contexto activo de `kubectl`.
- Consultar el estado del nodo y explorar algunos recursos básicos del clúster.

> **Enfoque:** ejecutar, observar e interpretar. No es necesario memorizar todos los detalles de Kubernetes en esta primera práctica.

## Prerrequisitos

- Acceso a una terminal Linux del entorno de laboratorio.
- Docker, Minikube y `kubectl` instalados.
- Acceso a Internet para descargar imágenes si todavía no están disponibles localmente.
- Los permisos y recursos de CPU y memoria requeridos por el entorno de laboratorio.

## 1. Preparar el directorio de trabajo

Crea los directorios que utilizarás durante las prácticas y entra en el directorio principal:

```bash
mkdir -p ~/k8s-intro/analisis
mkdir -p ~/k8s-intro/manifests

cd ~/k8s-intro
pwd
ls -la
```

### ¿Qué debes observar?

- `mkdir -p` crea los directorios intermedios que hagan falta y no falla si ya existen.
- `~` representa el directorio personal del usuario.
- `pwd` muestra la ruta del directorio actual.
- `ls -la` muestra el contenido del directorio, incluidos los archivos ocultos.

**Pregunta de comprobación:** ¿en qué ruta quedaron los directorios `analisis` y `manifests`?

## 2. Comprobar las herramientas y ejecutar un contenedor

Consulta las versiones de las herramientas:

```bash
docker --version
minikube version
kubectl version --client
```

Ahora ejecuta un contenedor de prueba:

```bash
docker run --rm hello-world
```

### ¿Qué debes observar?

Docker puede descargar la imagen `hello-world` si aún no está disponible localmente. Después crea un contenedor, ejecuta el programa de prueba y elimina el contenedor al finalizar.

- **Imagen:** plantilla utilizada para crear un contenedor.
- **Contenedor:** instancia que ejecuta un proceso a partir de una imagen.
- `--rm`: elimina el contenedor cuando termina; no significa que también se elimine la imagen.

**Pregunta de comprobación:** ¿qué mensaje confirma que el contenedor se ejecutó correctamente?

## 3. Iniciar el clúster local de Kubernetes

Inicia Minikube utilizando Docker como controlador:

```bash
minikube start \
  --driver=docker \
  --kubernetes-version=v1.31.0 \
  --cpus=2 \
  --memory=4096mb
```

Espera a que el comando termine. El primer inicio puede tardar más si es necesario descargar imágenes.

Comprueba el estado de Minikube:

```bash
minikube status -p minikube
```

### ¿Qué hace este comando?

- `minikube start` crea o inicia el clúster local.
- `--driver=docker` indica que Minikube utilizará Docker para ejecutar el nodo.
- `--kubernetes-version` especifica la versión de Kubernetes solicitada para el clúster.
- `--cpus=2` solicita dos CPU para el nodo.
- `--memory=4096mb` solicita 4096 MB de memoria.

En esta configuración, Docker es el mecanismo que ejecuta el nodo de Minikube. Minikube, por su parte, prepara el entorno de Kubernetes.

### ¿Qué debes observar?

Comprueba que el comando de inicio finaliza sin errores y que el estado de Minikube indica que los componentes principales están funcionando.

**Pregunta de comprobación:** ¿qué diferencia hay entre comprobar la versión de Minikube y comprobar el estado de un clúster?

## 4. Comprobar la conexión de `kubectl` con Kubernetes

Ejecuta estos comandos:

```bash
kubectl config current-context
kubectl cluster-info
kubectl version
```

### ¿Qué hace cada comando?

- `kubectl config current-context` muestra el contexto que utilizará `kubectl`.
- `kubectl cluster-info` consulta información de los servicios principales del clúster.
- `kubectl version` muestra información de la versión del cliente y del servidor cuando este último está accesible.

Un **contexto** es una configuración que permite a `kubectl` saber a qué clúster conectarse y qué identidad y namespace utilizar.

### ¿Qué debes observar?

Confirma que el contexto corresponde al clúster de Minikube y que `kubectl` puede consultar la información del clúster.

**Pregunta de comprobación:** si tuvieras configurados dos clústeres, ¿por qué sería importante revisar el contexto antes de ejecutar comandos?

## 5. Explorar el clúster

### 5.1. Consultar los nodos

```bash
kubectl get nodes -o wide
```

Identifica las columnas `NAME`, `STATUS`, `ROLES` y `VERSION`.

- `NAME`: nombre del nodo.
- `STATUS`: estado reportado por Kubernetes.
- `ROLES`: roles que aparecen asociados al nodo.
- `VERSION`: versión de Kubernetes que ejecuta el nodo.

El estado `Ready` indica que Kubernetes considera al nodo disponible para participar en la ejecución de cargas de trabajo. No garantiza por sí solo que cualquier aplicación vaya a funcionar.

**Pregunta:** ¿cuántos nodos aparecen y qué estado tiene cada uno?

### 5.2. Consultar los namespaces

```bash
kubectl get namespaces
```

Los **namespaces** permiten organizar recursos dentro de un clúster. Observa los nombres que aparecen en la salida.

**Pregunta:** ¿qué namespaces aparecen en tu entorno?

### 5.3. Consultar los Pods del sistema

```bash
kubectl get pods -n kube-system
```

Un **Pod** es la unidad desplegable más pequeña de Kubernetes y puede contener uno o más contenedores estrechamente relacionados. El namespace `kube-system` contiene Pods asociados a componentes del sistema del clúster.

Es normal encontrar Pods aunque todavía no hayas desplegado una aplicación propia.

**Pregunta:** ¿por qué crees que Kubernetes necesita ejecutar componentes del sistema antes de que despliegues tu propia aplicación?

### 5.4. Inspeccionar el nodo

```bash
kubectl describe node minikube
```

Este comando presenta información más detallada sobre el nodo, incluidos su estado, capacidad y condiciones.

No necesitas memorizar todos los campos. Localiza la información relacionada con el estado y los recursos del nodo.

**Pregunta:** ¿qué información adicional encuentras aquí que no aparecía en `kubectl get nodes`?

## 6. Guardar una evidencia sencilla

Guarda un resumen de las comprobaciones realizadas:

```bash
{
  echo "=== Fecha de la comprobación ==="
  date
  echo
  echo "=== Contexto activo ==="
  kubectl config current-context
  echo
  echo "=== Nodos ==="
  kubectl get nodes -o wide
  echo
  echo "=== Namespaces ==="
  kubectl get namespaces
} | tee ~/k8s-intro/analisis/evidencia-capitulo-01.txt
```

Consulta el archivo generado:

```bash
cat ~/k8s-intro/analisis/evidencia-capitulo-01.txt
```

La evidencia permite conservar el resultado de las consultas principales. Si un comando falla, revisa el mensaje de error antes de continuar.

## 7. Criterios de finalización

Marca cada punto cuando lo hayas comprobado:

- [ ] Puedo navegar por el directorio de trabajo y reconocer su ruta.
- [ ] Docker ejecutó correctamente el contenedor `hello-world`.
- [ ] Minikube está iniciado y sus componentes principales aparecen en estado operativo.
- [ ] Identifiqué el contexto activo de `kubectl`.
- [ ] Pude consultar los nodos, los namespaces y los Pods del sistema.
- [ ] Inspeccioné el nodo y generé el archivo de evidencia.

## 8. Si algo falla

- **Docker no responde:** comprueba que el servicio de Docker está activo y que tu usuario tiene permiso para utilizarlo.
- **Minikube no inicia:** lee el mensaje completo del comando `minikube start` y revisa el estado con `minikube status -p minikube`.
- **`kubectl` no conecta con el clúster:** comprueba `kubectl config current-context` y `minikube status -p minikube`.
- **La descarga tarda:** espera a que finalice; la primera ejecución puede necesitar descargar imágenes.
- **Un comando devuelve un error:** conserva el mensaje y consúltalo con el instructor antes de borrar o recrear el clúster.

> No ejecutes `minikube delete` como primer intento de solución. Eliminar el clúster puede borrar los recursos que contiene y no suele ser necesario para diagnosticar un problema de conexión.

## Resultado esperado

Al terminar, el estudiante habrá utilizado comandos básicos de Linux, ejecutado un contenedor con Docker, iniciado un clúster local y consultado recursos fundamentales de Kubernetes. También habrá guardado evidencia de que el entorno está operativo.

El objetivo no es dominar todos estos conceptos todavía, sino empezar a relacionar cada comando con un resultado observable y dejar el entorno listo para las siguientes prácticas.
