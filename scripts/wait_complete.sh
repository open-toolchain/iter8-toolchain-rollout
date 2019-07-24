#!/bin/bash
# uncomment to debug the script
set -x
# copy the script below into your app code repo (e.g. ./scripts/wait_complete.sh) and 'source' it from your pipeline job
#    source ./scripts/create_deployment.sh
# alternatively, you can source it from online script:
#    source <(curl -sSL "https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/wait_complete.sh")
# ------------------
# source: https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/wait_complete.sh

# Create canary deployment yaml

# Constants
MAX_DURATION=$(( 59*60 ))
BASELINE="baseline"
CANDIDATE="candidate"

# Default values if not set
SLEEP_TIME=${SLEEP_TIME:-5}
DURATION=${DURATION:-$(( 59*60 ))}

# Validate ${DURARTION}
# If duration > 1 hr report warning in log and reset to 59 minutes
if $(( ${DURATION} > ${MAX_DURATION} )); then
    echo "WARNING: Unable to monitor rollout for more than 59 minutes"
    echo "  Setting duration to 59 minutes"
    DURATION=${MAX_DURATION}
fi

echo "  EXPERIMENT_NAME = $EXPERIMENT_NAME"
echo "CLUSTER_NAMESPACE = $CLUSTER_NAMESPACE"
echo "         DURATION = $DURATION"
echo "       SLEEP_TIME = $SLEEP_TIME"

get_experiment_status() {
  kubectl --namespace ${CLUSTER_NAMESPACE} \
    get experiment ${EXPERIMENT_NAME} \
    -o jsonpath='{.status.conditions[?(@.type=="ExperimentCompleted")].status}'
}

startS=$(date +%s)
timePassedS=0$(( $(date +%s) - $startS ))
while (( timePassedS < ${DURATION} )); do
  sleep ${SLEEP_TIME}

  eStatus=$(get_experiment_status)
  status=${eStatus:-"False"} # experiment might not have started
  if [[ "${status}" == "True" ]]; then
    # experiment is done; delete appropriate version
    # if baseline and candidate are the same then don't delete anything
    _baseline=$(kubectl --namespace ${CLUSTER_NAMESPACE} get experiment ${EXPERIMENT_NAME} -o jsonpath='{.spec.targetService.baseline}')
    _candidate=$(kubectl --namespace ${CLUSTER_NAMESPACE} get experiment ${EXPERIMENT_NAME} -o jsonpath='{.spec.targetService.candidate}')
    if [[ "${_baseline}" == "${_candidate}" ]]; then
      exit 0
    fi

    # determine deployment to delete
    _on_success=$(kubectl --namespace ${CLUSTER_NAMESPACE} get experiment ${EXPERIMENT_NAME} -o jsonpath='{.spec.trafficControl.onSuccess}')
    if [[ "${_on_success}" == "$BASELINE" ]]; then _version_to_delete="$CANDIDATE"
    elif [[ "${_on_success}" == "$CANDIDATE" ]]; then _version_to_delete="$BASELINE"
    elif [[ "${_on_success}" == "both" ]]; then exit 0 # both; don't delete anything
    else _version_to_delete="$CANDIDATE" # default if not set (or set incorrectly)
    fi
    
    # sanity check the trafficSplitPercentage
    _percentage=$(kubectl --namespace ${CLUSTER_NAMESPACE} get experiment ${EXPERIMENT_NAME} -o json | jq -r --arg v ${_version_to_delete} '.status.trafficSplitPercentage[$v]')
    if (( ${_percentage} != 0 )); then
        echo "ERROR: Expected traffic percentage to be 0; found it was ${_percentage}"
        exit 1
    fi
    if [[ "${_version_to_delete}" == "$BASELINE" ]]; then _deployment_to_delete=${_baseline};
    else _deployment_to_delete=${_candidate}; fi
    echo kubectl --namespace ${CLUSTER_NAMESPACE} delete deployment ${_deployment_to_delete}
    exit 0
  fi

  timePassedS=$(( $(date +%s) - $startS ))
done

# We've waited ${DURATION} for the experiment to complete
# It hasn't, so we log warning and fail. User becomes responsible for cleanup.
echo "WARNING: Did not complete experiment in ${DURATION}"
echo "   To check status of rollout: kubectl --namespace ${CLUSTER_NAMESPACE} experiment ${EXPERIMENT_NAME}"
echo "   To delete original version (successful rollout), trigger stage IMMEDIATE ROLLFORWARD"
echo "   To delete candidate version (failed rollout), trigger stage IMMEDIATE ROLLBACK"
exit 1
