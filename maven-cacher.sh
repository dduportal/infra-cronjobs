#!/bin/bash
set -eux -o pipefail

: "${MVN_ARCHIVE_NAME:?Set MVN_ARCHIVE_NAME}"
: "${RELEASE_LINES:?Set RELEASE_LINES}"
: "${GITHUB_ORG:?Set GITHUB_ORG}"
: "${JENKINS_BRANCHES:-master}"
: "${BOM_BRANCHES:-master}"

# TODO: loop over branches

mvn_cache_dir="${MVN_CACHE_DIR:-"/tmp"}"
test -d "${mvn_cache_dir}"
mvn_local_repo="${MVN_LOCAL_REPO:-"${HOME}/.m2/repository"}"
mvn_cache_archive="${mvn_cache_dir}/${MVN_ARCHIVE_NAME}"
# As 'dependency:go-offline' always use latest and until https://github.com/jenkins-infra/helpdesk/issues/5198 is fixed let's pin to 3.10.0
mvn_dependency_offline_target='org.apache.maven.plugins:maven-dependency-plugin:3.10.0:go-offline'
mvn_global_opts=("-Dmaven.repo.local=${mvn_local_repo}")
script_dir="$(cd "$(dirname "$0")" && pwd -P)"

# Missing deps
missing_deps_file="${script_dir}"/missing-deps.txt
test -f "${missing_deps_file}"

while IFS= read -r missing || [[ -n "${missing}" ]]; do
    # Skip blank lines and comments
    [[ -z "${missing//[[:space:]]/}" || "${missing}" =~ ^[[:space:]]*# ]] && continue

		missing_group_id="$(echo "$missing" | cut -d':' -f1)"
		missing_artifact_id="$(echo "$missing" | cut -d':' -f2)"
		missing_packaging="$(echo "$missing" | cut -d':' -f3)"
		missing_version="$(echo "$missing" | cut -d':' -f4)"

		time mvn "${mvn_global_opts[@]}" dependency:get \
			-DgroupId="${missing_group_id}" \
			-DartifactId="${missing_artifact_id}"\
			-Dversion="${missing_version}" \
			-Dpackaging="${missing_packaging}"
done < "${missing_deps_file}"

test -d ./jenkins || git clone "https://github.com/${GITHUB_ORG}/jenkins"
pushd ./jenkins

read -r -a branches <<< "${JENKINS_BRANCHES:-}"
for branch in "${branches[@]}"; do
	git checkout "${branch}"
  time mvn "${mvn_global_opts[@]}" "${mvn_dependency_offline_target}"
done
popd

test -d ./bom || git clone "https://github.com/${GITHUB_ORG}/bom"
pushd ./bom
# Stay in the bom for its sub-project 'sample-plugin'
read -r -a build_lines <<< "${RELEASE_LINES:-}"
for build_line in "${build_lines[@]}"; do
	mvn_buildline_opts=("${mvn_global_opts[@]}")
	if [[ $build_line != "weekly" ]]; then
			mvn_buildline_opts+=("-P" "${build_line}")
	fi

	read -r -a branches <<< "${BOM_BRANCHES:-}"
	for branch in "${branches[@]}"; do
		git checkout "${branch}"
		time mvn -pl sample-plugin \
			-DincludeScore=runtime,compile,test \
			"${mvn_buildline_opts[@]}" \
			"${mvn_dependency_offline_target}"
	done
done
popd


# Generate a new cache archive from the local Maven repository
pushd "${mvn_local_repo}"
# Remove Maven internal resolutions files
find "${mvn_cache_archive}" -name '_remote.repositories' | xargs -0 rm -v || true
df -h .
du -sh .
time tar czf --no-xattrs "${mvn_cache_archive}" ./
du -sh "${mvn_cache_dir}"/*.gz
