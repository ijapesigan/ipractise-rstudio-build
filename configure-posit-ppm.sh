#!/usr/bin/env bash
# configure-posit-ppm.sh
# Configure system-wide CRAN repos to use Posit Package Manager for Ubuntu 24.04.
#
# Usage:
#   sudo ./configure-posit-ppm.sh
#
# Env:
#   PPM_URL (default: https://packagemanager.posit.co/cran/__linux__/noble/latest)
#   PPM_FORCE=true to overwrite existing config
#
set -Eeuo pipefail
IFS=$'\n\t'
export DEBIAN_FRONTEND=noninteractive

if [[ ${EUID:-0} -ne 0 ]]; then echo "Please run as root (sudo)." >&2; exit 1; fi
# shellcheck source=/dev/null
source /etc/os-release
[[ "${ID}" == "ubuntu" ]] || { echo "Ubuntu required. Detected ${PRETTY_NAME}"; exit 1; }

PPM_URL_DEFAULT="https://packagemanager.posit.co/cran/__linux__/noble/latest"
PPM_URL="${PPM_URL:-$PPM_URL_DEFAULT}"
PPM_FORCE="${PPM_FORCE:-false}"

mkdir -p /etc/R

RPROFILE_SITE="/etc/R/Rprofile.site"
RENVSITE="/etc/R/Renviron.site"

write_rprofile(){
  cat > "${RPROFILE_SITE}" <<'EOF'
## System-wide defaults
local({
  repos <- getOption("repos")
  repos["CRAN"] <- Sys.getenv("PPM_URL",
    "https://packagemanager.posit.co/cran/__linux__/noble/latest")
  options(repos = repos)
  # Use libcurl for better TLS/HTTP/2
  options(download.file.method = "libcurl")
  # Parallelize compiles by default
  if (nzchar(Sys.getenv("R_MAKE_NJOBS"))) {
    options(Ncpus = as.integer(Sys.getenv("R_MAKE_NJOBS")))
  } else {
    n <- tryCatch(parallel::detectCores(), error = function(e) 1L)
    options(Ncpus = if (is.finite(n) && n > 1) n else 1L)
  }
})
EOF
}

write_renviron(){
  cat > "${RENVSITE}" <<EOF
## Ensure renv and other tooling see the same repo
PPM_URL=${PPM_URL}
RENV_CONFIG_REPOS_OVERRIDE=${PPM_URL}
EOF
}

if [[ -f "${RPROFILE_SITE}" && "${PPM_FORCE}" != "true" ]]; then
  echo "${RPROFILE_SITE} exists. Set PPM_FORCE=true to overwrite."
else
  write_rprofile
  echo "Wrote ${RPROFILE_SITE}"
fi

if [[ -f "${RENVSITE}" && "${PPM_FORCE}" != "true" ]]; then
  echo "${RENVSITE} exists. Set PPM_FORCE=true to overwrite."
else
  write_renviron
  echo "Wrote ${RENVSITE}"
fi

echo "PPM configured -> ${PPM_URL}"
