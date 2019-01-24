#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

# User defined
KUBECONFIG="/Users/vvarza/git/github/qedzone/kubeadm-vagrant/src/output/kubeconfig.yaml"
KUBEMARK_KUBECONFIG=config/testing-cluster/kubemark.kubeconf
RESOURCE_DIRECTORY="config/kubemark/resources"
MASTER_IP="192.168.101.100"
NUM_NODES="${NUM_NODES:-1}"
DESIRED_NODES="${DESIRED_NODES:-1}"
ENABLE_KUBEMARK_CLUSTER_AUTOSCALER="${ENABLE_KUBEMARK_CLUSTER_AUTOSCALER:-true}"
ENABLE_KUBEMARK_KUBE_DNS="${ENABLE_KUBEMARK_KUBE_DNS:-false}"
KUBELET_TEST_LOG_LEVEL="${KUBELET_TEST_LOG_LEVEL:-"--v=10"}"
KUBEPROXY_TEST_LOG_LEVEL="${KUBEPROXY_TEST_LOG_LEVEL:-"--v=10"}"
USE_REAL_PROXIER=${USE_REAL_PROXIER:-false}
NODE_INSTANCE_PREFIX=${NODE_INSTANCE_PREFIX:-node}
TEST_CLUSTER_API_CONTENT_TYPE="${TEST_CLUSTER_API_CONTENT_TYPE:-}"
DNS_DOMAIN="${KUBE_DNS_DOMAIN:-cluster.local}"
HOLLOW_KUBELET_TEST_ARGS="--v=4 "
HOLLOW_PROXY_TEST_ARGS="--v=4 --use-real-proxier=false"

# Cloud information
RANDGEN=$(dd if=/dev/urandom bs=64 count=1 2>/dev/null | base64 | tr -d "=+/" | dd bs=16 count=1 2>/dev/null | sed 's/[A-Z]//g')
KUBE_NAMESPACE="kubemark_${RANDGEN}"
KUBEMARK_IMAGE_REGISTRY="qedzone"
KUBEMARK_IMAGE_TAG="latest"

# Create configmap for configuring hollow- kubelet, proxy and npd.
kubectl create configmap "node-configmap" --namespace="kubemark" \
    --from-literal=content.type="${TEST_CLUSTER_API_CONTENT_TYPE}" \
    --from-file=kernel.monitor="${RESOURCE_DIRECTORY}/kernel-monitor.json" \
    --dry-run -o yaml > config/helper-cluster/node-configmap.yaml

# Create secret for passing kubeconfigs to kubelet, kubeproxy and npd.
kubectl create secret generic "kubeconfig" --type=Opaque --namespace="kubemark" \
    --from-file=kubelet.kubeconfig="${KUBEMARK_KUBECONFIG}" \
    --from-file=kubeproxy.kubeconfig="${KUBEMARK_KUBECONFIG}" \
    --from-file=heapster.kubeconfig="${KUBEMARK_KUBECONFIG}" \
    --from-file=cluster_autoscaler.kubeconfig="${KUBEMARK_KUBECONFIG}" \
    --from-file=npd.kubeconfig="${KUBEMARK_KUBECONFIG}" \
    --from-file=dns.kubeconfig="${KUBEMARK_KUBECONFIG}" \
    --dry-run -o yaml > config/helper-cluster/kubeconfig-secret.yaml

# Create addon pods
# Heapster
mkdir -p "${RESOURCE_DIRECTORY}/addons"
sed "s/{{MASTER_IP}}/${MASTER_IP}/g" "${RESOURCE_DIRECTORY}/heapster_template.json" > "${RESOURCE_DIRECTORY}/addons/heapster.json"
metrics_mem_per_node=4
metrics_mem=$((200 + ${metrics_mem_per_node}*${NUM_NODES}))
sed -i'' -e "s/{{METRICS_MEM}}/${metrics_mem}/g" "${RESOURCE_DIRECTORY}/addons/heapster.json"
metrics_cpu_per_node_numerator=${NUM_NODES}
metrics_cpu_per_node_denominator=2
metrics_cpu=$((80 + metrics_cpu_per_node_numerator / metrics_cpu_per_node_denominator))
sed -i'' -e "s/{{METRICS_CPU}}/${metrics_cpu}/g" "${RESOURCE_DIRECTORY}/addons/heapster.json"
eventer_mem_per_node=500
eventer_mem=$((200 * 1024 + ${eventer_mem_per_node}*${NUM_NODES}))
sed -i'' -e "s/{{EVENTER_MEM}}/${eventer_mem}/g" "${RESOURCE_DIRECTORY}/addons/heapster.json"

# Cluster Autoscaler.
if [[ "${ENABLE_KUBEMARK_CLUSTER_AUTOSCALER:-}" == "true" ]]; then
    echo "Setting up Cluster Autoscaler"
    KUBEMARK_AUTOSCALER_MIG_NAME="${KUBEMARK_AUTOSCALER_MIG_NAME:-${NODE_INSTANCE_PREFIX}-group}"
    KUBEMARK_AUTOSCALER_MIN_NODES="${KUBEMARK_AUTOSCALER_MIN_NODES:-0}"
    KUBEMARK_AUTOSCALER_MAX_NODES="${KUBEMARK_AUTOSCALER_MAX_NODES:-${DESIRED_NODES}}"
    NUM_NODES=${KUBEMARK_AUTOSCALER_MAX_NODES}
    echo "Setting maximum cluster size to ${NUM_NODES}."
    KUBEMARK_MIG_CONFIG="autoscaling.k8s.io/nodegroup: ${KUBEMARK_AUTOSCALER_MIG_NAME}"
    sed "s/{{master_ip}}/${MASTER_IP}/g" "${RESOURCE_DIRECTORY}/cluster-autoscaler_template.json" > "${RESOURCE_DIRECTORY}/addons/cluster-autoscaler.json"
    sed -i'' -e "s/{{kubemark_autoscaler_mig_name}}/${KUBEMARK_AUTOSCALER_MIG_NAME}/g" "${RESOURCE_DIRECTORY}/addons/cluster-autoscaler.json"
    sed -i'' -e "s/{{kubemark_autoscaler_min_nodes}}/${KUBEMARK_AUTOSCALER_MIN_NODES}/g" "${RESOURCE_DIRECTORY}/addons/cluster-autoscaler.json"
    sed -i'' -e "s/{{kubemark_autoscaler_max_nodes}}/${KUBEMARK_AUTOSCALER_MAX_NODES}/g" "${RESOURCE_DIRECTORY}/addons/cluster-autoscaler.json"
fi

 # Kube DNS.
if [[ "${ENABLE_KUBEMARK_KUBE_DNS:-}" == "true" ]]; then
    echo "Setting up kube-dns"
    sed "s/{{dns_domain}}/${KUBE_DNS_DOMAIN}/g" "${RESOURCE_DIRECTORY}/kube_dns_template.yaml" > "${RESOURCE_DIRECTORY}/addons/kube_dns.yaml"
fi

# Create the replication controller for hollow-nodes.
# We allow to override the NUM_REPLICAS when running Cluster Autoscaler.

NUM_REPLICAS=${NUM_REPLICAS:-${NUM_NODES}}
sed "s/{{numreplicas}}/${NUM_REPLICAS}/g" "${RESOURCE_DIRECTORY}/hollow-node_template.yaml" > "${RESOURCE_DIRECTORY}/hollow-node.yaml"
proxy_cpu=20
if [ "${NUM_NODES}" -gt 1000 ]; then
    proxy_cpu=50
fi
proxy_mem_per_node=50
proxy_mem=$((100 * 1024 + ${proxy_mem_per_node}*${NUM_NODES}))
sed -i'' -e "s/{{HOLLOW_PROXY_CPU}}/${proxy_cpu}/g" "${RESOURCE_DIRECTORY}/hollow-node.yaml"
sed -i'' -e "s/{{HOLLOW_PROXY_MEM}}/${proxy_mem}/g" "${RESOURCE_DIRECTORY}/hollow-node.yaml"
sed -i'' -e "s'{{kubemark_image_registry}}'${KUBEMARK_IMAGE_REGISTRY}'g" "${RESOURCE_DIRECTORY}/hollow-node.yaml"
sed -i'' -e "s/{{kubemark_image_tag}}/${KUBEMARK_IMAGE_TAG}/g" "${RESOURCE_DIRECTORY}/hollow-node.yaml"
sed -i'' -e "s/{{master_ip}}/${MASTER_IP}/g" "${RESOURCE_DIRECTORY}/hollow-node.yaml"
sed -i'' -e "s/{{kubelet_verbosity_level}}/${KUBELET_TEST_LOG_LEVEL}/g" "${RESOURCE_DIRECTORY}/hollow-node.yaml"
sed -i'' -e "s/{{kubeproxy_verbosity_level}}/${KUBEPROXY_TEST_LOG_LEVEL}/g" "${RESOURCE_DIRECTORY}/hollow-node.yaml"
sed -i'' -e "s/{{use_real_proxier}}/${USE_REAL_PROXIER}/g" "${RESOURCE_DIRECTORY}/hollow-node.yaml"
sed -i'' -e "s'{{kubemark_mig_config}}'${KUBEMARK_MIG_CONFIG:-}'g" "${RESOURCE_DIRECTORY}/hollow-node.yaml"
sed -i'' -e "s/{{hollow_kubelet_params}}/${HOLLOW_KUBELET_TEST_ARGS}/g" "${RESOURCE_DIRECTORY}/hollow-node.yaml"
sed -i'' -e "s/{{hollow_proxy_params}}/${HOLLOW_PROXY_TEST_ARGS}/g" "${RESOURCE_DIRECTORY}/hollow-node.yaml"

# cp ${RESOURCE_DIRECTORY}/addons/* config/helper-cluster/
# cp ${RESOURCE_DIRECTORY}/hollow-node.yaml config/helper-cluster/
# kubectl apply -f config/helper-cluster/namespace.yaml
# kubectl -n kubemark apply -f config/helper-cluster/

echo "Created secrets, configMaps, replication-controllers required for hollow-nodes."