#!/bin/bash

# Check if a service name was provided
if [ $# -lt 1 ]; then
    echo "Error: Please provide a service name."
    echo "Usage: $0 <service-name> [namespace]"
    exit 1
fi

SERVICE_NAME="$1"
NAMESPACE="${2:-eidolon}"

# Get the Kubernetes context
CONTEXT=$(kubectl config current-context)

# Get the NodePort of the service
NODE_PORT=$(kubectl get svc "$SERVICE_NAME" --namespace="$NAMESPACE" -o=jsonpath='{.spec.ports[0].nodePort}')

# Check if NodePort is empty
if [ -z "$NODE_PORT" ]; then
    echo "Error: Couldn't find NodePort for '$SERVICE_NAME'. Make sure the service exists and is of type NodePort."
    exit 1
fi

# Determine the IP based on the context
if [[ $CONTEXT == "minikube" ]]; then
    IP=$(minikube ip)
elif [[ $CONTEXT == "docker-desktop" || $CONTEXT == "kind-"* ]]; then
    IP="localhost"
else
    # For other setups, try to get the internal IP of the first node
    IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
fi

# Ensure we only use the IPv4 address if multiple IPs are returned
IP=$(echo "$IP" | awk -F' ' '{print $1}')
echo "http://$IP:$NODE_PORT"
