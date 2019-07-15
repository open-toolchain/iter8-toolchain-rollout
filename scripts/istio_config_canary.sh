#!/bin/bash
# uncomment to debug the script
# set -x
# copy the script below into your app code repo (e.g. ./scripts/config_istio_canary.sh) and 'source' it from your pipeline job
#    source ./scripts/config_istio_canary.sh
# alternatively, you can source it from online script:
#    source <(curl -sSL "https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/config_istio_canary.sh")
# ------------------
# source: https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/config_istio_canary.sh

# Configure Istio gateway with a destination rule (stable/canary), and virtual service

# Input env variables from pipeline job
echo "PIPELINE_KUBERNETES_CLUSTER_NAME=${PIPELINE_KUBERNETES_CLUSTER_NAME}"
echo "IMAGE_NAME=${IMAGE_NAME}"
echo "CLUSTER_NAMESPACE=${CLUSTER_NAMESPACE}"
echo "DEPLOYMENT_FILE=${DEPLOYMENT_FILE}"

#Check namespace availability
echo "=========================================================="
echo "CHECKING CLUSTER readiness and namespace existence"
if kubectl get namespace ${CLUSTER_NAMESPACE}; then
  echo -e "Namespace ${CLUSTER_NAMESPACE} found."
else
  kubectl create namespace ${CLUSTER_NAMESPACE}
  echo -e "Namespace ${CLUSTER_NAMESPACE} created."
fi

echo "=========================================================="
echo "CHECK SIDECAR is automatically injected"
AUTO_SIDECAR_INJECTION=$(kubectl get namespace ${CLUSTER_NAMESPACE} -o json | jq -r '.metadata.labels."istio-injection"')
if [ "${AUTO_SIDECAR_INJECTION}" == "enabled" ]; then
    echo "Automatic Istio sidecar injection already enabled"
else
    # https://istio.io/docs/setup/kubernetes/sidecar-injection/#automatic-sidecar-injection
    kubectl label namespace ${CLUSTER_NAMESPACE} istio-injection=enabled
    echo "Automatic Istio sidecar injection now enabled"
    kubectl get namespace ${CLUSTER_NAMESPACE} -L istio-injection
fi

echo "=========================================================="
echo "CONFIGURE GATEWAY with 2 subsets 'stable' and 'canary'. Initially routing all traffic to 'stable' subset".
if [ -z "${ISTIO_CONFIG_FILE}" ]; then ISTIO_CONFIG_FILE=istio_config.yaml ; fi
if [ ! -f ${ISTIO_CONFIG_FILE} ]; then
  echo -e "Inferring gateway configuration using Kubernetes deployment yaml file : ${DEPLOYMENT_FILE}"
  if [ -z "${DEPLOYMENT_FILE}" ]; then DEPLOYMENT_FILE=deployment.yml ; fi
  if [ ! -f ${DEPLOYMENT_FILE} ]; then
      echo -e "${red}Kubernetes deployment file '${DEPLOYMENT_FILE}' not found${no_color}"
      exit 1
  fi
  # read app name if present, if not default to deployment name (using yq to translate yaml into json)
  APP_NAME=$( cat ${DEPLOYMENT_FILE} | yq r - -j | jq -r '. | select(.kind=="Deployment") | if (.metadata.labels.app) then .metadata.labels.app else .metadata.name end' ) # read deployment name
  cat > ${ISTIO_CONFIG_FILE} << EOF
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: virtual-service-${APP_NAME}
spec:
  hosts:
  - ${APP_NAME}
  http:
  - route:
    - destination:
        host: ${APP_NAME}
        port: {}
        subset: stable
      weight: 100
---
apiVersion: networking.istio.io/v1alpha3
kind: DestinationRule
metadata:
  name: destination-rule-${APP_NAME}
spec:
  host: ${APP_NAME}
  subsets:
  - name: stable
    labels:
      app: reviews
      version: v2
EOF
fi
cat ${ISTIO_CONFIG_FILE}
kubectl apply -f ${ISTIO_CONFIG_FILE} --namespace ${CLUSTER_NAMESPACE}
