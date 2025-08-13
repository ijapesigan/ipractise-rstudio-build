#!/usr/bin/env bash
# configure-posit-ppm.sh
# Ensure all R and RStudio sessions on Ubuntu use Posit Package Manager (PPM)
# with Linux binaries preferred.
#
# Usage:
#   sudo ./configure-posit-ppm.sh
#
# Env overrides:
#   PPM_URL=...                      # CRAN repo (defaults to __linux__/{codename}/latest)
#   PPM_FORCE=true                   # overwrite existing configs
#   PPM_CLEAN_USER_PREFS=true        # remove user-level CRAN mirror overrides
#   R_MAKE_NJOBS=<N>                 # default parallel compiles (exported into R)
#
# Files written:
#   /etc/R/Rprofile.site             # sets repos, binary-first, libcurl, parallel compiles
#   /etc/R/Renviron.site             # exports PPM_URL + renv override + R_MAKE_NJOBS
#   /etc/rstudio/rsession.conf       # authoritative CRAN mirror for RStudio
#
set -Eeuo pipefail
IFS=$'\n\t'
export DEBIAN_FRONTEND=noninteractive

if [[ ${EUID:-0} -ne 0 ]]; then
  echo "Please run as root (sudo)." >&2
  exit 1
fi

# shellcheck source=/dev/null
source /etc/os-release || { echo "Cannot read /etc/os-release"; exit 1; }

# Determine default PPM URL from codename, allow override.
case "${UBUNTU_CODENAME:-}" in
  jammy|noble) default_ppm="https://packagemanager.posit.co/cran/__linux__/${UBUNTU_CODENAME}/latest" ;;
  *)           default_ppm="https://packagemanager.posit.co/cran/latest" ;;
esac
PPM_URL="${PPM_URL:-${default_ppm}}"
PPM_FORCE="${PPM_FORCE:-false}"
PPM_CLEAN_USER_PREFS="${PPM_CLEAN_USER_PREFS:-false}"
R_MAKE_NJOBS="${R_MAKE_NJOBS:-}"

echo "Using PPM URL: ${PPM_URL}"

mkdir -p /etc/R /etc/rstudio

RPROFILE_SITE="/etc/R/Rprofile.site"
RENVSITE="/etc/R/Renviron.site"
RSESSION_CONF="/etc/rstudio/rsession.conf"

write_rprofile() {
  cat > "${RPROFILE_SITE}" <<'EOF'
## System-wide defaults to prefer Posit Package Manager (PPM) binaries
local({
  r <- getOption("repos")
  r["CRAN"] <- Sys.getenv("PPM_URL",
    "https://packagemanager.posit.co/cran/__linux__/noble/latest")
  options(repos = r)

  # Prefer Linux binaries; don't auto-fallback to source unless needed
  options(pkgType = "binary")
  options(install.packages.check.source = "no")

  # Use libcurl transport
  options(download.file.method = "libcurl")

  # Parallelize compiles sensibly
  if (nzchar(Sys.getenv("R_MAKE_NJOBS"))) {
    options(Ncpus = as.integer(Sys.getenv("R_MAKE_NJOBS")))
  } else {
    n <- tryCatch(parallel::detectCores(), error = function(e) 1L)
    options(Ncpus = if (is.finite(n) && n > 1) n else 1L)
  }
})
EOF
}

write_renviron() {
  cat > "${RENVSITE}" <<EOF
## Ensure renv/tooling use the same repo; expose PPM + compile threads
PPM_URL=${PPM_URL}
RENV_CONFIG_REPOS_OVERRIDE=${PPM_URL}
${R_MAKE_NJOBS:+R_MAKE_NJOBS=${R_MAKE_NJOBS}}
EOF
}

write_rsession_conf() {
  # This sets the authoritative default repo for RStudio sessions
  # (prevents fallback to cran.rstudio.com)
  cat > "${RSESSION_CONF}" <<EOF
r-cran-repos=${PPM_URL}
EOF
}

maybe_write() {
  # maybe_write <path> <writer_fn_name>
  local path="$1"; local writer="$2"
  if [[ -f "${path}" && "${PPM_FORCE}" != "true" ]]; then
    echo "Exists: ${path} (use PPM_FORCE=true to overwrite)"
  else
    "${writer}"
    echo "Wrote ${path}"
  fi
}

maybe_write "${RPROFILE_SITE}" write_rprofile
maybe_write "${RENVSITE}" write_renviron
maybe_write "${RSESSION_CONF}" write_rsession_conf

# Optionally clean user-level overrides that point to other CRAN mirrors
if [[ "${PPM_CLEAN_USER_PREFS}" == "true" ]]; then
  echo "Cleaning user-level CRAN mirror overrides…"
  for home in /home/*; do
    [ -d "$home" ] || continue
    user="$(basename "$home")"
    # RStudio prefs
    pref="${home}/.config/rstudio/rstudio-prefs.json"
    if [[ -f "${pref}" ]]; then
      sed -i '/"cran_mirror"/d' "${pref}" || true
      chown "${user}:${user}" "${pref}" || true
      echo "  cleaned ${pref}"
    fi
    # ~/.Rprofile repos lines
    rprof="${home}/.Rprofile"
    if [[ -f "${rprof}" ]]; then
      sed -i '/repos/d' "${rprof}" || true
      chown "${user}:${user}" "${rprof}" || true
      echo "  cleaned ${rprof}"
    fi
  done
  # root user too
  sed -i '/"cran_mirror"/d' /root/.config/rstudio/rstudio-prefs.json 2>/dev/null || true
  sed -i '/repos/d' /root/.Rprofile 2>/dev/null || true
fi

# Restart RStudio Server to pick up rsession.conf (ignore if not installed)
if systemctl list-unit-files | grep -q '^rstudio-server\.service'; then
  systemctl restart rstudio-server || true
fi

echo "PPM configuration complete."
echo "Verify inside R/RStudio:"
echo "  > getOption('repos')"
echo "  > getOption('pkgType'); getOption('install.packages.check.source')"
