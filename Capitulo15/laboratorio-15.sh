#!/usr/bin/env bash
set -Eeuo pipefail

# Variables del laboratorio
export LAB_ROOT="$HOME/k8s-intro"
export MANIFESTS_DIR="$LAB_ROOT/manifests"
export ANALYSIS_DIR="$LAB_ROOT/analisis"
export ARTIFACTS_DIR="$LAB_ROOT/artifacts"

export PROFILE="minikube"
export LAB_NS="laboratorio-k8s"
export INGRESS_NS="ingress-nginx"
export APP_SERVICE="webapp-svc"
export APP_HOST="webapp.local.test"

# Preparar directorios
mkdir -p "$MANIFESTS_DIR" "$ANALYSIS_DIR" "$ARTIFACTS_DIR"

# Iniciar o verificar Minikube sin eliminar el clúster existente
minikube --profile="$PROFILE" start \
  --driver=docker \
  --kubernetes-version=v1.31.0 \
  --cpus=2 \
  --memory=4096mb

kubectl config use-context "$PROFILE"

# Verificar los recursos heredados del capítulo 14
kubectl get pods -n "$LAB_NS" -o wide
kubectl get service "$APP_SERVICE" -n "$LAB_NS"
kubectl get endpoints "$APP_SERVICE" -n "$LAB_NS"
kubectl get pvc webapp-content-pvc -n "$LAB_NS"
kubectl get configmap webapp-config -n "$LAB_NS"

# Descargar el manifiesto oficial de ingress-nginx v1.12.0
curl -fL \
  -o "$MANIFESTS_DIR/ingress-nginx-controller-v1.12.0.yaml" \
  https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.12.0/deploy/static/provider/cloud/deploy.yaml

# Instalar y esperar el controlador
kubectl apply \
  -f "$MANIFESTS_DIR/ingress-nginx-controller-v1.12.0.yaml"

kubectl wait \
  --namespace="$INGRESS_NS" \
  --for=condition=Available \
  deployment/ingress-nginx-controller \
  --timeout=240s

# Crear el manifiesto Ingress
cat > "$MANIFESTS_DIR/webapp-ingress.yaml" <<'EOF'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: webapp-ingress
  namespace: laboratorio-k8s
spec:
  ingressClassName: nginx
  rules:
    - host: webapp.local.test
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: webapp-svc
                port:
                  number: 80
EOF

# Aplicar y revisar el Ingress
kubectl apply -f "$MANIFESTS_DIR/webapp-ingress.yaml"
kubectl get ingress webapp-ingress -n "$LAB_NS"
kubectl describe ingress webapp-ingress -n "$LAB_NS"

# Guardar evidencia
kubectl get ingress webapp-ingress -n "$LAB_NS" -o yaml \
  > "$ANALYSIS_DIR/15-00-01-ingress.yaml"