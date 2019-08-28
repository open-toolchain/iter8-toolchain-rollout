#!/bin/bash
# uncomment to debug the script
# set -x
# copy the script below into your app code repo (e.g. ./scripts/create_deployment.sh) and 'source' it from your pipeline job
#    source ./scripts/create_deployment.sh
# alternatively, you can source it from online script:
#    source <(curl -sSL "https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/create_deployment.sh")
# ------------------
# source: https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/create_deployment.sh

# Create candidate deployment yaml


export DEPLOYMENT_FILE=deploy.yaml

if [ -z "${PATCH_FILE}" ]; then PATCH_FILE=kustomize_patch.yaml ; fi
if [ ! -f ${PATCH_FILE} ]; then
    echo -e "${red}kustomize patch file '${PATCH_FILE}' not found${no_color}"
fi

# Install kustomize
opsys=linux  # or darwin, or windows
curl -s https://api.github.com/repos/kubernetes-sigs/kustomize/releases/latest |\
    grep browser_download |\
    grep $opsys |\
    cut -d '"' -f 4 |\
    xargs curl -O -L
mv kustomize_*_${opsys}_amd64 /usr/local/bin/kustomize
chmod u+x /usr/local/bin/kustomize

# Modify patch file using $IMAGE_TAG as VERSION
PIPELINE_IMAGE_URL="$REGISTRY_URL/$REGISTRY_NAMESPACE/$IMAGE_NAME:$IMAGE_TAG"
sed -i -e "s#iter8/reviews:istio-VERSION#$PIPELINE_IMAGE_URL#" ${PATCH_FILE}
sed -i -e "s#VERSION#${IMAGE_TAG}#g" ${PATCH_FILE}
cat ${PATCH_FILE}

# Create deployment yaml with kustomize build
kustomize build kustomize -o ${DEPLOYMENT_FILE}
