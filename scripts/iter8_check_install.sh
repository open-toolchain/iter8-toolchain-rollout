#!/bin/bash
# uncomment to debug the script
# set -x
# copy the script below into your app code repo (e.g. ./scripts/iter8_check_install.sh) and 'source' it from your pipeline job
#    source ./scripts/iter8_check_install.sh
# alternatively, you can source it from online script:
#    source <(curl -sSL "https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/iter8_check_install.sh")
# ------------------
# source: https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/iter8_check_install.sh

# Check iter8 installation in target cluster

# Input env variables from pipeline job

ITER8_NAMESPACE=iter8
ITER8_VERSION=${ITER8_VERSION:-"v0.2.1"}
echo "Checking iter8 configuration"
if kubectl get namespace ${ITER8_NAMESPACE}; then
  echo -e "Namespace ${ITER8_NAMESPACE} found."
else
  echo "iter8 not found, installing iter8"
  # https://github.com/iter8-tools/docs/blob/v0.2.1/doc_files/iter8_install.md#quick-installation
  source <(curl -sSL "https://raw.githubusercontent.com/iter8-tools/iter8-controller/${ITER8_VERSION}/install/install.sh")
fi

echo ""
echo "=========================================================="
echo -e "CHECKING installation status of iter8"
echo ""
for ITERATION in {1..30}
do
  DATA=$( kubectl get pods --namespace ${ITER8_NAMESPACE} -o json )
  NOT_READY=$(echo $DATA | jq '.items[].status | select(.containerStatuses!=null) | .containerStatuses[] | select(.ready==false and .state.terminated==null)')
  if [[ -z "$NOT_READY" ]]; then
    echo -e "All pods are ready:"
    break # iter8 installation succeeded
  fi
  echo -e "${ITERATION} : Deployment still pending..."
  echo -e "NOT_READY:${NOT_READY}"
  sleep 5
done

if [[ ! -z "$NOT_READY" ]]; then
  echo ""
  echo "=========================================================="
  echo "iter8 INSTALLATION CHECK : FAILED"
  echo "Please check that the target cluster meets the Istio system requirements (e.g. LITE clusters do not have enough capacity)."
  exit 1
fi
