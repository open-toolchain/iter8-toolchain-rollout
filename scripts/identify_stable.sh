#!/bin/bash

# Uncomment to debug
#set -x

# Identify baseline deployment for an experiment
# This is heuristic; prefers to look at stable DestinationRule
# But if this isn't defined will select first deployment that satisfies
# the service selector (service from Experiment)

NUM_DR=$(kubectl --namespace ${CLUSTER_NAMESPACE} get dr --selector=iter8.tools/role=stable --output json | jq '.items | length')
if (( ${NUM_DR} == 0 )); then
  # Find deployment(s) implementing $SERVICE
  SERVICE=$(kubectl --namespace ${CLUSTER_NAMESPACE} get experiment ${EXPERIMENT_NAME} --output jsonpath='{.spec.targetService.name}')
  DEPLOY_SELECTOR=$(kubectl --namespace ${CLUSTER_NAMESPACE} get svc ${SERVICE} --output json | jq -r '.spec.selector | to_entries[] | "\(.key)=\(.value)"' | paste -sd',' -)
else
  DEPLOY_SELECTOR=$(kubectl --namespace ${CLUSTER_NAMESPACE} get dr --selector=iter8.tools/role=stable -o json | jq -r '.items[0].spec.subsets[] | select(.name == "stable") | .labels | to_entries[] | "\(.key)=\(.value)"' | paste -sd',' -)
fi

NUM_DEPLOY=$(kubectl --namespace ${CLUSTER_NAMESPACE} get deploy --selector=${DEPLOY_SELECTOR} --output json | jq '.items | length')

if (( ${NUM_DEPLOY} == 0 )); then
  BASELINE_DEPLOYMENT_NAME=
else
  BASELINE_DEPLOYMENT_NAME=$(kubectl --namespace ${CLUSTER_NAMESPACE} get deployment --selector=${DEPLOY_SELECTOR} --output jsonpath='{.items[0].metadata.name}') echo "${BASELINE_DEPLOYMENT_NAME}" 
fi
