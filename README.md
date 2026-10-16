# Jenkins Infrastructure Cron Jobs

This repository holds a set of recurring ("cron-like") tasks for the Jenkins Infrastructure.
Each branch hosts an infra.ci.jenkins.io (private controller) pipeline job implementing a single task.


Details in https://github.com/jenkins-infra/helpdesk/issues/4876 for the initialization.


WIP:

depuis /oss/vv/helpdesk/helpdesk5338/maven-cacher/:

borkedMVN_CACHE_DIR=/Users/vv/oss/helpdesk/helpdesk5338 BOM_BRANCHES="master 93d49459b68ca8d2409bfa03fc6b40e5b49c56c4" JENKINS_BRANCHES="76f1e25d73bd735961044c853e263096e8e5d8a0 master stable-2.580" MVN_LOCAL_REPO=/Users/vv/oss/helpdesk/helpdesk5338/maven-cache-17h20 RELEASE_LINES="weekly 2.580.x 2.568.x 2.555.x" GITHUB_ORG=jenkinsci MVN_ARCHIVE_NAME=maven-cache-jenkinsci.tar.gz ./maven-cacher.sh