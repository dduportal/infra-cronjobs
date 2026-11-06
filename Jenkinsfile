properties([
  disableConcurrentBuilds(),
  pipelineTriggers([cron('@weekly'),
])])

node('jnlp-linux-arm64') {
  checkout scm

  withEnv([
    'STORAGE_NAME=geoipdbjenkinsio', // Storage Account
    'STORAGE_FILESHARE=geoipdb-jenkins-io', // Fileshare
    "GEOIP_DB_DIR=${env.WORKSPACE}/geoipdata",
  ]) {

    stage('Check Prerequisites') {
      sh '''
      azcopy --version
      rsync --version
      curl --version
      tar --version
      date --version # Must be GNU date on Ubuntu agents
      '''
    }

    stage('Retrieve Current Production GeoIP DB') {
      withCredentials([
        azureServicePrincipal(clientIdVariable: 'JENKINS_INFRA_FILESHARE_CLIENT_ID', clientSecretVariable: 'JENKINS_INFRA_FILESHARE_CLIENT_SECRET', credentialsId: 'cronjob-geoipdbstorage-fileshare-service-principal-writer', subscriptionIdVariable: 'JENKINS_INFRA_SUBSCRIPTION_ID ', tenantIdVariable: 'JENKINS_INFRA_FILESHARE_TENANT_ID'),
      ]) {
        sh '''
        bash ./retrieve-prod-geoip-db.sh
        '''
      }
    }

    stage('Get latest Maxmind GeoIP DB') {
      withCredentials([
        string(credentialsId: 'geoipupdate_account_id', variable: 'GEOIP_ACCOUNT_ID'), // ref. https://github.com/maxmind/geoip/blob/main/doc/docker.md#configuring
        string(credentialsId: 'geoipupdate_license_key', variable: 'GEOIP_LICENSE_KEY'), // ref. https://github.com/maxmind/geoip/blob/main/doc/docker.md#configuring
      ]) {
        sh '''
        bash ./get-maxmind-geoip-db.sh
        '''
      }
    }

    stage('Update Production GeoIP DB') {
      withCredentials([
        azureServicePrincipal(clientIdVariable: 'JENKINS_INFRA_FILESHARE_CLIENT_ID', clientSecretVariable: 'JENKINS_INFRA_FILESHARE_CLIENT_SECRET', credentialsId: 'cronjob-geoipdbstorage-fileshare-service-principal-writer', subscriptionIdVariable: 'JENKINS_INFRA_SUBSCRIPTION_ID ', tenantIdVariable: 'JENKINS_INFRA_FILESHARE_TENANT_ID'),
        file(credentialsId: 'kubeconfig-publick8s-sponsored-getjenkinsio-restarter', variable: 'KUBECONFIG_GETJENKINSIO'),
        file(credentialsId: 'kubeconfig-publick8s-sponsored-updatesjenkinsio-restarter', variable: 'KUBECONFIG_UPDATESJENKINSIO'),
      ]) {
        sh '''
        bash ./update-prod-geoip-db.sh
        '''
      }
    }
  }

  stage('Publish Build Status Report') {
    publishBuildStatusReport()
  }
}
