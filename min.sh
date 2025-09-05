#!/bin/bash
set -e
 
# Allow users to override the paths for NVIDIA tools
: "${NVIDIA_SMI_PATH:=nvidia-smi}"
: "${NVIDIA_CTK_PATH:=nvidia-ctk}"
 
echo "Current PATH: $PATH"
echo "Operating System: $(uname -a)"
 
# Helper: check if minikube exists
minikube_exists() {
  command -v minikube >/dev/null 2>&1
}
 
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
 
 
# Install minikube if missing
if minikube_exists; then
  echo "Minikube already installed."
else
  echo "Installing Minikube..."
  curl -LO https://github.com/kubernetes/minikube/releases/latest/download/minikube-linux-amd64
  install minikube-linux-amd64 "$HOME/.local/bin/minikube" && rm minikube-linux-amd64
fi
 
# --- Configure BPF (optional) ---
if [ -f /proc/sys/net/core/bpf_jit_harden ]; then
    echo "Skipping /etc/sysctl.conf modification (requires root)"
    echo "You can manually run 'sudo sysctl -w net.core.bpf_jit_harden=0' if needed"
fi
 
# --- Memory calculation ---
calculate_safe_memory() {
  local floor_mb=2048
  local host_reserve_mb=2048
 
  local total_kb avail_kb total_mb avail_mb
  total_kb=$(awk '/MemTotal:/ {print $2}' /proc/meminfo)
  avail_kb=$(awk  '/MemAvailable:/ {print $2}' /proc/meminfo)
  total_mb=$(( total_kb / 1024 ))
  avail_mb=$(( avail_kb > 0 ? avail_kb / 1024 : (total_mb * 60 / 100) ))
 
  local cg_raw cg_mb=0
  if [[ -r /sys/fs/cgroup/memory.max ]]; then
    cg_raw=$(cat /sys/fs/cgroup/memory.max)
    [[ "$cg_raw" != "max" ]] && cg_mb=$(( cg_raw / 1024 / 1024 ))
  fi
 
  local target=$(( avail_mb * 80 / 100 ))
  local total_cap=$(( total_mb * 90 / 100 ))
  (( target > total_cap )) && target=$total_cap
 
  local max_allowed=$(( total_mb - host_reserve_mb ))
  if (( cg_mb > 0 )); then
    local cg_cap=$(( cg_mb - host_reserve_mb ))
    (( cg_cap < max_allowed )) && max_allowed=$cg_cap
  fi
 
  if (( max_allowed < floor_mb )); then
    echo "ERROR: Not enough RAM to auto-size (total=${total_mb}MB, allowed=${max_allowed}MB). Set MINIKUBE_MEM manually." >&2
    return 1
  fi
 
  (( target < floor_mb )) && target=$floor_mb
  (( target > max_allowed )) && target=$max_allowed
  echo "$target"
}
 
# --- NVIDIA GPU detection ---
GPU_AVAILABLE=false
if command -v "$NVIDIA_SMI_PATH" >/dev/null 2>&1; then
    echo "NVIDIA GPU detected via nvidia-smi at: $(command -v "$NVIDIA_SMI_PATH")"
    if command -v "$NVIDIA_CTK_PATH" >/dev/null 2>&1; then
      echo "nvidia-ctk found at: $(command -v "$NVIDIA_CTK_PATH")"
      GPU_AVAILABLE=true
    else
      echo "nvidia-ctk not found. GPU support will be disabled."
    fi
else
    echo "No NVIDIA GPU detected. Minikube will start without GPU support."
fi
 
if [[ -z "${MINIKUBE_MEM:-}" ]]; then
  MINIKUBE_MEM="$(calculate_safe_memory)"
fi
 
# --- Start Minikube ---
if [ "$GPU_AVAILABLE" = true ]; then
    echo "Assuming Docker is already configured for GPU support..."
    echo "Starting Minikube with GPU support..."
    minikube start --memory="${MINIKUBE_MEM}" --driver=docker --container-runtime=docker --gpus=all --force --addons=nvidia-device-plugin
 
    echo "Updating kubeconfig context..."
    minikube update-context
 
    echo "Adding NVIDIA Helm repo and installing GPU Operator..."
    helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
    helm repo update
    helm install --wait --generate-name -n gpu-operator --create-namespace nvidia/gpu-operator --version=v24.9.1
else
    echo "Starting Minikube without GPU support..."
    minikube start --memory="${MINIKUBE_MEM}" --driver=docker --force
fi
 
echo "Minikube cluster installation complete."
 
 