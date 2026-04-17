pipeline {
    agent any
    
    environment {
        // THAY BẰNG TÊN ACR CỦA BRO
        ACR_URL = "haadtechacr2026.azurecr.io" 
        ACR_CRED_ID = "acr-credentials"
        ENV_CRED_ID = "haadtech-env" // ID file .env trong Jenkins Credentials
        KUBECONFIG_ID = "aks-kubeconfig" // ID file kubeconfig trong Jenkins Credentials
        
        FRONTEND_IMAGE = "haadtech-frontend"
        BACKEND_IMAGE = "haadtech-php"
        TAG = "v${BUILD_NUMBER}" 
    }

    stages {
        stage('1. Checkout Code') {
            steps {
                // Tự động kéo code từ repo GitHub đã cấu hình trong Job
                checkout scm
                echo "Đã kéo mã nguồn mới nhất từ GitHub"
            }
        }

        stage('2. Build Images with Env') {
            steps {
                script {
                    // 1. Móc file .env thật từ két sắt Jenkins ra để chuẩn bị đóng gói
                    withCredentials([file(credentialsId: "${ENV_CRED_ID}", variable: 'SECRET_ENV')]) {
                        // Copy file .env xịn vào thư mục gốc để Docker thấy
                        sh "cp \$SECRET_ENV ./.env"
                        
                        echo "Bắt đầu build Docker Images với biến môi trường xịn..."
                        // Build Frontend — pass VITE_* vars as build args so Vite bakes them into the JS bundle
                        sh """
                            export \$(cat .env | grep -v '^#' | grep -v '^\\s*\$' | xargs)
                            docker build \\
                                --build-arg VITE_SUPABASE_URL=\$VITE_SUPABASE_URL \\
                                --build-arg VITE_SUPABASE_ANON_KEY=\$VITE_SUPABASE_ANON_KEY \\
                                --build-arg VITE_SUPABASE_PUBLISHABLE_KEY=\$VITE_SUPABASE_PUBLISHABLE_KEY \\
                                -t ${ACR_URL}/${FRONTEND_IMAGE}:${TAG} \\
                                -f docker/frontend/Dockerfile .
                        """
                        
                        // Build Backend
                        sh "docker build -t ${ACR_URL}/${BACKEND_IMAGE}:${TAG} -f docker/php/Dockerfile ."
                    }
                }
            }
        }

        stage('3. Push to Azure ACR') {
            steps {
                script {
                    // Đăng nhập và đẩy hàng lên kho ACR
                    withCredentials([usernamePassword(credentialsId: "${ACR_CRED_ID}", usernameVariable: 'ACR_USER', passwordVariable: 'ACR_PASS')]) {
                        sh "docker login ${ACR_URL} -u ${ACR_USER} -p ${ACR_PASS}"
                        sh "docker push ${ACR_URL}/${FRONTEND_IMAGE}:${TAG}"
                        sh "docker push ${ACR_URL}/${BACKEND_IMAGE}:${TAG}"
                    }
                }
            }
        }

        stage('4. Deploy to AKS') {
            steps {
                script {
                    // Dùng chìa khóa Kubeconfig để ra lệnh cho thằng quản đốc AKS
                    withCredentials([file(credentialsId: "${KUBECONFIG_ID}", variable: 'KUBECONFIG')]) {
                        echo "Đang ra lệnh cho cụm AKS cập nhật phiên bản mới..."
                        
                        sh "kubectl create secret generic supabase-secret --from-env-file=./.env --dry-run=client -o yaml | kubectl apply -f - --kubeconfig=\$KUBECONFIG"
                        
                        // Áp dụng các file cấu hình Deployment/Service trong folder k8s
                        sh "kubectl apply -f k8s/ --kubeconfig=\$KUBECONFIG"
                        
                        // Ép các Deployment phải thay container cũ bằng bản image mới vừa build xong
                        sh "kubectl set image deployment/haadtech-frontend frontend=${ACR_URL}/${FRONTEND_IMAGE}:${TAG} --kubeconfig=\$KUBECONFIG"
                        sh "kubectl set image deployment/haadtech-backend backend=${ACR_URL}/${BACKEND_IMAGE}:${TAG} --kubeconfig=\$KUBECONFIG"
                        
                        // Theo dõi quá trình thay máu xem có thành công không
                        sh "kubectl rollout status deployment/haadtech-frontend --kubeconfig=\$KUBECONFIG"
                        sh "kubectl rollout status deployment/haadtech-backend --kubeconfig=\$KUBECONFIG"
                    }
                }
            }
        }
    }
    
    post {
        success {
            echo "Success! Pipeline completed successfully."
        }
        failure {
            echo "Failure! Please check the logs for details."
        }
    }
}