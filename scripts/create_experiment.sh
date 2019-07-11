#!/bin/bash
# uncomment to debug the script
# set -x
# copy the script below into your app code repo (e.g. ./scripts/istio_check_install.sh) and 'source' it from your pipeline job
#    source ./scripts/create_experiment.sh
# alternatively, you can source it from online script:
#    source <(curl -sSL "https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/create_experiment.sh")
# ------------------
# source: https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/create_experiment.sh

# Create iter8 experiment in target cluster/namespace

# Input env variables from pipeline job
echo "PIPELINE_KUBERNETES_CLUSTER_NAME=${PIPELINE_KUBERNETES_CLUSTER_NAME}"
echo "CLUSTER_NAMESPACE=${CLUSTER_NAMESPACE}"
echo "IMAGE_TAG=${IMAGE_TAG}"
echo "BASELINE_VERSION=${BASELINE_VERSION}"
echo "CANARY_VERSION=${CANARY_VERSION}"

if [ -z "${EXPERIMENT_TEMPLATE_FILE}" ]; then EXPERIMENT_TEMPLATE_FILE=iter8_experiment.yaml ; fi
if [ ! -f ${EXPERIMENT_TEMPLATE_FILE} ]; then
  echo -e "Inferring experiment using Kubernetes deployment yaml file : ${DEPLOYMENT_FILE}"
  if [ -z "${DEPLOYMENT_FILE}" ]; then DEPLOYMENT_FILE=deployment.yml ; fi
  if [ ! -f ${DEPLOYMENT_FILE} ]; then
      echo -e "${red}Kubernetes deployment file '${DEPLOYMENT_FILE}' not found${no_color}"
      exit 1
  fi
  # read app name if present, if not default to deployment name
  APP_NAME=$( cat ${DEPLOYMENT_FILE} | yq r - -j | jq -r '. | select(.kind=="Deployment") | if (.metadata.labels.app) then .metadata.labels.app else .metadata.name end' ) # read deployment name  
  cat > ${EXPERIMENT_TEMPLATE_FILE} << EOF
apiVersion: iter8.tools/v1alpha1
kind: Experiment
metadata:
  name: reviews-12
  labels:
    app.kubernetes.io/name: reviews
spec:
  targetService:
    name: reviews
    apiVersion: v1
    baseline: reviews-v2
    candidate: reviews-v3
  trafficControl:
    strategy: check_and_increment
    interval: 30s
    trafficStepSize: 20
    maxIterations: 8
    maxTrafficPercentage: 80
  analysis:
    analyticsService: http://iter8-analytics.iter8
    successCriteria:
    - metricName: iter8_latency
      toleranceType: threshold
      tolerance: 0.2
      sampleSize: 6
EOF
  #sed -e "s/\${DEPLOYMENT_NAME}/${DEPLOYMENT_NAME}/g" ${VIRTUAL_SERVICE_FILE}
fi

#WOW APP_NAME=$( cat ${DEPLOYMENT_FILE} | yq r - -j | jq -r '. | select(.kind=="Deployment") | if (.metadata.labels.app) then .metadata.labels.app else .metadata.name end' )
NAME=$(yq read ${EXPERIMENT_TEMPLATE_FILE} metadata.name)
yq write --inplace ${EXPERIMENT_TEMPLATE_FILE} \
  metadata.name ${NAME}-$(echo ${IMAGE_NAME} | cut -d- -f1)
yq write --inplace ${EXPERIMENT_TEMPLATE_FILE} \
  spec.targetService.baseline ${BASELINE_VERSION}
yq write --inplace ${EXPERIMENT_TEMPLATE_FILE} \
  spec.targetService.candidate ${CANARY_VERSION}
cat ${EXPERIMENT_TEMPLATE_FILE}

kubectl --namespace ${CLUSTER_NAMESPACE} \
  apply --filename ${EXPERIMENT_TEMPLATE_FILE}
