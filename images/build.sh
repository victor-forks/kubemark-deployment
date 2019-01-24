#! /usr/bin/env bash

# first build kuberetes: make quick-release
# more details: https://github.com/kubernetes/community/blob/master/contributors/devel/kubemark-guide.md

KUBE_ROOT="$HOME/git/github/kubernetes"
KUBEMARK_IMAGE_LOCATION="${KUBEMARK_IMAGE_LOCATION:-${KUBE_ROOT}/cluster/images/kubemark}"
REGISTRY="qedzone"
PWD="$(pwd)"

echo $KUBEMARK_IMAGE_LOCATION

cp ${KUBE_ROOT}/_output/dockerized/bin/linux/amd64/kubemark ${KUBEMARK_IMAGE_LOCATION}
cd ${KUBEMARK_IMAGE_LOCATION}
make all

cd "$PWD"
echo "Image pushed"

