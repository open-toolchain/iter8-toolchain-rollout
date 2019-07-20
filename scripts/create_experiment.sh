#!/bin/bash
# uncomment to debug the script
# set -x
# copy the script below into your app code repo (e.g. ./scripts/create_experiment.sh) and 'source' it from your pipeline job
#    source ./scripts/create_experiment.sh
# alternatively, you can source it from online script:
#    source <(curl -sSL "https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/create_experiment.sh")
# ------------------
# source: https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/create_experiment.sh

# Create iter8 experiment in target cluster/namespace

# Input env variables from pipeline job
echo "EXPERIMENT_TEMPLATE_FILE=${EXPERIMENT_TEMPLATE_FILE}"
echo "EXPERIMENT_NAME=${EXPERIMENT_NAME}"
echo "BASELINE_DEPLOYMENT_NAME=${BASELINE_DEPLOYMENT_NAME}"
echo "CANARY_DEPLOYMENT_NAME=${CANARY_DEPLOYMENT_NAME}"
echo "ON_SUCCESS=${ON_SUCCESS}"
echo "CLUSTER_NAMESPACE=${CLUSTER_NAMESPACE}"

# Fail early if no experient template
if [ -z "${EXPERIMENT_TEMPLATE_FILE}" ]; then EXPERIMENT_TEMPLATE_FILE=iter8_experiment.yaml ; fi
if [ ! -f ${EXPERIMENT_TEMPLATE_FILE} ]; then
  echo -e "${red}iter8 experiment template '${EXPERIMENT_TEMPLATE_FILE}' not found${no_color}"
fi

# Update experiment update
yq write --inplace ${EXPERIMENT_TEMPLATE_FILE} metadata.name ${EXPERIMENT_NAME}
yq write --inplace ${EXPERIMENT_TEMPLATE_FILE} spec.targetService.baseline ${BASELINE_DEPLOYMENT_NAME}
yq write --inplace ${EXPERIMENT_TEMPLATE_FILE} spec.targetService.candidate ${CANARY_DEPLOYMENT_NAME}
yq write --inplace ${EXPERIMENT_TEMPLATE_FILE} spec.trafficControl.onSuccess ${ON_SUCCESS}

cat ${EXPERIMENT_TEMPLATE_FILE}

# Create experiment in cluster
kubectl --namespace ${CLUSTER_NAMESPACE} apply --filename ${EXPERIMENT_TEMPLATE_FILE}
