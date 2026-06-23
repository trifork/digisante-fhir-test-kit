#!/bin/sh
set -eu

# Translate the friendly IG_URLS startup parameter into the native HAPI
# implementationguides.* environment variables the server reads at boot.
#
# IG_URLS is a comma-separated list. Each item is either:
#   <packageUrl>                    -> installed as package "ig<N>" version 0.0.0
#   <name>@<version>=<packageUrl>   -> explicit package coordinates
#
# Any HAPI_FHIR_IMPLEMENTATIONGUIDES_* variables set directly by the caller are
# left untouched, so the stock native configuration still works alongside this.

# Trim leading/trailing spaces using shell builtins only (the distroless base
# image ships a single busybox binary with no applet symlinks, so no sed/awk).
trim() {
  s=$1
  while case "$s" in ' '*) true ;; *) false ;; esac; do s=${s#?}; done
  while case "$s" in *' ') true ;; *) false ;; esac; do s=${s%?}; done
  printf '%s' "$s"
}

if [ -n "${IG_URLS:-}" ]; then
  i=0
  OLD_IFS=$IFS
  IFS=','
  for entry in $IG_URLS; do
    IFS=$OLD_IFS
    entry=$(trim "$entry")
    [ -z "$entry" ] && { IFS=','; continue; }
    case "$entry" in
      *@*=*)
        coords=${entry%%=*}
        url=${entry#*=}
        name=${coords%@*}
        version=${coords#*@}
        ;;
      *)
        url=$entry
        name="ig${i}"
        version="0.0.0"
        ;;
    esac
    export "HAPI_FHIR_IMPLEMENTATIONGUIDES_IG${i}_PACKAGEURL=${url}"
    export "HAPI_FHIR_IMPLEMENTATIONGUIDES_IG${i}_NAME=${name}"
    export "HAPI_FHIR_IMPLEMENTATIONGUIDES_IG${i}_VERSION=${version}"
    export "HAPI_FHIR_IMPLEMENTATIONGUIDES_IG${i}_INSTALLMODE=STORE_AND_INSTALL"
    # Pull in the IG's declared dependency packages (ch-core, terminology,
    # IPS/extensions, etc.) — including packages that provide profiles referenced
    # via the structuredefinition-imposeProfile extension — so they install too.
    export "HAPI_FHIR_IMPLEMENTATIONGUIDES_IG${i}_FETCHDEPENDENCIES=true"

    # Exclude dependency packages (regex on package id) from transitive install.
    # The defaults are "infrastructure" packages that HAPI's package installer
    # cannot ingest and which would otherwise abort startup:
    #   hl7.terminology.r4      -> HAPI-1764 "theKey must not be null"
    #   hl7.fhir.uv.xver-r5.r4  -> HAPI-0521 invalid (over-long) FHIR resource id
    # These provide terminology/cross-version helpers, not profiles, so excluding
    # them does not affect the IGs' profiles (incl. imposeProfile targets).
    # Override/clear via IG_DEPENDENCY_EXCLUDES (comma-separated; empty to disable).
    excludes=${IG_DEPENDENCY_EXCLUDES-hl7.terminology.r4,hl7.fhir.uv.xver-r5.r4}
    k=0
    while [ -n "$excludes" ]; do
      case "$excludes" in
        *,*) ex=${excludes%%,*}; excludes=${excludes#*,} ;;
        *)   ex=$excludes; excludes= ;;
      esac
      ex=$(trim "$ex")
      [ -n "$ex" ] && { export "HAPI_FHIR_IMPLEMENTATIONGUIDES_IG${i}_DEPENDENCYEXCLUDES_${k}=${ex}"; k=$((k + 1)); }
    done

    echo "[entrypoint] IG ${i}: name=${name} version=${version} url=${url} (fetchDependencies=true, excludes=${IG_DEPENDENCY_EXCLUDES-hl7.terminology.r4,hl7.fhir.uv.xver-r5.r4})"
    i=$((i + 1))
    IFS=','
  done
  IFS=$OLD_IFS
fi

# Branding: if a name file is mounted (or baked in), use it as the tester name
# unless the caller already set HAPI_FHIR_TESTER_HOME_NAME explicitly.
if [ -z "${HAPI_FHIR_TESTER_HOME_NAME:-}" ] && [ -r /branding/name.txt ]; then
  read -r brand_name < /branding/name.txt || brand_name=""
  if [ -n "$brand_name" ]; then
    export HAPI_FHIR_TESTER_HOME_NAME="$brand_name"
    echo "[entrypoint] tester name: ${brand_name}"
  fi
fi

# Launch the HAPI server. This mirrors the upstream hapiproject/hapi (distroless)
# entrypoint. If a future base image changes its launch command, update this exec
# line -- or bypass IG_URLS and run the stock image with native
# HAPI_FHIR_IMPLEMENTATIONGUIDES_* variables instead.
exec java \
  --class-path /app/main.war \
  -Dloader.path="main.war!/WEB-INF/classes/,main.war!/WEB-INF/,/app/extra-classes" \
  org.springframework.boot.loader.PropertiesLauncher "$@"
