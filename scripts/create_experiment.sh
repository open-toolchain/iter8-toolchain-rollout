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
echo "IMAGE_NAME=${IMAGE_NAME}"
echo "IMAGE_TAG=${IMAGE_TAG}"
echo "BASELINE_VERSION=${BASELINE_VERSION}"
echo "CANARY_DEPLOYMENT_NAME=${CANARY_DEPLOYMENT_NAME}"
echo "EXPERIMENT_TEMPLATE_FILE=${EXPERIMENT_TEMPLATE_FILE}"

if [ -z "${EXPERIMENT_TEMPLATE_FILE}" ]; then EXPERIMENT_TEMPLATE_FILE=iter8_experiment.yaml ; fi
if [ ! -f ${EXPERIMENT_TEMPLATE_FILE} ]; then
  echo -e "${red}iter8 experiment template '${EXPERIMENT_TEMPLATE_FILE}' not found${no_color}"
fi

#WOW: APP_NAME=$( cat ${DEPLOYMENT_FILE} | yq r - -j | jq -r '. | select(.kind=="Deployment") | if (.metadata.labels.app) then .metadata.labels.app else .metadata.name end' )
NAME=$(yq read ${EXPERIMENT_TEMPLATE_FILE} metadata.name)
# export experimet name so can later patch it
export EXPERIMENT_NAME=${NAME}-${BUILD_NUMBER}
echo "EXPERIMENT_NAME=${EXPERIMENT_NAME}"

yq write --inplace ${EXPERIMENT_TEMPLATE_FILE} \
  metadata.name ${EXPERIMENT_NAME}
yq write --inplace ${EXPERIMENT_TEMPLATE_FILE} \
  spec.targetService.baseline ${BASELINE_VERSION}
yq write --inplace ${EXPERIMENT_TEMPLATE_FILE} \
  spec.targetService.candidate ${CANARY_DEPLOYMENT_NAME}
yq write --inplace ${EXPERIMENT_TEMPLATE_FILE} \
  spec.trafficControl.onSuccess baseline
cat ${EXPERIMENT_TEMPLATE_FILE}

kubectl --namespace ${CLUSTER_NAMESPACE} \
  apply --filename ${EXPERIMENT_TEMPLATE_FILE}
