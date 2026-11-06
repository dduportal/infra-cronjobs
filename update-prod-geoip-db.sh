#!/bin/bash

set -eu -o pipefail

geoip_db_dir="$(cd "${GEOIP_DB_DIR?'ERROR: environment variable GEOIP_DB_DIR must be set.'}" && pwd -P)" \
  || { echo "ERROR: no directory at the value provided by GEOIP_DB_DIR (${GEOIP_DB_DIR})"; exit 1; }
# All the following STORAGE_* (upper case) variables are needed by get-fileshare-signed-url.sh
STORAGE_NAME=${STORAGE_NAME:?'ERROR: environment variable STORAGE_NAME must be set.'}
STORAGE_FILESHARE=${STORAGE_FILESHARE:?'ERROR: environment variable STORAGE_FILESHARE must be set.'}
export STORAGE_NAME STORAGE_FILESHARE
# Short lived token
export STORAGE_DURATION_IN_MINUTE=2
# Both read and write are needed
export STORAGE_PERMISSIONS=dlrw

# date(1) isn't GNU compliant on MacOS, using gdate(1) in that case
[[ "$(uname  || true)" == "Darwin" ]] && dateCmd="gdate" || dateCmd="date"

age_file="${geoip_db_dir}"/.age
geoipdb_age_unix="$(cat "${age_file}")"
now_unix="$(${dateCmd} --date 'now' +%s)"
age_diff_in_days=$(( (geoipdb_age_unix - now_unix) / 86400 ))

if [ "${age_diff_in_days}" -gt 7 ]
  echo "[INFO] GeoIP DB age is more than 7 days aged: deploying to production and restarting services"
then
  ####
  # Deploy DB files
  ####

  # Disable debug to ensure token isn't printed in the output
  set +x
  fileShareSignedUrl="$(get-fileshare-signed-url.sh)"
  urlWithoutToken="${fileShareSignedUrl%\?*}"

  # Assuming all data is at the root
  echo "INFO: Copying to: ${urlWithoutToken}"

  # See https://github.com/Azure/azure-storage-azcopy/issues/3024 for the piped prefix workaround
  : | azcopy copy \
    "${geoip_db_dir}/*" "${fileShareSignedUrl}" \
    --skip-version-check `# Do not check for new azcopy versions (we have updatecli + puppet for this)` \
    --log-level=ERROR `# Do not write too much logs (I/O...)` \
    --overwrite="ifSourceNewer" `# Upload if and only if the updategeoip as updated the files` \
  || \
    { cat "${HOME}/.azcopy/*"; exit 1; }   # Dump the logs in case of error during azcopy copy
  unset fileShareSignedUrl

  ####
  # Then restart services to ensure they load the new DB
  ####
  echo '[INFO]: restarting service "updates.jenkins.io"...'
  # TODO: track namespace and deployment name with updatecli from https://github.com/jenkins-infra/kubernetes-management/
  kubectl --kubeconfig="${KUBECONFIG_UPDATESJENKINSIO}" --namespace=updates-jenkins-io rollout status --watch deployment updates-jenkins-io-content-mirrorbits

  # TODO: track namespace and deployment name with updatecli from https://github.com/jenkins-infra/kubernetes-management/
  echo '[INFO]: restarting service "get.jenkins.io"...'
  kubectl --kubeconfig="${KUBECONFIG_GETJENKINSIO}" --namespace=get-jenkins-io rollout status --watch deployment get-jenkins-io-content-mirrorbits
else
  echo '[INFO] GeoIP DB age is less than 7 days aged: no action to perform'
fi
