#!/usr/bin/env bash
# Apply local-dev components directly via Tanka, bypassing ArgoCD.
#
# Usage:
#   ./scripts/tk-apply-local.sh                     # apply all waves
#   ./scripts/tk-apply-local.sh server               # apply a single component
#   ./scripts/tk-apply-local.sh --local-ip 10.0.0.5  # override detected IP
#   ./scripts/tk-apply-local.sh --dry-run             # show what would be applied

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

LOCAL_IP=""
DRY_RUN=false
COMPONENT=""
TK_APPLY_FLAGS=("--server-side" "--force")

# Wave definitions (matches argocd-apps.libsonnet ordering)
WAVE_0=(namespace cloudnative-pg-crds external-secrets)
WAVE_1=(traefik cert-manager)
WAVE_2=(cloudnative-pg)
WAVE_3=(auth)
WAVE_4=(server web argocd)

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS] [COMPONENT]

Apply local-dev Tanka components directly to the KIND cluster.

Options:
  --local-ip IP   Override auto-detected local IP for nip.io domain
  --dry-run       Print commands without executing them
  -h, --help      Show this help message

If COMPONENT is given, only that component is applied.
Otherwise, all components are applied in wave order.

Available components:
  Wave 0: ${WAVE_0[*]}
  Wave 1: ${WAVE_1[*]}
  Wave 2: ${WAVE_2[*]}
  Wave 3: ${WAVE_3[*]}
  Wave 4: ${WAVE_4[*]}
EOF
}

detect_ip() {
  if [[ -n "$LOCAL_IP" ]]; then
    return
  fi
  if [[ -n "${LOCAL_IP_ENV:-}" ]]; then
    LOCAL_IP="$LOCAL_IP_ENV"
    return
  fi
  local helper="$SCRIPT_DIR/get-local-ip.sh"
  if [[ -x "$helper" ]]; then
    LOCAL_IP="$("$helper")" || true
  fi
  if [[ -z "$LOCAL_IP" ]]; then
    echo "Error: could not detect local IP. Pass --local-ip or set LOCAL_IP." >&2
    exit 1
  fi
}

apply_component() {
  local component="$1"
  local cmd=(
    tk apply "$REPO_ROOT/environments/local-dev"
    --tla-str "localIP=$LOCAL_IP"
    --tla-str "component=$component"
    "${TK_APPLY_FLAGS[@]}"
  )

  if $DRY_RUN; then
    echo "[dry-run] ${cmd[*]}"
  else
    echo "--- Applying: $component"
    "${cmd[@]}"
  fi
}

apply_wave() {
  local wave_name="$1"
  shift
  local components=("$@")

  echo "=== $wave_name ==="
  for c in "${components[@]}"; do
    apply_component "$c"
  done
}

# --- Parse arguments ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --local-ip)
      LOCAL_IP="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
    *)
      COMPONENT="$1"
      shift
      ;;
  esac
done

detect_ip
echo "Using local IP: $LOCAL_IP"

if [[ -n "$COMPONENT" ]]; then
  apply_component "$COMPONENT"
else
  apply_wave "Wave 0: CRDs and namespaces" "${WAVE_0[@]}"
  apply_wave "Wave 1: Operators"           "${WAVE_1[@]}"
  apply_wave "Wave 2: Database"            "${WAVE_2[@]}"
  apply_wave "Wave 3: Authentication"      "${WAVE_3[@]}"
  apply_wave "Wave 4: Applications"        "${WAVE_4[@]}"
fi

echo "Done."
