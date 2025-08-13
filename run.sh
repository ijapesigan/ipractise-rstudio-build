#!/usr/bin/env bash
# run.sh
# One-shot orchestrator for Ubuntu 24.04 EC2:
#  - Install R from source
#  - Install RStudio Server
#  - Configure Posit Package Manager
#
# Usage examples:
#   ./run.sh
#   R_VERSION=latest ./run.sh
#   R_VERSION=4.4.2 MAKE_NJOBS=8 DEFAULT_USER=analyst PPM_URL=https://packagemanager.posit.co/cran/__linux__/noble/2025-08-01 ./run.sh
#
set -Eeuo pipefail
IFS=$'\n\t'

# If not root, re-exec with sudo
if [[ ${EUID:-0} -ne 0 ]]; then
  exec sudo -E bash "$0" "$@"
fi
export DEBIAN_FRONTEND=noninteractive

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${DIR}"

# Default envs (can be overridden by caller)
export R_VERSION="${R_VERSION:-latest}"
export MAKE_NJOBS="${MAKE_NJOBS:-0}"
export DEFAULT_USER="${DEFAULT_USER:-rstudio}"
export PPM_URL="${PPM_URL:-https://packagemanager.posit.co/cran/__linux__/noble/latest}"

echo "==== STEP 1: Install R (${R_VERSION}) ===="
bash "${DIR}/install-r-from-source.sh" "${R_VERSION}"

echo "==== STEP 2: Install RStudio Server ===="
bash "${DIR}/install-rstudio-server.sh" "${RSTUDIO_VERSION:-stable}"

echo "==== STEP 3: Configure Posit Package Manager ===="
bash "${DIR}/configure-posit-ppm.sh"

echo "==== DONE ===="
echo "R: $(command -v R || true)"
R --version || true
systemctl --no-pager status rstudio-server || true

echo
echo "Next steps:"
echo " - Open TCP 8787 in your EC2 Security Group."
echo " - Visit http://<EC2-Public-DNS>:8787 and log in with an OS user (e.g., ${DEFAULT_USER})."
echo " - In R, run: options('repos') to verify PPM; install.packages('data.table') to test."
