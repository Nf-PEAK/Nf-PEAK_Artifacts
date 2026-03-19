#!/bin/bash

# --- Config ---
NAMESPACE="username"
NODE_POD="nfpeak-pod-c37"  # For testing, one node only
REMOTE_PATH="/private-data/energy-attribution/pod_uids.tsv"
LOCAL_TMP="pod_uids.tsv"

# --- 1. Find the latest workflow sessionId ---
echo "🔍 Detecting latest Nextflow workflow ID..."
WORKFLOW_ID=$(kubectl get pods -n "$NAMESPACE" -o json \
  | jq -r '.items[].metadata.labels["nextflow.io/sessionId"]' \
  | grep -v null | sed 's/^uuid-//' | sort | tail -n 1)

if [[ -z "$WORKFLOW_ID" ]]; then
    echo "❌ Could not detect a valid Nextflow workflow ID."
    exit 1
fi

echo "✅ Detected workflow ID: $WORKFLOW_ID"

# --- 2. Get all pods belonging to that workflow ---
#echo "🔍 Fetching pod UIDs for workflow $WORKFLOW_ID..."
#kubectl get pods -n "$NAMESPACE" -o json \
#  | jq -r --arg sid "uuid-$WORKFLOW_ID" \
#    '.items[] | select(.metadata.labels["nextflow.io/sessionId"] == $sid) | [.metadata.name, .metadata.uid] | @tsv' \
#    > "$LOCAL_TMP"
#
#if [[ ! -s "$LOCAL_TMP" ]]; then
#    echo "❌ No pods found for workflow ID $WORKFLOW_ID"
#    exit 1
#fi

# --- 2. Get all pods belonging to that workflow ---
echo "🔍 Fetching pod UIDs for workflow $WORKFLOW_ID..."
kubectl get pods -n "$NAMESPACE" -o json \
  | jq -r --arg sid "uuid-$WORKFLOW_ID" \
    '.items[]
     | select(.metadata.labels["nextflow.io/sessionId"] == $sid)
     | [.metadata.name,
        .metadata.uid,
        (.metadata.labels["nextflow.io/taskName"] // "unknown")]
     | @tsv' \
    > "$LOCAL_TMP"

echo "✅ Found $(wc -l < "$LOCAL_TMP") task pods. Copying UID list to node..."

# --- 3. Copy UID list to Nf-PEAK pod ---
kubectl cp "$LOCAL_TMP" "$NAMESPACE/$NODE_POD:$REMOTE_PATH"

# --- 4. Trigger mapping on the node ---
echo "🚀 Starting remote PID mapping..."
kubectl exec -n "$NAMESPACE" "$NODE_POD" -- bash /private-data/energy-attribution/map_pids_from_uids_node37.sh "$REMOTE_PATH"
kubectl exec -n "$NAMESPACE" "nfpeak-pod-c38" -- bash /private-data/energy-attribution/map_pids_from_uids_node38.sh "$REMOTE_PATH"

echo "✅ Done."
