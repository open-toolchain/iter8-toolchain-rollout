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

Create namespace
cat <EOF | kubectl apply -f
apiVersion: v1
kind: Namespace
metadata:
  name: ${CLUSTER_NAMESPACE}
  labels:
    istio-injection: enabled
EOF

# Install bookinfo
kubectl apply -f https://raw.githubusercontent.com/kalantar/canary-testing-istio-toolchain/master/scripts/bookinfo.yaml

# Expose bookinfo
kubectl apply -f https://raw.githubusercontent.com/kalantar/canary-testing-istio-toolchain/master/scripts/bookinfo-gateway.yaml

LOADBALANCER=$(kubectl --namespace istio-system get service istio-ingressgateway --output jsonpath='{.status.loadBalancer.ingress[0].ip}')
PORT=$(kubectl --namespace istio-system get service istio-ingressgateway --output jsonpath='{.spec.ports[?(@.targetPort==80)].nodePort}')
APP_URL="http://$LOADBALANCER:$PORT/productpage"
echo "Application URL: $APP_URL"

HOST=$(kubectl --namespace ${CLUSTER_NAMESPACE} get gateway bookinfo-gateway --output jsonpath='{.spec.servers[0].hosts[0]}')
echo "   curl command: curl -Is -H 'Host: $HOST' $APP_URL"

echo "Load Generation: watch -x -n 0.1 curl -Is -H 'Host: $HOST' $APP_URL"