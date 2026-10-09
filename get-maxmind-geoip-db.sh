#!/bin/bash

set -eu -o pipefail

geoip_db_dir="$(cd "${GEOIP_DB_DIR?'ERROR: environment variable GEOIP_DB_DIR must be set.'}" && pwd -P)" \
  || { echo "ERROR: no directory at the value provided by GEOIP_DB_DIR (${GEOIP_DB_DIR})"; exit 1; }
geoip_account_id="${GEOIP_ACCOUNT_ID?'ERROR: environment variable GEOIP_ACCOUNT_ID must be set.'}"
geoip_license_key="${GEOIP_LICENSE_KEY?'ERROR: environment variable GEOIP_LICENSE_KEY must be set.'}"

age_file="${geoip_db_dir}"/.age
geoip_edition_ids='GeoLite2-ASN GeoLite2-City GeoLite2-Country'

# date(1) isn't GNU compliant on MacOS, using gdate(1) in that case
[[ "$(uname  || true)" == "Darwin" ]] && dateCmd="gdate" || dateCmd="date"

## TODO: with curl 8.x, we can remove the tedious piping to grep|cut and ask curl to only returns the "Last-Modified" header with the command below (2 flags: --write-out '%header{last-modified}' and --output /dev/null)
# geoipdb_last_modified="$(curl \
#   --head `# HEAD requests do not count on Maxmind rate limit - https://dev.maxmind.com/geoip/updating-databases/#checking-for-the-latest-release-date` \
#   --location `# Follow redirections: Maxmind may use mirrors without any notice` \
#   --user "${geoip_account_id}:${geoip_license_key}" \
#   --write-out '%header{last-modified}' \
#   --output /dev/null \
#   --silent `# No progress bar` \
#   --show-error `# Print errors if any (useful for debugging)` \
#   'https://download.maxmind.com/geoip/databases/GeoLite2-ASN/download?suffix=tar.gz')"

## Curl 7.x on Ubuntu 22.04 do not support `--write-out` variable `%header` so we use shell piping to grep|cut
geoipdb_last_modified="$(curl \
  --head `# HEAD requests do not count on Maxmind rate limit - https://dev.maxmind.com/geoip/updating-databases/#checking-for-the-latest-release-date` \
  --location `# Follow redirections: Maxmind may use mirrors without any notice` \
  --user "${GEOIP_ACCOUNT_ID}:${GEOIP_LICENSE_KEY}" \
  --silent `# No progress bar` \
  --show-error `# Print errors if any (useful for debugging)` \
  'https://download.maxmind.com/geoip/databases/GeoLite2-ASN/download?suffix=tar.gz' \
| grep -i '^last-modified' \
| cut -d':' -f2 \
| xargs `# Remove any prefix/suffix whitespaces` )"

geoipdb_last_modified_unix="$("${dateCmd}" --date "${geoipdb_last_modified}" +%s)"
echo "[INFO] the latest GeoIP DB from MaxMind was released on ${geoipdb_last_modified} (Unix: ${geoipdb_last_modified_unix})"

# Simulate a 1 month old production GeoIP DB if no '.age' found
production_geoipdb_age_unix="$(cat "${age_file}" || "${dateCmd}" --date '1 month ago' +%s)"
# Note: (GNU)date expect a '@' prefix when `--date` is passed a Unix timestamp
production_geoipdb_age="$("${dateCmd}" --date "@${production_geoipdb_age_unix}")"
echo "[INFO] Current GeoIP Production DB was deployed on ${production_geoipdb_age} (Unix: ${production_geoipdb_age_unix})"

age_diff_in_days=$(( (geoipdb_last_modified_unix - production_geoipdb_age_unix) / 86400 ))
echo "[INFO] GeoIP Production DB and latest MaxMind DB have a difference of ${age_diff_in_days} days"

if [ "${age_diff_in_days}" -gt 7 ]
then
  echo "[INFO] More than 7 days age difference: we need to upgrade the Production DB"

  pushd "${geoip_db_dir}"
  for geoip_edition in $geoip_edition_ids
  do
    binary_permalink="https://download.maxmind.com/geoip/databases/${geoip_edition}/download?suffix=tar.gz"
    checksum_permalink="${binary_permalink}".sha256

    for url in $binary_permalink $checksum_permalink
    do
      echo "[INFO] Downloading ${url} ..."
      curl \
        --silent `# No progress bar` \
        --show-error `# Print errors if any (useful for debugging)` \
        --location `# Follow redirections: Maxmind may use mirrors without any notice` \
        --user "${geoip_account_id}:${geoip_license_key}" \
        --remote-name `# Ask curl to create the local file using the remote server response to infer the filename. Also need --remote-header-name option below.` \
        --remote-header-name `# When curl infers the filename (--remote-name option), it will check the 'Content-Disposition' response header to get the value, instead of using the URL` \
        "${url}"
    done

    # Verify checksum and remove them if not needed anymore
    sha256sum --check ./"${geoip_edition}"_*.sha256
    rm -f ./"${geoip_edition}"_*.sha256

    # Extract the mmdb (binary) DB and remove archive
    # Note: using the short form of `-f` is mandatory (--file won't use wildcard from shell globs)
    # Not: we expect GNU tar 1.x. BSDtar works differently.
    tar --extract --strip-components=1 --directory="${geoip_db_dir}" --wildcards -f "${geoip_edition}"_*.tar.gz '*.mmdb'
    rm -f ./"${geoip_edition}"_*.tar.gz
  done

  # Generate the age file
  echo "${geoipdb_last_modified_unix}" > "${age_file}"

  popd
else
  echo "[INFO] Less than 7 days age difference: no upgrade to perform."
fi

exit 0
