#!/bin/bash

INPUT_FILE="$1"
LOG_FILE="/private-data/energy-attribution/pid_map_result_node37.log"

# Start fresh log
echo "🔍 PID Mapping started at $(date)" >> "$LOG_FILE"

if [[ -z "$INPUT_FILE" || ! -f "$INPUT_FILE" ]]; then
    echo "❌ Input file not found: $INPUT_FILE" | tee -a "$LOG_FILE"
    exit 1
fi

echo "✅ Loaded pod UID file: $INPUT_FILE" >> "$LOG_FILE"

# 1. Load pod UID→name map
#declare -A pod_map
#while IFS=$'\t' read -r name uid; do
#    pod_map["$uid"]="$name"
#done < "$INPUT_FILE"

# 1. Load pod UID→name(+task) map
declare -A pod_map
declare -A task_map
while IFS=$'\t' read -r name uid task; do
    pod_map["$uid"]="$name"
    if [[ -n "$task" ]]; then
        task_map["$uid"]="$task"
    else
        task_map["$uid"]="unknown"
    fi
done < "$INPUT_FILE"

# 2. Scan /proc for matching cgroup entries
#echo "🔍 Scanning /proc for process cgroups..." >> "$LOG_FILE"
#
#for pid in $(ls /proc | grep -E '^[0-9]+$'); do
#    cgroup_file="/proc/$pid/cgroup"
#    if [[ -f $cgroup_file ]]; then
#        while IFS= read -r line; do
#            if [[ "$line" == *kubepods*pod* ]]; then
#                # Extract pod UID from line (with underscores)
#                pod_match=$(echo "$line" | grep -o 'pod[0-9a-fA-F_]\+')
#                if [[ -n $pod_match ]]; then
#                    pod_uid_raw=${pod_match#pod}
#                    pod_uid_dash=$(echo "$pod_uid_raw" | sed 's/_/-/g')
#                    pod_name=${pod_map[$pod_uid_dash]}
#                    if [[ -n $pod_name ]]; then
#                        echo "PID $pid → Pod $pod_name (UID $pod_uid_dash)" >> "$LOG_FILE"
#                    fi
#                fi
#            fi
#        done < "$cgroup_file"
#    fi
#done

# 2. Scan /proc for matching cgroup entries
echo "🔍 Scanning /proc for process cgroups..." >> "$LOG_FILE"

for pid in $(ls /proc | grep -E '^[0-9]+$'); do
    cgroup_file="/proc/$pid/cgroup"
    if [[ -f $cgroup_file ]]; then
        while IFS= read -r line; do
            if [[ "$line" == *kubepods*pod* ]]; then
                # Extract pod UID from line (with underscores)
                pod_match=$(echo "$line" | grep -o 'pod[0-9a-fA-F_]\+')
                if [[ -n $pod_match ]]; then
                    pod_uid_raw=${pod_match#pod}
                    pod_uid_dash=$(echo "$pod_uid_raw" | sed 's/_/-/g')
                    pod_name=${pod_map[$pod_uid_dash]}
                    task_name=${task_map[$pod_uid_dash]}
                    if [[ -n $pod_name ]]; then
                        echo "PID $pid → Pod $pod_name (UID $pod_uid_dash, Task $task_name)" >> "$LOG_FILE"
                    fi
                fi
            fi
        done < "$cgroup_file"
    fi
done

echo "✅ PID mapping completed at $(date)" >> "$LOG_FILE"

LOG_DIR="/private-data/energy-attribution"
PROCESSED_PIDS_FILE="$LOG_DIR/pids_already_monitored_node37.txt"
NODE_LOG_FILE="$LOG_DIR/pid_map_result_node37.log"

ENERGAT_NODE_DIR="/private-data/energy-attribution/data_node37"
#mkdir -p "$ENERGAT_NODE_DIR"

# Compute basepower once if not yet present
#if [[ ! -f "$ENERGAT_NODE_DIR/data/baseline_power.json" ]]; then
#    echo "⚡ Computing basepower for node..." >> "$LOG_FILE"
#    (cd "$ENERGAT_NODE_DIR" && energat -basepower >> "$LOG_FILE" 2>&1)
#fi

# Ensure processed PID list exists
touch "$PROCESSED_PIDS_FILE"

# Extract PIDs from current log
grep -oP 'PID \K[0-9]+' "$NODE_LOG_FILE" | sort -n | uniq > "$LOG_DIR/all_seen_pids_node37.txt"

# Sort the files that are compared
#sort -n "$LOG_DIR/all_seen_pids_node37.txt" -o "$LOG_DIR/all_seen_pids_node37.txt"
#sort -n "$PROCESSED_PIDS_FILE" -o "$PROCESSED_PIDS_FILE"
# Sort lexicographically instead of numeric
sort "$LOG_DIR/all_seen_pids_node37.txt" -o "$LOG_DIR/all_seen_pids_node37.txt"
sort "$PROCESSED_PIDS_FILE" -o "$PROCESSED_PIDS_FILE"

# Determine new PIDs
comm -23 "$LOG_DIR/all_seen_pids_node37.txt" "$PROCESSED_PIDS_FILE" > "$LOG_DIR/new_pids_node37.txt"

# Keep only root PIDs among NEW_CANDIDATES (no ancestor in NEW ∪ MONITORED)
# Usage: prune_to_roots <new_pids_file> <monitored_pids_file> > roots_to_launch.txt
prune_to_roots() {
  local NEW="$1"
  local MON="$2"

  # Private tmp dir (works whether TMPDIR=/tmp or /tmp2 or anything)
  local TMPD
  TMPD="$(mktemp -d)"
  trap 'rm -rf "$TMPD"' RETURN

  # 1) Normalize: keep numeric, live PIDs
  awk '/^[0-9]+$/' "$NEW" | sort -n | uniq | while read -r p; do
    [[ -d "/proc/$p" ]] && echo "$p"
  done > "$TMPD/new.live"

  awk '/^[0-9]+$/' "$MON" | sort -n | uniq | while read -r p; do
    [[ -d "/proc/$p" ]] && echo "$p"
  done > "$TMPD/mon.live"

  # Union (NEW ∪ MONITORED) membership for ancestry checks
  cat "$TMPD/new.live" "$TMPD/mon.live" | sort -n | uniq > "$TMPD/union"

  # Single snapshot of PID->PPID
  ps -eo pid=,ppid= | awk '{print $1" "$2}' > "$TMPD/pp"

  # Keep only NEW PIDs that have NO ancestor in the union set
  awk -v UNION="$TMPD/union" -v PP="$TMPD/pp" -v NEWLIVE="$TMPD/new.live" '
    BEGIN{
      while ((getline < UNION)>0) in_union[$1]=1
      while ((getline < PP)>0)    ppid[$1]=$2
    }
    function has_ancestor_in_union(x){
      while (x>1) {
        x=ppid[x]
        if (!x) break
        if (in_union[x]) return 1
      }
      return 0
    }
    END{
      while ((getline l < NEWLIVE)>0) {
        pid=l+0
        if (!has_ancestor_in_union(pid)) print pid
      }
    }
  ' < /dev/null
}

prune_to_roots "$LOG_DIR/new_pids_node37.txt" "$PROCESSED_PIDS_FILE" > "$LOG_DIR/non_child_pids_node37.txt"

# Start EnergAt for each new PID
while read -r pid; do
    echo "🚀 Starting EnergAt for PID $pid on node 37" >> "$LOG_FILE"
    #energat -pid "$pid" &  # optional: add & to run in background
    (
        cd "$ENERGAT_NODE_DIR"
        #nohup energat -pid "$pid" >> "$LOG_FILE" 2>&1 &
        #nohup energat -pid "$pid" > /dev/null 2>&1 & #Working verion with default rapl_period (0.01)
        #nohup energat -pid "$pid" --rapl_period=0.5 --process_only_targets --linger_on_root_exit > /dev/null 2>&1 &
        mkdir -p "$ENERGAT_NODE_DIR/logs37"
        #nohup energat -pid "$pid" --rapl_period=0.2 --process_only_targets --linger_on_root_exit >> "$ENERGAT_NODE_DIR/logs37/energat_${pid}.log" 2>&1 &
        #nohup energat -pid "$pid" --interval=5 --rapl_period=2 --process_only_targets --linger_on_root_exit >> "$ENERGAT_NODE_DIR/logs37/energat_${pid}.log" 2>&1 &
        #nohup energat -pid "$pid" --interval=5 --rapl_period=2 --process_only_targets --linger_on_root_exit > /dev/null 2>&1 &
        nohup energat -pid "$pid" --interval=5 --rapl_period=2 --process_only_targets > /dev/null 2>&1 &
        disown
    ) &
    echo "$pid" >> "$PROCESSED_PIDS_FILE"
done < "$LOG_DIR/non_child_pids_node37.txt" #"$LOG_DIR/new_pids_node37.txt"