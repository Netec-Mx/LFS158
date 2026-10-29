#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# LABORATORIO 14: CONFIGMAPS - CONFIGURACION DE UNA APLICACION
# Basado en Netec-Mx/LFS158/Capitulo14/README.md
# Mantiene Minikube iniciado y exporta las variables de trabajo.
# No elimina el Deployment, Service ni PVC.
# ============================================================

export LAB_ROOT="${HOME}/k8s-intro"
export MANIFESTS_DIR="${LAB_ROOT}/manifests"
export ANALYSIS_DIR="${LAB_ROOT}/analisis"
export ARTIFACTS_DIR="${LAB_ROOT}/artifacts"
export PROFILE="minikube"
export NAMESPACE="curso-k8s"
export NS="${NAMESPACE}"

mkdir -p "${MANIFESTS_DIR}" "${ANALYSIS_DIR}" "${ARTIFACTS_DIR}"
cd "${LAB_ROOT}"

echo "== Paso 0: iniciar/verificar Minikube =="
minikube --profile "${PROFILE}" start \
  --driver=docker \
  --kubernetes-version=v1.31.0 \
  --cpus=2 \
  --memory=4096mb

kubectl config use-context "${PROFILE}" >/dev/null
if [[ "$(kubectl config current-context)" != "${PROFILE}" ]]; then
  echo "ERROR: el contexto activo no es ${PROFILE}." >&2
  exit 1
fi
minikube --profile "${PROFILE}" status
kubectl config current-context

# Capitulo 14 del README especifica curso-k8s. En el laboratorio anterior
# del usuario se utilizo laboratorio-k8s; detectamos el namespace que ya
# contiene los tres recursos heredados para no apuntar al lugar incorrecto.
has_prerequisites() {
  local ns="$1"
  kubectl get deployment webapp -n "$ns" >/dev/null 2>&1 &&
    kubectl get service webapp-svc -n "$ns" >/dev/null 2>&1 &&
    kubectl get pvc webapp-content-pvc -n "$ns" >/dev/null 2>&1
}

if has_prerequisites "curso-k8s"; then
  export NAMESPACE="curso-k8s"
elif has_prerequisites "laboratorio-k8s"; then
  export NAMESPACE="laboratorio-k8s"
  echo "AVISO: los recursos heredados están en laboratorio-k8s."
  echo "El README especifica curso-k8s; se usará laboratorio-k8s para conservar el entorno existente."
else
  echo "ERROR: no se encontraron Deployment webapp, Service webapp-svc y PVC webapp-content-pvc"
  echo "en curso-k8s ni en laboratorio-k8s. No se modificó ningún recurso."
  echo "Revise los prerrequisitos del capítulo 13 antes de continuar." >&2
  exit 1
fi
export NS="${NAMESPACE}"
echo "Namespace seleccionado: ${NAMESPACE}"

echo "== Paso 1: verificar los recursos heredados =="
kubectl get namespace "${NS}"
kubectl get deployment webapp -n "${NS}"
kubectl get service webapp-svc -n "${NS}"
kubectl get pvc webapp-content-pvc -n "${NS}"
kubectl get deployment webapp -n "${NS}" \
  -o jsonpath='{.spec.template.spec.containers[*].name}{"\n"}'
kubectl describe deployment webapp -n "${NS}"
kubectl get deployment webapp -n "${NS}" -o yaml \
  > "${ANALYSIS_DIR}/14-00-01-webapp-antes.yaml"

# Requerimos una app estable antes de cambiar su plantilla.
kubectl rollout status deployment/webapp -n "${NS}" --timeout=120s

echo "== Paso 2: crear y aplicar el ConfigMap inicial =="
cat > "${MANIFESTS_DIR}/webapp-config.yaml" <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: webapp-config
  namespace: ${NS}
  labels:
    app: webapp
    laboratorio: 14-00-01
data:
  config.json: |
    {
      "applicationName": "webapp",
      "environment": "desarrollo",
      "supportEmail": "soporte-desarrollo@example.com"
    }
EOF

cat "${MANIFESTS_DIR}/webapp-config.yaml"
kubectl apply -f "${MANIFESTS_DIR}/webapp-config.yaml"
kubectl get configmap webapp-config -n "${NS}"
kubectl get configmap webapp-config -n "${NS}" \
  -o jsonpath='{.data.config\.json}{"\n"}'
kubectl describe configmap webapp-config -n "${NS}"

echo "== Paso 3: montar config.json usando ConfigMap y subPath =="
cat > "${MANIFESTS_DIR}/webapp-config-mount-patch.yaml" <<'EOF'
spec:
  template:
    spec:
      volumes:
        - name: webapp-config-volume
          configMap:
            name: webapp-config
            items:
              - key: config.json
                path: config.json
      containers:
        - name: webapp
          volumeMounts:
            - name: webapp-config-volume
              mountPath: /usr/share/nginx/html/config.json
              subPath: config.json
              readOnly: true
EOF

cat "${MANIFESTS_DIR}/webapp-config-mount-patch.yaml"
kubectl patch deployment webapp -n "${NS}" \
  --type=strategic \
  --patch-file "${MANIFESTS_DIR}/webapp-config-mount-patch.yaml"
kubectl rollout status deployment/webapp -n "${NS}" --timeout=120s
kubectl get pods -n "${NS}" -l app=webapp -o wide
kubectl describe deployment webapp -n "${NS}"
kubectl get deployment webapp -n "${NS}" -o yaml \
  > "${ANALYSIS_DIR}/14-00-01-webapp-con-configmap.yaml"

echo "== Paso 4: validar config.json a través del Service interno =="
kubectl get service webapp-svc -n "${NS}"
kubectl run webapp-config-check \
  -n "${NS}" --rm -i --restart=Never \
  --image=busybox:1.37.0 \
  -- sh -c 'wget -qO- http://webapp-svc/config.json'

kubectl run webapp-config-evidence \
  -n "${NS}" --rm -i --restart=Never \
  --image=busybox:1.37.0 \
  -- sh -c 'wget -qO- http://webapp-svc/config.json' \
  | tee "${ANALYSIS_DIR}/14-00-01-config-inicial.json"

grep -E '"applicationName"|"environment"|"supportEmail"' \
  "${ANALYSIS_DIR}/14-00-01-config-inicial.json"
grep '"environment": "desarrollo"' \
  "${ANALYSIS_DIR}/14-00-01-config-inicial.json"

echo "== Paso 5: actualizar el ConfigMap y reiniciar el Deployment =="
cat > "${MANIFESTS_DIR}/webapp-config.yaml" <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: webapp-config
  namespace: ${NS}
  labels:
    app: webapp
    laboratorio: 14-00-01
data:
  config.json: |
    {
      "applicationName": "webapp",
      "environment": "pruebas",
      "supportEmail": "soporte-pruebas@example.com"
    }
EOF

kubectl apply -f "${MANIFESTS_DIR}/webapp-config.yaml"
kubectl get configmap webapp-config -n "${NS}" \
  -o jsonpath='{.data.config\.json}{"\n"}'
kubectl rollout restart deployment/webapp -n "${NS}"
kubectl rollout status deployment/webapp -n "${NS}" --timeout=120s
kubectl rollout history deployment/webapp -n "${NS}"

kubectl run webapp-config-updated-check \
  -n "${NS}" --rm -i --restart=Never \
  --image=busybox:1.37.0 \
  -- sh -c 'wget -qO- http://webapp-svc/config.json' \
  | tee "${ANALYSIS_DIR}/14-00-01-config-actualizado.json"

grep '"environment": "pruebas"' \
  "${ANALYSIS_DIR}/14-00-01-config-actualizado.json"
grep '"supportEmail": "soporte-pruebas@example.com"' \
  "${ANALYSIS_DIR}/14-00-01-config-actualizado.json"

echo "== Paso 6: validación final y evidencias =="
kubectl config current-context
kubectl get configmap webapp-config -n "${NS}"
kubectl get deployment webapp -n "${NS}"
kubectl get service webapp-svc -n "${NS}"
kubectl get pvc webapp-content-pvc -n "${NS}"
kubectl rollout status deployment/webapp -n "${NS}" --timeout=120s
kubectl get pods -n "${NS}" -o wide

kubectl get deployment webapp -n "${NS}" -o yaml \
  > "${ANALYSIS_DIR}/14-00-01-webapp-final.yaml"
kubectl get configmap webapp-config -n "${NS}" -o yaml \
  > "${ANALYSIS_DIR}/14-00-01-configmap-final.yaml"
kubectl get pvc webapp-content-pvc -n "${NS}" -o yaml \
  > "${ANALYSIS_DIR}/14-00-01-pvc-final.yaml"

echo "== Comprobación del contenido final =="
cat "${ANALYSIS_DIR}/14-00-01-config-actualizado.json"
echo
echo "Evidencias guardadas en: ${ANALYSIS_DIR}"
echo "Laboratorio 14 finalizado correctamente."
echo "Namespace usado: ${NS}"
echo "Se conservaron el Deployment, Service y PVC."
