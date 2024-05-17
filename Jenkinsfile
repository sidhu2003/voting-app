pipeline {

    agent any

    environment {
        registryUrlVote = 'programmer175/voteapp_vote'
        registryUrlResult = 'programmer175/voteapp_result'
        registryUrlWorker = 'programmer175/voteapp_worker'
        registryCredential = 'programmer175'
    }

    stages {

        stage('Build Vote Image') {
            steps {
                script {
                    
                    dir('vote') {
                        
                        def voteImage = docker.build("${registryUrlVote}:$BUILD_NUMBER")
                        
                        env.VOTE_IMAGE = voteImage.id
                    }
                }
            }
        }

        stage('Push Vote Image Dockerhub Registry') {
            steps {
                script {
                   
                    def voteImage = docker.image(env.VOTE_IMAGE)
                    docker.withRegistry('', registryCredential) {
                        voteImage.push()
                        voteImage.push("latest")
                    }
                }
            }
        }

        stage('Build Result Image') {
            steps {
                script {
                   
                    dir('result') {
                        
                        def resultImage = docker.build("${registryUrlResult}:$BUILD_NUMBER")
                    
                        env.RESULT_IMAGE = resultImage.id
                    }
                }
            }
        }

        stage('Push Result Image Dockerhub Registry') {
            steps {
                script {
            
                    def resultImage = docker.image(env.RESULT_IMAGE)
                    docker.withRegistry('', registryCredential) {
                        resultImage.push()
                        resultImage.push("latest")
                    }
                }
            }
        }

        stage('Build Worker Image') {
            steps {
                script {
                    
                    dir('worker') {
                        
                        def workerImage = docker.build("${registryUrlWorker}:$BUILD_NUMBER")
            
                        env.WORKER_IMAGE = workerImage.id
                    }
                }
            }
        }

        stage('Push Worker Image Dockerhub Registry') {
            steps {
                script {
                    
                    def workerImage = docker.image(env.WORKER_IMAGE)
                    docker.withRegistry('', registryCredential) {
                        workerImage.push()
                        workerImage.push("latest")
                    }
                }
            }
        }

        stage('Deploy using Kubernetes') {
            agent{label 'kops'}
            steps {
                script {
                    sh "helm upgrade --install votingapp-stack helm/votingapp-charts --set voteimage=${registryUrlVote},resultimage=${registryUrlResult},workerimage=${registryUrlWorker}"
                }
            }
        }
    }
}
