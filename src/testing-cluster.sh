#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

KUBECONFIG="/Users/vvarza/Downloads/kubeadm-vagrant/src/output/kubeconfig.yaml"

kubectl apply -f ./config/testing-cluster/kubemark-sa.yaml
TOKEN_NAME=$(kubectl -n kube-system get secret | grep kubemark |  cut -d ' ' -f1)
TOKEN=$(kubectl -n kube-system get secret $TOKEN_NAME -o jsonpath='{.data.token}' | base64 -D)

CA_PATH="config/testing-cluster/ca.pem"
CA=$(cat $KUBECONFIG  | grep certificate-authority-data | cut -d ' ' -f6) && echo $CA | base64 -D > $CA_PATH
API_SERVER=$(cat $KUBECONFIG | grep server | cut -d ' ' -f6)

# generate kubeconfig
KUBELET_KUBECONF=config/testing-cluster/kubemark.kubeconf
kubectl --kubeconfig=$KUBELET_KUBECONF config set-credentials kubemark --user=kubemark --token=$TOKEN 
kubectl --kubeconfig=$KUBELET_KUBECONF config set-cluster testing-cluster --cluster=testing-cluster --server=$API_SERVER --certificate-authority=$CA_PATH --embed-certs
kubectl --kubeconfig=$KUBELET_KUBECONF config set-context kubemark-context --user=kubemark --cluster=testing-cluster
kubectl --kubeconfig=$KUBELET_KUBECONF config current-context kubemark-context
