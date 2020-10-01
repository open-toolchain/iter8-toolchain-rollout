#!/bin/bash
# uncomment to debug the script
# set -x
# copy the script below into your app code repo (e.g. ./scripts/bookinfo_check_install.sh) and 'source' it from your pipeline job
#    source ./scripts/bookinfo_check_install.sh
# alternatively, you can source it from online script:
#    source <(curl -sSL "https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/bookinfo_check_install.sh")
# ------------------
# source: https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/bookinfo_check_install.sh

# Check bookinfo installation in target cluster

# Input env variables from pipeline job

# Create namespace
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: ${CLUSTER_NAMESPACE}
  labels:
    istio-injection: enabled
EOF

# Install bookinfo
kubectl --namespace ${CLUSTER_NAMESPACE} \
   apply -f https://raw.githubusercontent.com/open-toolchain/iter8-toolchain-rollout/master/scripts/bookinfo.yaml

# Expose bookinfo
#kubectl --namespace ${CLUSTER_NAMESPACE} \
#    apply -f https://raw.githubusercontent.com/open-toolchain/iter8-toolchain-rollout/master/scripts/bookinfo-gateway.yaml

HOSTNAME="${HOST}"
if [[ -z ${HOST} ]]; then HOSTNAME='*'; fi

cat <<EOF | kubectl --namespace ${CLUSTER_NAMESPACE} apply -f -
apiVersion: networking.istio.io/v1alpha3
kind: Gateway
metadata:
  name: bookinfo-gateway
spec:
  selector:
    istio: ingressgateway # use istio default controller
  servers:
  - port:
      number: 80
      name: http
      protocol: HTTP
    hosts:
    - "${HOSTNAME}"
---
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: bookinfo
spec:
  hosts:
  - "${HOSTNAME}"
  gateways:
  - bookinfo-gateway
  http:
  - match:
    - uri:
        exact: /productpage
    - uri:
        exact: /login
    - uri:
        exact: /logout
    - uri:
        prefix: /api/v1/products
    route:
    - destination:
        host: productpage
        port:
          number: 9080
EOF

# Find the information to access the application
# https://cloud.ibm.com/docs/containers?topic=containers-istio-mesh#istio_access_bookinfo
INGRESS_IP=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
INGRESS_PORT=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.spec.ports[?(@.name=="http2")].port}')
if [[ ! ${INGRESS_IP} ]]; then
  INGRESS_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type == "ExternalIP")].address}')
fi
APP_URL="http://${INGRESS_IP}:${INGRESS_PORT}/productpage"

echo "Application URL: ${APP_URL}"
if [[ -z ${HOST} ]]; then
  echo "   curl command: curl -Is ${APP_URL}"
  echo "Load Generation: watch -x -n 0.1 curl -Is ${APP_URL}"
else
  echo "   curl command: curl -Is -H 'Host: ${HOST}' ${APP_URL}"
  echo "Load Generation: watch -x -n 0.1 curl -Is -H 'Host: ${HOST}' ${APP_URL}"
fi
