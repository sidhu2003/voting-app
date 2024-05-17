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
                    // Navigate to the directory containing the Dockerfile
                    dir('vote') {
                        // Build the Docker image and assign it to a variable
                        def voteImage = docker.build("${registryUrlVote}:$BUILD_NUMBER")
                        // Store the image reference in the environment for the next stage
                        env.VOTE_IMAGE = voteImage.id
                    }
                }
            }
        }

        stage('Push Vote Image Dockerhub Registry') {
            steps {
                script {
                    // Use the stored image reference to push the image
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
                    // Navigate to the directory containing the Dockerfile
                    dir('result') {
                        // Build the Docker image and assign it to a variable
                        def resultImage = docker.build("${registryUrlResult}:$BUILD_NUMBER")
                        // Store the image reference in the environment for the next stage
                        env.RESULT_IMAGE = resultImage.id
                    }
                }
            }
        }

        stage('Push Result Image Dockerhub Registry') {
            steps {
                script {
                    // Use the stored image reference to push the image
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
                    // Navigate to the directory containing the Dockerfile
                    dir('worker') {
                        // Build the Docker image and assign it to a variable
                        def workerImage = docker.build("${registryUrlWorker}:$BUILD_NUMBER")
                        // Store the image reference in the environment for the next stage
                        env.WORKER_IMAGE = workerImage.id
                    }
                }
            }
        }

        stage('Push Worker Image Dockerhub Registry') {
            steps {
                script {
                    // Use the stored image reference to push the image
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
