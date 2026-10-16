def githubOrg = 'jenkinsci-cert'
def archive = "maven-cache-${githubOrg}.tar.gz"
def releaseLines = 'weekly 2.580.x 2.568.x 2.555.x'

node {
    withEnv([
        "MVN_ARCHIVE_NAME=${archive}",
        "GITHUB_ORG=${githubOrg}",
        "RELEASE_LINES=${releaseLines}",
        "MVN_LOCAL_REPO=??????????"
    ]) {
        sh '''

        '''
    }


    archiveArtifacts archive
}