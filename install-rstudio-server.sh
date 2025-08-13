#!/usr/bin/env bash
# install-rstudio-server.sh
# Install RStudio Server (open-source) on Ubuntu 24.04 (Noble) EC2.
#
# Usage:
#   sudo ./install-rstudio-server.sh                 # latest stable
#   sudo ./install-rstudio-server.sh preview         # latest preview
#   sudo ./install-rstudio-server.sh 2024.12.0-467   # exact version
#
# Env:
#   RSTUDIO_VERSION=stable|preview|<ver>
#   DEFAULT_USER=rstudio
#
set -Eeuo pipefail
IFS=$'\n\t'
RSTUDIO_VERSION="${1:-${RSTUDIO_VERSION:-stable}}"
DEFAULT_USER="${DEFAULT_USER:-rstudio}"
export DEBIAN_FRONTEND=noninteractive

if [[ ${EUID:-0} -ne 0 ]]; then echo "Please run as root (sudo)." >&2; exit 1; fi
# shellcheck source=/dev/null
source /etc/os-release
ARCH="$(dpkg --print-architecture)"
[[ "${ID}" == "ubuntu" ]] || { echo "Ubuntu required. Detected ${PRETTY_NAME}"; exit 1; }
case "${ARCH}" in amd64|arm64) :;; *) echo "Unsupported arch ${ARCH}"; exit 1;; esac

retry(){ local n=$1; shift; local i; for ((i=1;i<=n;i++)); do "$@" && return 0 || true; sleep $((i*2)); done; "$@"; }
url_exists(){ curl -fsI "$1" >/dev/null 2>&1; }

retry 3 apt-get update -y
retry 3 apt-get install -y --no-install-recommends       gdebi-core adduser procps psmisc libssl3 libclang-dev libstdc++-12-dev ca-certificates curl wget

CODENAME="${UBUNTU_CODENAME}"
BASES=( "https://download2.rstudio.org/server" "https://download1.rstudio.org/server" )
declare -a CANDIDATES=()

make_pkg(){ echo "rstudio-server-$1-$2.deb"; }

if [[ "${RSTUDIO_VERSION}" == "stable" || "${RSTUDIO_VERSION}" == "preview" ]]; then
  for codename_try in "${CODENAME}" "noble" "jammy"; do
    for base in "${BASES[@]}"; do
      ver_url="${base}/${codename_try}/${ARCH}/VERSION"
      if url_exists "${ver_url}"; then
        ver="$(curl -fsSL "${ver_url}" | tr -d ' \r')"
        CANDIDATES+=( "${base}/${codename_try}/${ARCH}/$(make_pkg "${ver}" "${ARCH}")" )
      fi
      if [[ "${RSTUDIO_VERSION}" == "preview" ]]; then
        prev="${base}/${codename_try}/${ARCH}/preview/VERSION"
        if url_exists "${prev}"; then
          verp="$(curl -fsSL "${prev}" | tr -d ' \r')"
          CANDIDATES+=( "${base}/${codename_try}/${ARCH}/preview/$(make_pkg "${verp}" "${ARCH}")" )
        fi
      fi
    done
  done
else
  for codename_try in "${CODENAME}" "noble" "jammy"; do
    for base in "${BASES[@]}"; do
      CANDIDATES+=( "${base}/${codename_try}/${ARCH}/$(make_pkg "${RSTUDIO_VERSION}" "${ARCH}")" )
      CANDIDATES+=( "${base}/${codename_try}/${ARCH}/preview/$(make_pkg "${RSTUDIO_VERSION}" "${ARCH}")" )
    done
  done
fi

[[ ${#CANDIDATES[@]} -gt 0 ]] || { echo "No candidate URLs produced"; exit 1; }

DL_URL=""
for u in "${CANDIDATES[@]}"; do if url_exists "${u}"; then DL_URL="${u}"; break; fi; done
[[ -n "${DL_URL}" ]] || { echo "Could not resolve RStudio Server URL"; printf '%s\n' "${CANDIDATES[@]}" >&2; exit 1; }

echo "Downloading: ${DL_URL}"
tmpdir=$(mktemp -d); trap 'rm -rf "${tmpdir}"' EXIT
(cd "${tmpdir}" && curl -fLO "${DL_URL}")
DEB_FILE=$(basename "${DL_URL}")
(cd "${tmpdir}" && gdebi -n "${DEB_FILE}" || dpkg -i "${DEB_FILE}" || true)
apt-get -f install -y

if ! id -u "${DEFAULT_USER}" >/dev/null 2>&1; then
  adduser --disabled-password --gecos "" "${DEFAULT_USER}"
  echo "${DEFAULT_USER}:${DEFAULT_USER}" | chpasswd
  usermod -aG sudo "${DEFAULT_USER}" || true
  echo "Created user '${DEFAULT_USER}' with password same as username. Change it."
fi

systemctl enable rstudio-server
systemctl restart rstudio-server
systemctl --no-pager status rstudio-server || true
echo "RStudio Server installed. Visit: http://<EC2-Public-DNS>:8787"
