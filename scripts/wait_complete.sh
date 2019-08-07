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

get_experiment_status() {
  kubectl --namespace ${CLUSTER_NAMESPACE} \
    get experiment ${EXPERIMENT_NAME} \
    -o jsonpath='{.status.conditions[?(@.type=="ExperimentCompleted")].status}'
}

log() {
  echo "$@"
  echo "       Reason: $(kubectl --namespace ${CLUSTER_NAMESPACE} \
    get experiment ${EXPERIMENT_NAME} \
    -o jsonpath='{.status.conditions[?(@.type=="Ready")].reason}')"
  echo "   Assessment: $(kubectl --namespace ${CLUSTER_NAMESPACE} \
    get experiment ${EXPERIMENT_NAME} \
    -o jsonpath='{.status.assessment.conclusions}')"
}

startS=$(date +%s)
timePassedS=0$(( $(date +%s) - $startS ))
while (( timePassedS < ${DURATION} )); do
  sleep ${SLEEP_TIME}

  eStatus=$(get_experiment_status)
  status=${eStatus:-"False"} # experiment might not have completed
  if [[ "${status}" == "True" ]]; then
    # experiment is done; delete appropriate version
    # if baseline and candidate are the same then don't delete anything
    _baseline=$(kubectl --namespace ${CLUSTER_NAMESPACE} get experiment ${EXPERIMENT_NAME} -o jsonpath='{.spec.targetService.baseline}')
    _candidate=$(kubectl --namespace ${CLUSTER_NAMESPACE} get experiment ${EXPERIMENT_NAME} -o jsonpath='{.spec.targetService.candidate}')
    echo "         _baseline = ${_baseline}"
    echo "        _candidate = ${_candidate}"
    if [[ "${_baseline}" == "${_candidate}" ]]; then
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
    else exit 0 # don't delete a version since traffic is still split
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
      log "Experiment terminated (${_assessment}) unexpectedly in stage ${IDS_STAGE_NAME}"
      exit 1
    fi

    # Read reason from experiment 
    _reason=$(kubectl --namespace ${CLUSTER_NAMESPACE} \
                get experiment ${EXPERIMENT_NAME} \
                --output jsonpath='{.status.conditions[?(@.type=="Ready")].reason}')
    echo "_reason=${_reason}"

    # Handle experiment FAILURE
    if [[ -n ${_reason} ]] && [[ "${_reason}" =~ ^ExperimentFailure:.* ]]; then

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

    # # In order to determine the status of this step, we need to know if the version we deleted
    # # is the one we expected to delete.
    # # In the normal case, we inspect the spec.trafficControl.onSuccess
    # # In the exception case (a user forced a termination), we inspect spec.assessment
    # # To decide which case to consider, we look to see if $FORCE_TERMINATION is defined
    # _assessment=$(kubectl --namespace ${CLUSTER_NAMESPACE} get experiment ${EXPERIMENT_NAME} -o jsonpath='{.spec.assessment}')
    # echo "       _assessment = ${_assessment}"
    # if [[ -n $FORCE_TERMINATION ]]; then
    #   if [[ -z ${_version_to_delete} ]]; then
    #     echo "ERROR: Experiment ${EXPERIMENT_NAME} was manuually terminated but no version could be identified to delete."
    #     exit 1
    #   fi
    #   if [[ -z ${_assessment} ]]; then
    #     echo "ERROR: Expected experiment ${EXPERIMENT_NAME} to have been manually terminated but spec.assessment not set."
    #     exit 1
    #   fi
    #   if [[ "${_assessment}" == "${OVERRIDE_SUCCESS}" ]]; then
    #     if [[ "${_version_to_delete}" == "${BASELINE}" ]]; then exit 0;
    #     else 
    #       echo "ERROR: Experiment ${EXPERIMENT_NAME} was rolled forward. However ${CANDIDATE} version ${_deployment_to_delete} was deleted instead of baseline."
    #       exit 1
    #     fi
    #   elif [[ "${_assessment}" == "${OVERRIDE_FAILURE}" ]]; then
    #     if [[ "${_version_to_delete}" == "${CANDIDATE}" ]]; then exit 0;
    #     else 
    #       echo "ERROR: Experiment ${EXPERIMENT_NAME} was rolled back. However ${BASELINE} version ${_deployment_to_delete} was deleted instead of candidate."
    #       exit 1
    #     fi
    #   else # unknown value in spec.assessment
    #     echo "ERROR: Invalid value specified for spec.assessment in experiment ${EXPERIMENT_NAME}"
    #     exit 1
    #   fi
    # fi

    # if [[ -n ${_assessment} ]] && [[ -z ${FORCE_TERMINATION} ]]; then
    #   echo "WARNING: spec.assessment unexpectedly set in experiment ${EXPERIMENT_NAME}"
    # fi

    # # if $FORCE_TERMINATION was not set look at _on_success
    # _on_success=$(kubectl --namespace ${CLUSTER_NAMESPACE} get experiment ${EXPERIMENT_NAME} -o jsonpath='{.spec.trafficControl.onSuccess}')
    # echo "       _on_success = ${_on_success}"
    # if [[ -z ${_on_success} ]]; then _on_success="${CANDIDATE}"; fi
    # if [[ "${_on_success}" == "$BASELINE" ]]; then
    #   if [[ "${_version_to_delete}" == "${CANDIDATE}" ]]; then exit 0;
    #   else
    #     echo "ERROR: Desired final version is ${BASELINE} version ${_baseline}"
    #     echo "       However, it (${_deployment_to_delete}) was deleted, perhaps due to manual intervention."
    #     exit 1
    #   fi
    # elif [[ "${_on_success}" == "$CANDIDATE" ]]; then
    #   if [[ "${_version_to_delete}" == "${BASELINE}" ]]; then exit 0;
    #   else
    #     echo "ERROR: Desired final version is ${CANDIDATE} version ${_candidate}"
    #     echo "       However, it (${_deployment_to_delete}) was deleted, perhaps due to manual intervention."
    #     exit 1
    #   fi
    # elif [[ "${_on_success}" == "both" ]]; then exit 0;
    # fi

  fi # if [[ "${status}" == "True" ]]

  timePassedS=$(( $(date +%s) - $startS ))
done

# We've waited ${DURATION} for the experiment to complete
# It hasn't, so we log warning and fail. User becomes responsible for cleanup.
echo "WARNING: Did not complete experiment in ${DURATION}"
echo "   To check status of rollout: kubectl --namespace ${CLUSTER_NAMESPACE} experiment ${EXPERIMENT_NAME}"
echo "   To delete original version (successful rollout), trigger stage IMMEDIATE ROLLFORWARD"
echo "   To delete candidate version (failed rollout), trigger stage IMMEDIATE ROLLBACK"
exit 1
