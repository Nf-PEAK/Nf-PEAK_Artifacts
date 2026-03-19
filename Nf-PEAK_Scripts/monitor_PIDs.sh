#!/bin/bash

# Delete old resources
kubectl exec -n username -it nfpeak-pod-c37 -- rm -f /private-data/energy-attribution/pid_map_result_node37.log
kubectl exec -n username -it nfpeak-pod-c38 -- rm -f /private-data/energy-attribution/pid_map_result_node38.log
kubectl exec -n username -it nfpeak-pod-c37 -- rm -f /private-data/energy-attribution/pids_already_monitored_node37.txt
kubectl exec -n username -it nfpeak-pod-c38 -- rm -f /private-data/energy-attribution/pids_already_monitored_node38.txt
kubectl exec -n username -it nfpeak-pod-c37 -- rm -rf /private-data/energy-attribution/data_node37
kubectl exec -n username -it nfpeak-pod-c38 -- rm -rf /private-data/energy-attribution/data_node38

# Create directories for Nf-PEAK data storage
kubectl exec -n username -it nfpeak-pod-c37 -- mkdir -p /private-data/energy-attribution/data_node37
kubectl exec -n username -it nfpeak-pod-c38 -- mkdir -p /private-data/energy-attribution/data_node38

# Logging basepower
sleep 10
kubectl exec -n username nfpeak-pod-c37 -- bash -c 'echo "⚡ Computing basepower for node 37" >> /private-data/energy-attribution/pid_map_result_node37.log'
kubectl exec -n username nfpeak-pod-c38 -- bash -c 'echo "⚡ Computing basepower for node 38" >> /private-data/energy-attribution/pid_map_result_node38.log'

# Confirm logging
kubectl exec -n username nfpeak-pod-c37 -- tail -n 5 /private-data/energy-attribution/pid_map_result_node37.log
kubectl exec -n username nfpeak-pod-c38 -- tail -n 5 /private-data/energy-attribution/pid_map_result_node38.log

# Compute basepower
kubectl exec -n username nfpeak-pod-c37 -- bash -c 'cd /private-data/energy-attribution/data_node37 && energat -basepower >> /private-data/energy-attribution/pid_map_result_node37.log 2>&1'
kubectl exec -n username nfpeak-pod-c38 -- bash -c 'cd /private-data/energy-attribution/data_node38 && energat -basepower >> /private-data/energy-attribution/pid_map_result_node38.log 2>&1'

while true; do
    bash generate_pod_uid_map.sh
    #sleep 120
    sleep 10  # or 30, 60 seconds, etc.
done
