pipeline {
    agent any
    
    environment {
        ACR_URL = "haadtechacr2026.azurecr.io" 
        ACR_CRED_ID = "acr-credentials" 
        
        FRONTEND_IMAGE = "haadtech-frontend"
        BACKEND_IMAGE = "haadtech-php"
        TAG = "v${BUILD_NUMBER}" 
    }

    stages {
        stage('1. Checkout') {
            steps {
                checkout scm
                echo "Đã kéo mã nguồn từ GitHub"
            }
        }

        stage('2. Build Images') {
            steps {
                script {
                    // Build Frontend từ folder docker/frontend
                    sh "docker build -t ${ACR_URL}/${FRONTEND_IMAGE}:${TAG} -f docker/frontend/Dockerfile ."
                    
                    // Build PHP Backend từ folder docker/php
                    sh "docker build -t ${ACR_URL}/${BACKEND_IMAGE}:${TAG} -f docker/php/Dockerfile ."
                }
            }
        }

        stage('3. Push to Azure') {
            steps {
                script {
                    // Đăng nhập và đẩy image lên ACR bằng thông tin đã lưu
                    withCredentials([usernamePassword(credentialsId: "${ACR_CRED_ID}", usernameVariable: 'ACR_USER', passwordVariable: 'ACR_PASS')]) {
                        sh "docker login ${ACR_URL} -u ${ACR_USER} -p ${ACR_PASS}"
                        sh "docker push ${ACR_URL}/${FRONTEND_IMAGE}:${TAG}"
                        sh "docker push ${ACR_URL}/${BACKEND_IMAGE}:${TAG}"
                    }
                }
            }
        }
    }
    
    post {
        success {
            echo "Sucessfully built and pushed images to Azure Container Registry!"
        }
    }
}