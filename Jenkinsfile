pipeline {

    agent any

    environment {
        registryUrlVote = 'programmer175/voteapp_vote'
        registryUrlResult = 'programmer175/voteapp_result'
        registryUrlWorker = 'programmer175/voteapp_worker'
        registryCredential = 'programmer175'
        dockerImage = ''
    }

    stages {

        stage('Build Vote Image') {
            steps {
               script {
                 dir('/vote/Dockerfile'){
                    dockerImage = docker.build registryUrlVote + ":$BUILD_NUMBER"
                 }
                   
                }
            }
        }

        stage('Push Vote Image Dockerhub Registry') {
            steps {
                script {
                    docker.withRegistry( '', registryCredential ) {
                        dockerImage.push()
                        dockerImage.push("latest")
                    }
                }
            }
        }

        stage('Build Result Image') {
            steps {
               script {
                 dir('/result/Dockerfile'){
                    dockerImage = docker.build registryUrlResult + ":$BUILD_NUMBER"
                 }
                   
                }
            }
        }

        stage('Push Result Image Dockerhub Registry') {
            steps {
                script {
                    docker.withRegistry( '', registryCredential ) {
                        dockerImage.push()
                        dockerImage.push("latest")
                    }
                }
            }
        }

        stage('Build Worker Image') {
            steps {
               script {
                 dir('/worker/Dockerfile'){
                    dockerImage = docker.build registryUrlWorker + ":$BUILD_NUMBER"
                 }
                   
                }
            }
        }

        stage('Push Worker Image Dockerhub Registry') {
            steps {
                script {
                    docker.withRegistry( '', registryCredential ) {
                        dockerImage.push()
                        dockerImage.push("latest")
                    }
                }
            }
        }
    }
}