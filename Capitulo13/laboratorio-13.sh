
#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# LABORATORIO 13: USO DE ALMACENAMIENTO PERSISTENTE EN K8S
# Objetivo: demostrar persistencia de datos mediante un PVC.
# Namespace: laboratorio-k8s
# ============================================================

export LAB_ROOT="$HOME/k8s-intro"
export MANIFESTS_DIR="$LAB_ROOT/manifests"
export ANALYSIS_DIR="$LAB_ROOT/analisis"
export ARTIFACTS_DIR="$LAB_ROOT/artifacts"
export PROFILE="intro-k8s"
export NAMESPACE="lab-intro"

minikube start --driver=docker --kubernetes-version=v1.31.0 --cpus=2 --memory=4096mb

kubectl apply -f "$MANIFESTS_DIR/web-demo.yaml" 
kubectl apply -f "$MANIFESTS/webapp-deployment.yaml"
kubectl apply -f "$MANIFESTS/webapp-service.yaml"

# PASO 0. Preparar el directorio de trabajo y las evidencias.
mkdir -p ~/k8s-intro/manifests ~/k8s-intro/analisis
cd ~/k8s-intro

# Confirmar que Minikube está iniciado y usar el contexto correcto.
minikube status
kubectl config current-context

# Validar contexto antes de modificar recursos.
if [ "$(kubectl config current-context)" != "minikube" ]; then
  echo "ERROR: el contexto activo no es minikube. Se cancela la práctica."
  exit 1
  fi

# Definir el namespace para reutilizarlo en los comandos.
export NS=laboratorio-k8s

# Verificar que existen el namespace, Deployment y Service del lab 12.
kubectl get namespace "$NS"
kubectl get deployment webapp -n "$NS"
kubectl get service webapp-svc -n "$NS"
kubectl get pods -n "$NS" -l app=webapp -o wide

# Guardar una fotografía del estado inicial.
kubectl get deployment,service,pods -n "$NS" -o wide \
  | tee ~/k8s-intro/analisis/13-00-01-estado-inicial.txt

# Comprobar el nombre del contenedor que se modificará.
kubectl get deployment webapp -n "$NS" \
  -o jsonpath='{.spec.template.spec.containers[*].name}{"\n"}'

# PASO 1. Inspeccionar la StorageClass de Minikube.
# Esta clase permite aprovisionar el volumen de forma dinámica.
kubectl get storageclass
kubectl describe storageclass standard
kubectl get storageclass standard -o yaml \
  > ~/k8s-intro/analisis/13-00-01-storageclass-standard.yaml

# Comprobar los addons relacionados con almacenamiento.
minikube addons list | grep -E 'storage-provisioner|default-storageclass'

# Mostrar el nombre y el provisionador de la clase.
kubectl get storageclass standard \
  -o jsonpath='{.metadata.name}{" | provisioner="}{.provisioner}{"\n"}'

# PASO 2. Crear el manifiesto del PersistentVolumeClaim (PVC).
# Se solicitan 1 GiB, acceso ReadWriteOnce y StorageClass standard.
cat > ~/k8s-intro/manifests/webapp-content-pvc.yaml <<'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: webapp-content-pvc
  namespace: laboratorio-k8s
  labels:
    app: webapp
    laboratorio: 13-00-01
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: standard
  resources:
    requests:
      storage: 1Gi
EOF

# Revisar el YAML y crear el PVC en Kubernetes.
cat ~/k8s-intro/manifests/webapp-content-pvc.yaml
kubectl apply -f ~/k8s-intro/manifests/webapp-content-pvc.yaml

# Esperar hasta que el PVC esté enlazado a un PersistentVolume.
kubectl wait \
  --namespace "$NS" \
  --for=jsonpath='{.status.phase}'=Bound \
  pvc/webapp-content-pvc \
  --timeout=120s

# Inspeccionar el PVC y el PV aprovisionado.
kubectl get pvc webapp-content-pvc -n "$NS"
kubectl get pv
kubectl describe pvc webapp-content-pvc -n "$NS"

# Guardar la definición del PVC como evidencia.
kubectl get pvc webapp-content-pvc -n "$NS" -o yaml \
  > ~/k8s-intro/analisis/13-00-01-pvc-bound.yaml

# Validar fase, capacidad solicitada y modo de acceso.
kubectl get pvc webapp-content-pvc -n "$NS" \
  -o jsonpath='{.status.phase}{" | "}{.spec.resources.requests.storage}{" | "}{.spec.accessModes[0]}{"\n"}'

# PASO 3. Crear el parche para montar el PVC en NGINX.
# El initContainer crea index.html solo si todavía no existe.
# Se usa una réplica para este ejercicio con ReadWriteOnce.
cat > ~/k8s-intro/manifests/webapp-persistent-storage-patch.yaml <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: webapp
  namespace: laboratorio-k8s
spec:
  replicas: 1
  template:
    spec:
      initContainers:
        - name: initialize-content
          image: busybox:1.37.0
          imagePullPolicy: IfNotPresent
          command:
            - /bin/sh
            - -c
          args:
            - |
              set -eu
              FILE=/usr/share/nginx/html/index.html

              if [ -f "$FILE" ]; then
                echo "index.html ya existe; se conserva el contenido persistente."
              else
                printf '%s\\n' \\
                  '<!doctype html>' \\
                  '<html lang="es">' \\
                  '<head><meta charset="utf-8"><title>Webapp persistente</title></head>' \\
                  '<body>' \\
                  '<h1>Webapp con almacenamiento persistente</h1>' \\
                  '<p>Este archivo fue inicializado por un initContainer.</p>' \\
                  '</body></html>' > "$FILE"
                echo "index.html creado correctamente."
              fi
          volumeMounts:
            - name: webapp-content
              mountPath: /usr/share/nginx/html
      containers:
        - name: webapp
          image: nginx:1.27.4-alpine
          volumeMounts:
            - name: webapp-content
              mountPath: /usr/share/nginx/html
      volumes:
        - name: webapp-content
          persistentVolumeClaim:
            claimName: webapp-content-pvc
EOF

# Comprobar que el contenedor principal se llama webapp.
grep -n 'name: webapp' \
  ~/k8s-intro/manifests/webapp-persistent-storage-patch.yaml

# Aplicar el parche al Deployment existente.
kubectl patch deployment webapp \
  --namespace "$NS" \
  --type=strategic \
  --patch-file ~/k8s-intro/manifests/webapp-persistent-storage-patch.yaml

# Esperar a que termine el rollout.
kubectl rollout status deployment/webapp -n "$NS" --timeout=180s

# Obtener el nombre del Pod y revisar el estado del initContainer.
kubectl get pods -n "$NS" -l app=webapp -o wide
kubectl get pods -n "$NS" -l app=webapp \
  -o jsonpath='{range .items[*]}{.metadata.name}{" | init="}{.status.initContainerStatuses[0].state.terminated.reason}{"\n"}{end}'

POD_ACTUAL=$(kubectl get pods -n "$NS" -l app=webapp \
  -o jsonpath='{.items[0].metadata.name}')

# Consultar los logs de la inicialización del volumen.
kubectl logs "$POD_ACTUAL" -n "$NS" -c initialize-content

# Comprobar que el Pod tiene montado el PVC.
kubectl describe pod "$POD_ACTUAL" -n "$NS" \
  | sed -n '/Volumes:/,/QoS Class:/p'

# PASO 4. Validar el contenido inicial y el acceso HTTP.
# Leer index.html directamente desde el contenedor NGINX.
kubectl exec -n "$NS" "$POD_ACTUAL" -c webapp -- \
  cat /usr/share/nginx/html/index.html

# Verificar que el Service tiene endpoints disponibles.
kubectl get endpoints webapp-svc -n "$NS"

# Consultar la página mediante un Pod temporal.
# --rm elimina el Pod de prueba al finalizar.
kubectl run http-check \
  --namespace "$NS" \
  --rm -i \
  --restart=Never \
  --image=busybox:1.37.0 \
  -- sh -c 'wget -qO- http://webapp-svc/'

# Guardar la respuesta HTTP como evidencia.
kubectl run http-check-evidence \
  --namespace "$NS" \
  --rm -i \
  --restart=Never \
  --image=busybox:1.37.0 \
  -- sh -c 'wget -qO- http://webapp-svc/' \
  | tee ~/k8s-intro/analisis/13-00-01-index-http.html

# Comprobar que la página contiene el título esperado.
grep -F 'Webapp con almacenamiento persistente' \
  ~/k8s-intro/analisis/13-00-01-index-http.html

# PASO 5. Escribir un archivo de prueba en el volumen persistente.
# El token permite comprobar que los datos sobreviven al Pod.
POD_ANTES=$(kubectl get pods -n "$NS" -l app=webapp \
  -o jsonpath='{.items[0].metadata.name}')

TOKEN="persistencia-$(date +%Y%m%d-%H%M%S)"
echo "Token de prueba: $TOKEN"

# Crear persistencia.txt dentro del directorio montado desde el PVC.
kubectl exec -n "$NS" "$POD_ANTES" -c webapp -- \
  sh -c "printf '%s\n' '$TOKEN' > /usr/share/nginx/html/persistencia.txt"

# Leer el archivo para comprobar que se escribió correctamente.
kubectl exec -n "$NS" "$POD_ANTES" -c webapp -- \
  cat /usr/share/nginx/html/persistencia.txt

# Validar que el archivo también se sirve mediante el Service.
kubectl run http-persistence-check \
  --namespace "$NS" \
  --rm -i \
  --restart=Never \
  --image=busybox:1.37.0 \
  -- sh -c 'wget -qO- http://webapp-svc/persistencia.txt'

# Guardar el nombre del Pod y el token antes de eliminarlo.
{
  echo "POD_ANTES=$POD_ANTES"
  echo "TOKEN=$TOKEN"
} | tee ~/k8s-intro/analisis/13-00-01-datos-prueba.txt

# Verificar que el archivo contiene exactamente el token.
kubectl exec -n "$NS" "$POD_ANTES" -c webapp -- \
  cat /usr/share/nginx/html/persistencia.txt | grep -Fx "$TOKEN"

# PASO 6. Eliminar únicamente el Pod y comprobar su recreación.
# NO se elimina el Deployment ni el PVC.
kubectl delete pod "$POD_ANTES" -n "$NS"

# Esperar a que el Pod anterior desaparezca.
kubectl wait \
  --for=delete "pod/$POD_ANTES" \
  -n "$NS" \
  --timeout=120s

# Esperar a que el Deployment vuelva a estar disponible.
kubectl rollout status deployment/webapp -n "$NS" --timeout=180s

# Obtener el nombre del nuevo Pod.
POD_DESPUES=$(kubectl get pods -n "$NS" -l app=webapp \
  -o jsonpath='{.items[0].metadata.name}')

echo "Pod anterior: $POD_ANTES"
echo "Pod nuevo:    $POD_DESPUES"

# Confirmar que Kubernetes creó una instancia diferente.
test "$POD_ANTES" != "$POD_DESPUES" && \
  echo "Correcto: el Deployment creó un Pod nuevo."

# Leer el archivo desde el Pod nuevo.
# Si el PVC funciona, el token debe ser idéntico al original.
kubectl exec -n "$NS" "$POD_DESPUES" -c webapp -- \
  cat /usr/share/nginx/html/persistencia.txt

# Validar automáticamente que el contenido no cambió.
kubectl exec -n "$NS" "$POD_DESPUES" -c webapp -- \
  cat /usr/share/nginx/html/persistencia.txt | grep -Fx "$TOKEN"

# Revisar el initContainer: debe conservar index.html existente.
kubectl logs "$POD_DESPUES" -n "$NS" -c initialize-content

# Confirmar la persistencia por HTTP desde un Pod temporal.
kubectl run http-final-check \
  --namespace "$NS" \
  --rm -i \
  --restart=Never \
  --image=busybox:1.37.0 \
  -- sh -c 'wget -qO- http://webapp-svc/persistencia.txt'

# PASO 7. Guardar evidencias del estado final.
kubectl get pvc,pv -n "$NS" -o wide \
  > ~/k8s-intro/analisis/13-00-01-almacenamiento-final.txt

kubectl get pods -n "$NS" -l app=webapp -o wide \
  >> ~/k8s-intro/analisis/13-00-01-almacenamiento-final.txt

kubectl logs "$POD_DESPUES" -n "$NS" -c initialize-content \
  > ~/k8s-intro/analisis/13-00-01-initcontainer-recreado.log

# Mostrar la fase, capacidad y contenido persistido.
kubectl get pvc webapp-content-pvc -n "$NS" \
  -o jsonpath='PVC={.metadata.name}{" | fase="}{.status.phase}{" | capacidad="}{.status.capacity.storage}{"\n"}'

kubectl exec -n "$NS" "$POD_DESPUES" -c webapp -- \
  cat /usr/share/nginx/html/persistencia.txt

# Validar una vez más el contenido publicado por el Service.
kubectl run http-validation \
  --namespace "$NS" \
  --rm -i \
  --restart=Never \
  --image=busybox:1.37.0 \
  -- sh -c 'wget -qO- http://webapp-svc/persistencia.txt'

# PASO 8. Limpiar posibles Pods temporales que hayan quedado.
# No se borra el PVC porque se utilizará en el laboratorio 14.
kubectl delete pod \
  http-check \
  http-check-evidence \
  http-persistence-check \
  http-final-check \
  http-validation \
  -n "$NS" \
  --ignore-not-found=true

# Verificar que los recursos necesarios continúan disponibles.
kubectl get deployment webapp -n "$NS"
kubectl get service webapp-svc -n "$NS"
kubectl get pvc webapp-content-pvc -n "$NS"
kubectl get pods -n "$NS" -l app=webapp -o wide

echo "Laboratorio 13 finalizado."
echo "Evidencias guardadas en ~/k8s-intro/analisis/"
