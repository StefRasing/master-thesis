#!/usr/bin/env bash
# Read-only: run on the DAIC login node; save output alongside pilot results.
set -euo pipefail
echo '=== Account associations ==='
sacctmgr show user "$USER" withassoc format=User,Account,Partition,QOS,DefaultQOS
echo '=== Partition limits ==='
sinfo -o '%P %l %c %m %a'
scontrol show partition
echo '=== QoS limits (if visible to your account) ==='
sacctmgr show qos format=Name,MaxWall,MaxTRESPU,MaxJobsPU,MaxSubmitPU || true
echo '=== Array limit ==='
scontrol show config | rg MaxArraySize
echo '=== Julia ==='
command -v julia
julia --startup-file=no --version
