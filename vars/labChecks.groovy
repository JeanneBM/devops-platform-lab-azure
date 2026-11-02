def call() {
    echo 'LAB_SHARED_LIBRARY_LOADED'
    podTemplate(namespace: 'jenkins-agents', yaml: libraryResource('agents/tester.yaml'),
                podRetention: never(), idleMinutes: 0) {
        node(POD_LABEL) {
            stage('Checkout') {
                checkout scm
                sh 'echo "LAB_AGENT_HOST=$(hostname)"'
            }
            stage('Python tests') {
                container('python') {
                    sh '''
                        python -m venv .venv
                        .venv/bin/python -m pip install --no-cache-dir -r requirements-dev.txt
                        .venv/bin/python -m pytest tests/test_calculator.py -q --junitxml=reports/python.xml
                    '''
                }
            }
            stage('Java tests') {
                container('java') {
                    sh 'bash scripts/test-java.sh'
                }
            }
            stage('Evidence') {
                archiveArtifacts artifacts: 'reports/*.xml', fingerprint: true
                echo 'LAB_DYNAMIC_AGENT_TESTS_PASSED'
            }
        }
    }
}
