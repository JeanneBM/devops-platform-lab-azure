// The dynamic library is sandboxed and versioned alongside this pipeline.
timeout(time: 12, unit: 'MINUTES') {
    library identifier: "devops-lab@${params.SOURCE_REF}", retriever: modernSCM([
        $class: 'GitSCMSource',
        remote: 'https://github.com/JeanneBM/devops-platform-lab-azure.git'
    ])
    labChecks()
}
