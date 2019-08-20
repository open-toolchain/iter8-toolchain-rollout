#!/bin/bash
# uncomment to debug the script
#set -x
# copy the script below into your app code repo (e.g. ./scripts/wait_complete.sh) and 'source' it from your pipeline job
#    source ./scripts/wait_complete.sh
# alternatively, you can source it from online script:
#    source <(curl -sSL "https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/wait_complete.sh")
# ------------------
# source: https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/wait_complete.sh

# Wait for experiment $EXPERIMENT_NAME to complete
# AND delete the inactive deployment

# Constants
MAX_DURATION=$(( 59*60 ))
PHASE_SUCCEEDED="Succeeded"
PHASE_FAILED="Failed"
BASELINE="baseline"
CANDIDATE="candidate"
OVERRIDE_FAILURE="override_failure"
OVERRIDE_SUCCESS="override_success"

# Default values if not set
SLEEP_TIME=${SLEEP_TIME:-5}
DURATION=${DURATION:-$(( 59*60 ))}

# Validate ${DURARTION}
# If duration > 1 hr report warning in log and reset to 59 minutes
if (( ${DURATION} > ${MAX_DURATION} )); then
    echo "WARNING: Unable to monitor rollout for more than 59 minutes"
    echo "  Setting duration to 59 minutes"
    DURATION=${MAX_DURATION}
fi

echo "   EXPERIMENT_NAME = $EXPERIMENT_NAME"
echo " CLUSTER_NAMESPACE = $CLUSTER_NAMESPACE"
echo "          DURATION = $DURATION"
echo "        SLEEP_TIME = $SLEEP_TIME"
echo " FORCE_TERMINATION = $FORCE_TERMINATION"
echo "    IDS_STAGE_NAME = $IDS_STAGE_NAME"

get_experiment_phase() {
  kubectl --namespace ${CLUSTER_NAMESPACE} \
    get experiment ${EXPERIMENT_NAME} \
    -o jsonpath='{.status.phase}'
}

log() {
  echo "$@"
  echo "         Message: $(kubectl --namespace ${CLUSTER_NAMESPACE} \
    get experiment ${EXPERIMENT_NAME} \
    --output jsonpath='{.status.message}')"
  echo "      Assessment: $(kubectl --namespace ${CLUSTER_NAMESPACE} \
    get experiment ${EXPERIMENT_NAME} \
    --output jsonpath='{.status.assessment.conclusions}')"
  echo "Canary Dashboard:"
  kubectl --namespace ${CLUSTER_NAMESPACE} get experiment ${EXPERIMENT_NAME} --output jsonpath='{.status.grafanaURL}'
  echo ""
}

startS=$(date +%s)
timePassedS=0$(( $(date +%s) - $startS ))
while (( timePassedS < ${DURATION} )); do
  sleep ${SLEEP_TIME}

  phase=$(get_experiment_phase)
  if [[ "${phase}" == "${PHASE_SUCCEEDED}" ]] || [[ "${phase}" == "${PHASE_FAILED}" ]]; then
    # experiment is done; delete appropriate version
    # if baseline and candidate are the same then don't delete anything
    _baseline=$(kubectl --namespace ${CLUSTER_NAMESPACE} get experiment ${EXPERIMENT_NAME} -o jsonpath='{.spec.targetService.baseline}')
    _candidate=$(kubectl --namespace ${CLUSTER_NAMESPACE} get experiment ${EXPERIMENT_NAME} -o jsonpath='{.spec.targetService.candidate}')
    echo "         _baseline = ${_baseline}"
    echo "        _candidate = ${_candidate}"
    if [[ "${_baseline}" == "${_candidate}" ]]; then
      log "Stage ${IDS_STAGE_NAME} successfully completes"
      exit 0
    fi

    # To determine which version to delete: look at traffic split
    _b_traffic=$(kubectl --namespace ${CLUSTER_NAMESPACE} get experiment ${EXPERIMENT_NAME} -o jsonpath='{.status.trafficSplitPercentage.baseline}')
    _c_traffic=$(kubectl --namespace ${CLUSTER_NAMESPACE} get experiment ${EXPERIMENT_NAME} -o jsonpath='{.status.trafficSplitPercentage.candidate}')
    echo " baseline traffic is ${_b_traffic}"
    echo "candidate traffic is ${_c_traffic}"

    # Select the one not receiving any traffic
    _version_to_delete=
    if (( ${_b_traffic} == 0 )); then _version_to_delete="$BASELINE";
    elif (( ${_c_traffic} == 0 )); then _version_to_delete="$CANDIDATE";
    else 
      log "Stage ${IDS_STAGE_NAME} successfully completes"
      exit 0 # don't delete a version since traffic is still split
    fi
    echo "_version_to_delete = ${_version_to_delete}"

    # Delete it
    _deployment_to_delete=
    if [[ "${_version_to_delete}" == "$BASELINE" ]]; then _deployment_to_delete=${_baseline};
    elif [[ "${_version_to_delete}" == "$CANDIDATE" ]]; then _deployment_to_delete=${_candidate};
    else _deployment_to_delete=${_candidate}; fi
    if [[ -n ${_deployment_to_delete} ]]; then
      kubectl --namespace ${CLUSTER_NAMESPACE} delete deployment ${_deployment_to_delete} --ignore-not-found
    fi

    # Determine the end status for this toolchain stage.
    # This depends on the experiment status as well as the stage. 
    # For example, in the IMMEDIATE ROLLBACK stage, we expect the experiment to fail.

    # First consider two unexpeted conditions that always result in failure. These are around
    # and inconsistency in .spec.assessment and $FORCE_TERMINATION (set by IMMEDIATE ROLLBACK and
    # IMMEDIATE ROLLFORWARD)
    _assessment=$(kubectl --namespace ${CLUSTER_NAMESPACE} get experiment ${EXPERIMENT_NAME} -o jsonpath='{.spec.assessment}')
    echo "       _assessment = ${_assessment}"
    if [[ -n ${FORCE_TERMINATION} ]] && [[ -z ${_assessment} ]]; then
      log "Attempt to terminate experiment in stage ${IDS_STAGE_NAME} but success/failure not specified."
      exit 1
    fi
    if [[ -z ${FORCE_TERMINATION} ]] && [[ -n ${_assessment} ]] && [[ "${_assessment}" == "${OVERRIDE_FAILURE}" ]]; then
      # This occurs if the spec.assessment field is patched external to the toolchain
      # Since $FORCE_TERMINATION is not set, is in ROLLOUT CANDIDATE
      # If $_assessment is override_failure --> fail
      # Otherwise, let the remaining logic deal with it
      log "Experiment terminated (${_assessment}) unexpectedly in stage ${IDS_STAGE_NAME}"
      exit 1
    fi
    # the other alternative, [[ "${_assessment}" == "${OVERRIDE_SUCCESS}" ]], occurs if a user
    # manually (outside the toochain) overrides behavior. In this case

    # Read reason from experiment 
    _reason=$(kubectl --namespace ${CLUSTER_NAMESPACE} \
                get experiment ${EXPERIMENT_NAME} \
                --output jsonpath='{.status.conditions[?(@.type=="Ready")].reason}')
    echo "_reason=${_reason}"

    # Handle experiment FAILURE
    if [[ "${phase}" == "${PHASE_FAILED}" ]]; then
      # called from IMMEDIATE ROLLBACK
      if [[ -n ${FORCE_TERMINATION} ]] && [[ "${_assessment}" == "${OVERRIDE_FAILURE}" ]]; then
        log 'IMMEDIATE ROLLBACK called: experiment successfully rolled back'
        exit 0
      fi

      # called from IMMEDIATE ROLLFORWARD
      if [[ -n ${FORCE_TERMINATION} ]] && [[ "${_assessment}" == "${OVERRIDE_SUCCESS}" ]]; then
        log 'IMMEDIATE ROLLFORWARD called: experiment failed to rollforward'
        exit 1
      fi

      # called from ROLLOUT CANDIDATE
      log 'ROLLOUT CANDIDATE: Experiment failed'
      exit 1

    # Handle experiment SUCCESS
    else
      # called from IMMEDIATE ROLLBACK
      if [[ -n ${FORCE_TERMINATION} ]] && [[ "${_assessment}" == "${OVERRIDE_FAILURE}" ]]; then
        log 'IMMEDIATE ROLLBACK called: experiment not rolled back; it successfully completed before rollback could be implemented'
        exit 1
      fi

      # called from IMMEDIATE ROLLFORWARD
      if [[ -n ${FORCE_TERMINATION} ]] && [[ "${_assessment}" == "${OVERRIDE_SUCCESS}" ]]; then
        log 'IMMEDIATE ROLLFORWARD called: experiment successfully rolled forward'
        exit 0
      fi

      # called from ROLLOUT CANDIDATE
      log 'ROLLOUT CANDIDATE: Experiment succeeded'
      exit 0
    fi

  fi # if [[ "${phase}" == "${PHASE_SUCCEEDED}" ]] || [[ "${phase}" == "${PHASE_FAILED}" ]]; then

  timePassedS=$(( $(date +%s) - $startS ))
done

# We've waited ${DURATION} for the experiment to complete
# It hasn't, so we log warning and fail. User becomes responsible for cleanup.
echo "WARNING: Stage ${IDS_STAGE_NAME} did not complete experiment in ${DURATION}"
echo "   To check status of rollout: kubectl --namespace ${CLUSTER_NAMESPACE} experiment ${EXPERIMENT_NAME}"
echo "   To delete original version (successful rollout), trigger stage IMMEDIATE ROLLFORWARD"
echo "   To delete candidate version (failed rollout), trigger stage IMMEDIATE ROLLBACK"
log "WARNING: Stage ${IDS_STAGE_NAME} did not complete experiment in ${DURATION}s"
exit 1
