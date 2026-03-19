#!/bin/bash

ENERGAT_DIR="/private-data/energy-attribution"
RESULT_LOG="$ENERGAT_DIR/task_energy_summary.log"
RESULT_CSV="$ENERGAT_DIR/task_energy_summary.csv"

# Prepare fresh files
echo "📊 Aggregated Task Energy Report" > "$RESULT_LOG"
echo "🕒 Generated at: $(date)" >> "$RESULT_LOG"
echo "===================================" >> "$RESULT_LOG"
echo "task,total_pkg_j,total_dram_j,total_energy_j,pods,pids" > "$RESULT_CSV"

# Declare associative arrays
declare -A task_pkg_energy
declare -A task_dram_energy
declare -A task_pods
declare -A task_pid_pkg
declare -A task_pid_dram
declare -A seen_pid

for node_dir in "$ENERGAT_DIR"/data_node*/; do
    node_label=$(basename "$node_dir" | sed 's/data_//')
    LOG_FILE="$ENERGAT_DIR/pid_map_result_${node_label}.log"
    CSV_DIR="$node_dir/data/results"

    echo "🔍 Processing node directory: $node_dir" >> "$RESULT_LOG"

    TEMP_PID_FILE=$(mktemp)

    grep '^PID ' "$LOG_FILE" | while read -r line; do
        pid=$(echo "$line" | grep -oP 'PID \K[0-9]+')
        pod=$(echo "$line" | grep -oP '→ Pod \K[^ ]+')
        task=$(echo "$line" | grep -oP 'Task \K[^)]*')

        [[ -z "$pid" || -z "$pod" || -z "$task" ]] && continue
        [[ ${seen_pid[$pid]} ]] && continue
        seen_pid[$pid]=1

        csv_file="$CSV_DIR/energat_traces_target-$pid.csv"

        if [[ -f "$csv_file" ]]; then
            pkg_joules=$(awk -F',' 'NR>1 {sum += $12} END {print sum+0}' "$csv_file")
            dram_joules=$(awk -F',' 'NR>1 {sum += $13} END {print sum+0}' "$csv_file")
            echo "$task|$pid|$pod|$pkg_joules|$dram_joules" >> "$TEMP_PID_FILE"
        fi
    done

    while IFS='|' read -r task pid pod pkg_joules dram_joules; do
        task_pkg_energy["$task"]=$(echo "${task_pkg_energy["$task"]:-0} + $pkg_joules" | bc)
        task_dram_energy["$task"]=$(echo "${task_dram_energy["$task"]:-0} + $dram_joules" | bc)

        task_pods["$task"]+="$pod "
        task_pid_pkg["$task"]+="$pid:$pkg_joules "
        task_pid_dram["$task"]+="$pid:$dram_joules "
    done < "$TEMP_PID_FILE"

    rm -f "$TEMP_PID_FILE"
done

# Write results
for task in "${!task_pkg_energy[@]}"; do
    total_pkg=${task_pkg_energy[$task]}
    total_dram=${task_dram_energy[$task]}
    total_energy=$(echo "$total_pkg + $total_dram" | bc)

    echo "🧪 Task: $task" >> "$RESULT_LOG"
    echo "  • Total Package Energy (J): $total_pkg" >> "$RESULT_LOG"
    echo "  • Total DRAM Energy (J):    $total_dram" >> "$RESULT_LOG"
    echo "  • Total Combined Energy (J): $total_energy" >> "$RESULT_LOG"

    # Deduplicate pod names for log output
    unique_pods=$(echo "${task_pods[$task]}" | tr ' ' '\n' | sort -u | tr '\n' ' ' | sed 's/ $//')
    echo "  • Pods involved: $unique_pods" >> "$RESULT_LOG"

    echo "  • Per-PID Energy Breakdown:" >> "$RESULT_LOG"
    IFS=' ' read -r -a pkg_pairs <<< "${task_pid_pkg[$task]}"
    IFS=' ' read -r -a dram_pairs <<< "${task_pid_dram[$task]}"
    for i in "${!pkg_pairs[@]}"; do
        pid_pkg="${pkg_pairs[$i]}"
        pid_dram="${dram_pairs[$i]}"
        pid=$(echo "$pid_pkg" | cut -d':' -f1)
        pkg=$(echo "$pid_pkg" | cut -d':' -f2)
        dram=$(echo "$pid_dram" | cut -d':' -f2)
        combined=$(echo "$pkg + $dram" | bc)
        echo "    - PID $pid → pkg: $pkg J, dram: $dram J, total: $combined J" >> "$RESULT_LOG"
    done
    echo "" >> "$RESULT_LOG"

    # Write to CSV
    csv_pods=$(echo "$unique_pods" | tr ' ' ';')
    pid_list=$(echo "${task_pid_pkg[$task]}" | sed 's/ /;/g')

    echo "$task,$total_pkg,$total_dram,$total_energy,\"$csv_pods\",\"$pid_list\"" >> "$RESULT_CSV"
done

# Final summary totals
grand_total_pkg=0
grand_total_dram=0

for task in "${!task_pkg_energy[@]}"; do
    grand_total_pkg=$(echo "$grand_total_pkg + ${task_pkg_energy[$task]}" | bc)
    grand_total_dram=$(echo "$grand_total_dram + ${task_dram_energy[$task]}" | bc)
done

grand_total_combined=$(echo "$grand_total_pkg + $grand_total_dram" | bc)

echo "===================================" >> "$RESULT_LOG"
echo "🧾 Total Summary Across All Tasks:" >> "$RESULT_LOG"
echo "  • Total Package Energy (J): $grand_total_pkg" >> "$RESULT_LOG"
echo "  • Total DRAM Energy (J):    $grand_total_dram" >> "$RESULT_LOG"
echo "  • Total Combined Energy (J): $grand_total_combined" >> "$RESULT_LOG"