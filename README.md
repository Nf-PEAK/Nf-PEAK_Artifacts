# Nf-PEAK: Process-based Energy Attribution for Nextflow Workflows on Kubernetes

Nf-PEAK is a **containerized** method to attribute **CPU package** and **DRAM** energy (Intel RAPL)
to individual **processes** and **Nextflow tasks** on **Kubernetes** clusters, without installing software
on cluster nodes.

It works by (1) detecting Nextflow workflow pods, (2) mapping pod UIDs to host PIDs via cgroup metadata,
(3) monitoring per-process resource usage and socket-level RAPL counters, and (4) applying a
non-linear “energy credit” model before aggregating results at task level.

> Note: Monitoring requires elevated permissions for the *monitoring pods* (e.g., `hostPID: true` and a
> read-only mount of the host powercap directory that exposes RAPL counters). Workflow tasks themselves can
> remain unprivileged.

## Repository structure

```
Architecture/              # Architecture figure describing components and interactions
Dockerfile/        # Monitoring container Dockerfile + build instructions + monitoring source code
Nf-PEAK_Scripts/           # Shell scripts for discovery, mapping, monitoring control, aggregation
Pods/                      # Kubernetes YAMLs to deploy Nextflow and monitoring pods
```

## Quick start (typical workflow)

The repository contains all files required to run Nf-PEAK on a Kubernetes cluster. You will need to adapt
variables such as namespaces, paths/PVCs, and node names to your cluster setup.

1. **Deploy a Nextflow pod** (adjust parameters in `Pods/pod_nextflow.yaml`):
   ```bash
   kubectl apply -f Pods/pod_nextflow.yaml
   ```

2. **Deploy one monitoring pod per worker node** you want to instrument (adjust the YAML, then apply):
   ```bash
   kubectl apply -f Pods/energat-pod-<node>.yaml
   ```

3. **Copy the script set** from `Nf-PEAK_Scripts/` to the cluster and adjust:
   - namespaces
   - node names
   - PVC mount paths / output paths
   - polling + sampling intervals (optional)

4. **Start monitoring**:
   ```bash
   bash monitor_PIDs.sh
   ```

5. **Wait ~30 seconds** so Nf-PEAK can measure and store **static (idle) energy**. Ensure the cluster is idle
   during this calibration step (or measure static energy separately and disable re-calculation in `monitor_PIDs.sh`).

6. **Run your workflow** in the Nextflow pod (Nf-PEAK will automatically detect and monitor it):
   ```bash
   nextflow run <workflow> -profile kubernetes
   ```

7. **After the workflow completes**, aggregate results (run in one monitoring pod):
   ```bash
   bash aggregate_energy.sh
   ```

## Output

Nf-PEAK produces:
- a **human-readable log** (per PID / per task aggregation details)
- a **CSV file** suitable for post-processing and plotting (task-level energy results)

## Key parameters

Nf-PEAK exposes a few practical tuning knobs:
- **γ (gamma)**: non-linearity exponent in the energy-credit model
- **task discovery / polling interval**: how often new pods/PIDs are detected
- **RAPL sampling interval**: how often RAPL counters are read (trade-off: short-task coverage vs overhead)

The values used in our experiments were `gamma = 0.3`, discovery every `5s`, and RAPL sampling every `2s`.
These values were experimentally evaluated to be optimal on our hardware.
On different hardware, other values might produce better results.

## Limitations

- **Very short tasks (sub-second)** can be missed by polling/sampling, which may bias attribution.
- RAPL covers **CPU package** and (where available) **DRAM** energy; storage/network/accelerator energy is not covered.

## Publication

This repository accompanies our preprint, "Nf-PEAK: Process-Based Energy Attribution for Nextflow Workflows on Kubernetes Clusters", which presents Nf-PEAK as a method for attributing CPU package and DRAM energy consumption to individual Nextflow tasks on Kubernetes clusters.

Please cite our preprint:

Philipp Thamm, Somayeh Mohammadi, Kathleen West, Knut Reinert, Lauritz Thamsen, Ulf Leser. "Nf-PEAK: Process-Based Energy Attribution for Nextflow Workflows on Kubernetes Clusters." arXiv, 2026. DOI: 10.48550/arXiv.2605.22393.

BibTeX:
```
@misc{thamm_nf-peak_2026,
  title = {Nf-{PEAK}: {Process}-{Based} {Energy} {Attribution} for {Nextflow} {Workflows} on {Kubernetes} {Clusters}},
  copyright = {Creative Commons Attribution 4.0 International},
  shorttitle = {Nf-{PEAK}},
  url = {https://arxiv.org/abs/2605.22393},
  doi = {10.48550/ARXIV.2605.22393},
  language = {en},
  urldate = {2026-05-29},
  publisher = {arXiv},
  author = {Thamm, Philipp and Mohammadi, Somayeh and West, Kathleen and Reinert, Knut and Thamsen, Lauritz and Leser, Ulf},
  year = {2026},
  note = {Version Number: 1},
  keywords = {Distributed, Parallel, and Cluster Computing (cs.DC), FOS: Computer and information sciences},
}
```
