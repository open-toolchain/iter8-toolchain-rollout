#!/bin/bash

# Uncomment to debug
#set -x

# Identify baseline deployment for an experiment
# This is heuristic; prefers to look at stable DestinationRule
# But if this isn't defined will select first deployment that satisfies
# the service selector (service from Experiment)

CONNECTOR='.'
NUM_DR=$(kubectl --namespace ${CLUSTER_NAMESPACE} get dr --selector=iter8${CONNECTOR}tools/role=stable --output json | jq '.items | length')
if (( ${NUM_DR} == 0 )); then
  CONNECTOR='-'
  NUM_DR=$(kubectl --namespace ${CLUSTER_NAMESPACE} get dr --selector=iter8${CONNECTOR}tools/role=stable --output json | jq '.items | length')
fi
if (( ${NUM_DR} == 0 )); then
  # No DestinationRule 
  DEPLOY_SELECTOR=""
else
  # Find the stable destination rule and the associetd deployment selector
  DEPLOY_SELECTOR=$(kubectl --namespace ${CLUSTER_NAMESPACE} get dr --selector=iter8${CONNECTOR}tools/role=stable -o json | jq -r '.items[0].spec.subsets[] | select(.name == "stable") | .labels | to_entries[] | "\(.key)=\(.value)"' | paste -sd',' -)
fi
if [ -z "$DEPLOY_SELECTOR" ]; then
  # No stable DestinationRule found so find the deployment(s) implementing $SERVICE
  SERVICE=$(yq read ${EXPERIMENT_TEMPLATE_FILE} spec.targetService.name)
  #SERVICE=$(kubectl --namespace ${CLUSTER_NAMESPACE} get experiments.iter8.tools ${EXPERIMENT_NAME} --output jsonpath='{.spec.targetService.name}')
  DEPLOY_SELECTOR=$(kubectl --namespace ${CLUSTER_NAMESPACE} get svc ${SERVICE} --output json | jq -r '.spec.selector | to_entries[] | "\(.key)=\(.value)"' | paste -sd',' -)
fi
echo "DEPLOY_SELECTOR=$DEPLOY_SELECTOR"
NUM_DEPLOY=$(kubectl --namespace ${CLUSTER_NAMESPACE} get deploy --selector=${DEPLOY_SELECTOR} --output json | jq '.items | length')

if (( ${NUM_DEPLOY} == 0 )); then
  BASELINE_DEPLOYMENT_NAME=
else
  BASELINE_DEPLOYMENT_NAME=$(kubectl --namespace ${CLUSTER_NAMESPACE} get deployment --selector=${DEPLOY_SELECTOR} --output jsonpath='{.items[0].metadata.name}') 
fi
echo "BASELINE_DEPLOYMENT_NAME=${BASELINE_DEPLOYMENT_NAME}" 
