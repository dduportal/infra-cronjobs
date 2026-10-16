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

# mvn_global_opts=("-Dmaven.repo.local=${mvn_local_repo}" "${mvn_dependency_offline_target}")
mvn_global_opts="-Dmaven.test.skip=true -Dexpression=settings.localRepository -Dmaven.repo.local=${mvn_local_repo} ${mvn_dependency_offline_target}"

test -d ./jenkins || git clone "https://github.com/${GITHUB_ORG}/jenkins"
pushd ./jenkins

# Missing deps
missing_deps_file="${MISSING_DEPS_FILE:-../missing-deps.txt}"
ls
test -f "${missing_deps_file}"

while IFS= read -r missing || [[ -n "${missing}" ]]; do
    # Skip blank lines and comments
    [[ -z "${missing//[[:space:]]/}" || "${missing}" =~ ^[[:space:]]*# ]] && continue

    time mvn $mvn_global_opts -Dartifact="${missing}"
done < "${missing_deps_file}"


# missings_deps="org.apache.maven.plugins:maven-clean-plugin:pom:3.5.0  org.apache.maven.plugins:maven-help-plugin:pom:2.0  org.apache.maven.plugins:maven-help-plugin:pom:2.0.1  org.apache.maven.plugins:maven-help-plugin:pom:2.0.2  org.apache.maven.plugins:maven-help-plugin:pom:2.1  org.apache.maven.plugins:maven-help-plugin:pom:2.1.1  org.apache.maven.plugins:maven-help-plugin:pom:2.2  org.apache.maven.plugins:maven-help-plugin:pom:3.0.0  org.apache.maven.plugins:maven-help-plugin:pom:3.0.1  org.apache.maven.plugins:maven-help-plugin:pom:3.1.0  org.apache.maven.plugins:maven-help-plugin:pom:3.1.1  org.apache.maven.plugins:maven-help-plugin:pom:3.2.0  org.apache.maven.plugins:maven-help-plugin:pom:3.3.0  org.apache.maven.plugins:maven-help-plugin:pom:3.4.0  org.apache.maven.plugins:maven-help-plugin:pom:3.4.1  org.apache.maven.plugins:maven-help-plugin:pom:3.5.0  org.apache.maven.plugins:maven-plugins:pom:43  org.apache.maven.plugins:maven-plugins:pom:49  org.apache.maven.plugins:maven-site-plugin:pom:3.22.0 io.jenkins.tools.incrementals:git-changelist-maven-extension:jar:1.13 org.xmlunit:xmlunit-bom:pom:2.13.0 org.apache.maven.plugins:maven-install-plugin:pom:3.2.0 org.apache.maven.plugins:maven-deploy-plugin:pom:3.2.0 org.apache.maven.plugins:maven-help-plugin:pom:3.5.2 org.xmlunit:xmlunit-bom:pom:2.13.0 org.jvnet.hudson:license:jar:1.0"

# read -r -a missings <<< "${missings_deps:-}"
# for missing in "${missings[@]}"; do
# 	time mvn $mvn_global_opts -Dartifact="${missing}"
# done

read -r -a branches <<< "${JENKINS_BRANCHES:-}"
for branch in "${branches[@]}"; do
	git checkout "${branch}"
	sleep 5
    time mvn "${mvn_global_opts[@]}"
done
popd

# # TODO: store only the pom files of private cert repos so we can retrieve their deps

test -d ./bom || git clone "https://github.com/${GITHUB_ORG}/bom"
pushd ./bom
time mvn "${mvn_global_opts[@]}"
# Stay in the bom for its sub-project 'sample-plugin'
read -r -a build_lines <<< "${RELEASE_LINES:-}"
for build_line in "${build_lines[@]}"; do
    mvn_buildline_opts=("${mvn_global_opts}")
    if [[ $build_line != "weekly" ]]; then
        mvn_buildline_opts+=("-P" "${build_line}")
    fi
	read -r -a branches <<< "${BOM_BRANCHES:-}"
	for branch in "${branches[@]}"; do
		git checkout "${branch}"
		time mvn -pl sample-plugin \
			-DincludeScore=runtime,compile,test \
			"${mvn_buildline_opts[@]}"
	done
done
popd


# Generate a new cache archive from the local Maven repository
pushd "${mvn_local_repo}"
find "${mvn_cache_archive}" -name '_remote.repositories' | xargs rm -v || true
df -h .
du -sh .
time tar czf --no-xattrs "${mvn_cache_archive}" ./
du -sh "${mvn_cache_dir}"/*.gz
