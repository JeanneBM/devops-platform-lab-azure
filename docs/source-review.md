# Source review and reuse decisions

Source: [devops-platform-lab-local at 0797b65](https://github.com/JeanneBM/devops-platform-lab-local/tree/0797b65e403d60b206b07655312ff565f6f534a4).
This is the tested local counterpart, previously named `jb_myKubeApp`.

The source has a Flask calculator served by Gunicorn, Java 21 greeting server with
Singleton examples, separate namespaces, non-root application containers,
health probes and resource limits. The Java image is already multistage.
It deploys a Jenkins controller with a PVC; its optional Jenkins pipeline expects
an externally configured agent. It does not yet provide dynamic Kubernetes agents,
JCasC, a shared library or a rehearsed backup/restore procedure.

| Existing element | Azure reuse decision |
| --- | --- |
| `src/python/app.py`, templates, tests and dependencies | Copied from the pinned source commit; calculator behavior preserved |
| `src/java/src`, tests and multistage Dockerfile | Copied; greeting and health endpoints preserved |
| Python Dockerfile | Non-root Gunicorn preserved; dependency wheels now built in a separate stage |
| Kubernetes probes/resources/security contexts | Translated into charts/lab-app; chart assertions and HTTP verification added |
| Kustomize structure and kind configuration | Retain in local repository; Azure deployments will use Helm |
| `scripts/build.sh` OCI source label | Retain the principle, but use the Azure repository URL for Azure-built images |
| Jenkins single-controller/Recreate/PVC | Carry the storage safety principle into the Jenkins Helm configuration |
| Root Jenkinsfile | Evolve to Kubernetes pod agents and a shared library in stage 3 |
| Local `port-forward` access | Retain for the lab; no application LoadBalancer or Ingress initially |

Stage 1 established Azure infrastructure. Stage 2 copies application sources and unit tests
from the pinned commit; the Python Dockerfile is deliberately changed to multistage.
Application CI builds these sources and exercises the actual Helm deployments in kind.
It does not assume old GHCR images prove a new ACR deployment.

Avoid these misleading claims: enabling Workload Identity alone grants no Azure
permissions; enabling a network policy engine alone isolates no namespaces; running
Jenkins alone does not execute pipelines or create agents.
