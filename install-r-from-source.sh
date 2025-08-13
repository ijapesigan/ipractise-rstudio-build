#!/usr/bin/env bash
# install-r-from-source.sh
# Build and install R from source on Ubuntu 24.04 (Noble) — AWS EC2 friendly.
#
# Usage:
#   sudo ./install-r-from-source.sh                 # latest release
#   sudo ./install-r-from-source.sh patched         # latest patched snapshot
#   sudo ./install-r-from-source.sh devel           # latest devel snapshot
#   sudo ./install-r-from-source.sh 4.4.2           # specific version
#
# Env:
#   R_VERSION=latest|patched|devel|<x.y.z>
#   MAKE_NJOBS=0|N           (0 = auto cores)
#   R_PREFIX=/usr/local      (install prefix; default /usr/local)
#   PURGE_BUILDDEPS=true|false
#
set -Eeuo pipefail
IFS=$'\n\t'
R_VERSION="${1:-${R_VERSION:-latest}}"
MAKE_NJOBS="${MAKE_NJOBS:-0}"
R_PREFIX="${R_PREFIX:-/usr/local}"
PURGE_BUILDDEPS="${PURGE_BUILDDEPS:-true}"
export DEBIAN_FRONTEND=noninteractive

if [[ ${EUID:-0} -ne 0 ]]; then
  echo "Please run as root (sudo)." >&2; exit 1; fi

# shellcheck source=/dev/null
source /etc/os-release
if [[ "${ID}" != "ubuntu" ]]; then
  echo "This script targets Ubuntu. Detected: ${PRETTY_NAME}" >&2; exit 1; fi

retry(){ local n=$1; shift; local i; for ((i=1;i<=n;i++)); do "$@" && return 0 || true; sleep $((i*2)); done; "$@"; }
nproc_auto(){ command -v nproc >/dev/null && nproc || getconf _NPROCESSORS_ONLN || echo 2; }

LANG="${LANG:-en_US.UTF-8}"
retry 3 apt-get update -y
retry 3 apt-get install -y --no-install-recommends locales
/usr/sbin/locale-gen --lang "${LANG}"
/usr/sbin/update-locale --reset LANG="${LANG}"

retry 3 apt-get install -y --no-install-recommends \
  build-essential gfortran clang make cmake ninja-build \
  pkg-config \
  libreadline-dev libbz2-dev zlib1g-dev liblzma-dev libzstd-dev \
  libpcre2-dev libcurl4-openssl-dev \
  libpng-dev libjpeg-dev libtiff5-dev \
  libx11-dev libxft-dev libxext-dev libxt-dev libxinerama-dev \
  libxml2-dev \
  libblas-dev liblapack-dev libopenblas-dev \
  libedit-dev \
  ca-certificates curl wget git python3 python3-pip texinfo
apt-get install -y --no-install-recommends default-jre || true

# Prefer OpenBLAS if alternatives are registered (amd64/arm64)
if update-alternatives --list libblas.so-x86_64-linux-gnu >/dev/null 2>&1; then
  oblas="$(update-alternatives --list libblas.so-x86_64-linux-gnu | grep -m1 openblas || true)"
  [[ -n "${oblas}" ]] && update-alternatives --set libblas.so-x86_64-linux-gnu "${oblas}" || true
fi
if update-alternatives --list liblapack.so-x86_64-linux-gnu >/dev/null 2>&1; then
  olapack="$(update-alternatives --list liblapack.so-x86_64-linux-gnu | grep -m1 openblas || true)"
  [[ -n "${olapack}" ]] && update-alternatives --set liblapack.so-x86_64-linux-gnu "${olapack}" || true
fi
if update-alternatives --list libblas.so-aarch64-linux-gnu >/dev/null 2>&1; then
  oblas_a="$(update-alternatives --list libblas.so-aarch64-linux-gnu | grep -m1 openblas || true)"
  [[ -n "${oblas_a}" ]] && update-alternatives --set libblas.so-aarch64-linux-gnu "${oblas_a}" || true
fi
if update-alternatives --list liblapack.so-aarch64-linux-gnu >/dev/null 2>&1; then
  olapack_a="$(update-alternatives --list liblapack.so-aarch64-linux-gnu | grep -m1 openblas || true)"
  [[ -n "${olapack_a}" ]] && update-alternatives --set liblapack.so-aarch64-linux-gnu "${olapack_a}" || true
fi

R_BASE_URL_RELEASE="https://cran.r-project.org/src/base/R-4"
SNAPSHOT_BASE="https://cran.r-project.org/src/base-prerelease"
case "${R_VERSION}" in
  latest)
    # Robustly detect the newest R-x.y.z tarball from CRAN index
    TARBALL="$(curl -fsSL "${R_BASE_URL_RELEASE}/" \
      | grep -Eo 'R-[0-9]+\.[0-9]+\.[0-9]+\.tar\.gz' \
      | sort -Vu | tail -1)"
    if [[ -z "${TARBALL}" ]]; then
      echo "ERROR: Could not detect latest R tarball from ${R_BASE_URL_RELEASE}" >&2
      exit 1
    fi
    URL="${R_BASE_URL_RELEASE}/${TARBALL}"
    ;;
  patched)
    URL="${SNAPSHOT_BASE}/R-patched.tar.gz"; TARBALL="R-patched.tar.gz"
    ;;
  devel)
    URL="${SNAPSHOT_BASE}/R-devel.tar.gz";   TARBALL="R-devel.tar.gz"
    ;;
  *)
    TARBALL="R-${R_VERSION}.tar.gz"; URL="${R_BASE_URL_RELEASE}/${TARBALL}"
    ;;
esac

echo "Downloading: ${URL}"
tmpdir=$(mktemp -d); trap 'rm -rf "${tmpdir}"' EXIT
(cd "${tmpdir}" && curl -fL -o "${TARBALL}" "${URL}")
(cd "${tmpdir}" && tar -xf "${TARBALL}")
SRCDIR=$(find "${tmpdir}" -maxdepth 1 -type d -name "R-*" -print -quit)
: "${SRCDIR:?Source dir not found}"
[[ "${MAKE_NJOBS}" == "0" ]] && MAKE_NJOBS="$(nproc_auto)"

cd "${SRCDIR}"
./configure \
  --prefix="${R_PREFIX}" \
  --enable-R-shlib \
  --with-blas \
  --with-lapack \
  --with-readline \
  --with-recommended-packages \
  FFLAGS="-O3 -pipe -fPIC" \
  CFLAGS="-O3 -pipe -fPIC" \
  CXXFLAGS="-O3 -pipe -fPIC" \
  FCFLAGS="-O3 -pipe -fPIC"
make -j"${MAKE_NJOBS}"
make install

if [[ "${R_PREFIX}" != "/usr/local" ]]; then
  ln -sf "${R_PREFIX}/bin/R" /usr/local/bin/R
  ln -sf "${R_PREFIX}/bin/Rscript" /usr/local/bin/Rscript
fi

/usr/local/bin/R --version || "${R_PREFIX}/bin/R" --version

if [[ "${PURGE_BUILDDEPS}" == "true" ]]; then
  apt-get purge -y clang cmake ninja-build texinfo || true
  apt-get autoremove -y --purge || true
  apt-get clean
fi
echo "R installation complete."
