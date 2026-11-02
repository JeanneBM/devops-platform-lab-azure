# Stage 3 — Jenkins administration, shared library and dynamic agents

## Prepared scope

Helm installs upstream `jenkinsci/jenkins` chart **5.10.9**, Jenkins **2.580.2-jdk25**,
one controller with a 10 GiB RWO PVC, and a ClusterIP service. Controller executor
count is zero. JCasC supplies controller/cloud/security configuration. An idempotent
Groovy init script creates the `lab-verify` Pipeline-from-SCM job at the exact
deployed Git commit. No anonymous build access or precommitted password is used;
the upstream chart generates the administrator Secret.

The four explicit plugin versions are recorded in `helm-values/jenkins.yaml`.
The plugin installer resolves minimum compatible transitive dependencies, with
latest-resolution disabled. This is not a complete transitive plugin lock or an
offline/reproducible image. Record installed plugin versions before a real upgrade.
No plugin downloads occur on dynamic agents; the controller's initial installation
needs access to Jenkins update/download services.

`Jenkinsfile` dynamically loads the sandboxed shared library from the repository
root (`vars/labChecks.groovy`, `resources/agents/tester.yaml`). This is a standard
Jenkins shared library, not a Groovy `load` substitute. The default library ref
equals the exact pipeline commit. `SOURCE_REF` exists to permit a deliberate library
version exercise; do not point it at unreviewed code.

The library requests an ephemeral Kubernetes pod with three containers: inbound
agent (pinned), Python 3.12 and Java 21. The shared workspace is ephemeral. The pod
checks out application sources, tests Python/Java, archives a Python test report,
then is removed. It does not build Docker images, push ACR or deploy applications;
those are still local operator actions from stage 2. No Docker socket, privileged
DinD container, Azure credential or Kubernetes API token is given to the agent.
Runtime-line tags for Python/Java may receive upstream updates.

## Authorization boundaries

| Identity | Permissions |
| --- | --- |
| Human operator | Existing AKS operator permissions and ACR push from stages 1–2 |
| `jenkins:lab-controller` | Manage pods, exec and logs only in `jenkins-agents` |
| `jenkins-agents:lab-agent` | No RoleBinding and no API token automount |
| Application SAs | No RoleBindings or token automount |

The controller needs its own in-cluster service-account token to provision agents.
There is no new ClusterRoleBinding. Agents communicate with the controller over
WebSocket/HTTP inside the cluster, so TCP port 50000 is not exposed.
This is not full tenant isolation: a controller that creates pods can choose any
service account in the agent namespace. Keep privileged identities out of that
namespace. A ServiceAccount without API rights does not imply network isolation.
Network policies and workload identity consumers are separate future exercises.

No Jenkins Azure API action exists in this stage, so granting it a Workload Identity
or subscription role would add unnecessary access. Enabled AKS WI/OIDC is reserved
for a later workload with an actual Azure API need.

## Run in a future authorized Azure session

Start from a clean Git checkout pushed to GitHub: the pipeline retrieves committed
code, not local uncommitted Jenkinsfile/library edits. All stage 1–2 tools plus Git
are required. Read cost notes before starting.

```powershell
pwsh ./scripts/Start-Lab.ps1
pwsh ./scripts/Start-Lab.ps1 -Apply
```

With `-Apply`, the entrypoint now creates infrastructure, deploys/tests applications,
installs Jenkins, checks RBAC and triggers the verification job. First boot can take
several minutes while plugins download. A failure does not remove Azure resources:
inspect, retry using the original state, or destroy after preserving needed evidence.

For an already-running lab, install/update Jenkins and verify independently:

```powershell
$kube = Join-Path (Get-Location) '.local/aks.kubeconfig'
$ref = git rev-parse HEAD
pwsh ./scripts/Deploy-Jenkins.ps1 -Kubeconfig $kube -SourceRef $ref
pwsh ./scripts/Test-JenkinsRbac.ps1 -Kubeconfig $kube
pwsh ./scripts/Test-Jenkins.ps1 -Kubeconfig $kube
```

Expected: controller ready, zero built-in executors, correct RBAC allow/deny answers,
shared-library marker, successful Python/Java tests, a real agent observed using
`lab-agent` with token automount false, then no agent pods left. The test obtains
administrator credentials in memory and uses them only through a loopback port-forward;
it does not print them or change anonymous permissions.

## Administration exercise

Forward the service, open http://localhost:8081 and stop forwarding with Ctrl+C:

```powershell
kubectl --kubeconfig .local/aks.kubeconfig -n jenkins port-forward svc/jenkins 8081:8080
```

Retrieve your generated password locally, and do not paste it into public evidence:

```powershell
$encoded = kubectl --kubeconfig .local/aks.kubeconfig -n jenkins get secret jenkins -o jsonpath='{.data.jenkins-admin-password}'
[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($encoded))
```

Use username `admin`. In Manage Jenkins inspect plugins, Kubernetes cloud, the zero
executor count and configuration-as-code. In `lab-verify` inspect SCM commit,
parameters, pipeline stages, console output and archived `reports/python.xml`.
Watch agent pods while starting a new build:

```powershell
kubectl --kubeconfig .local/aks.kubeconfig -n jenkins-agents get pods -w
```

Change the JCasC system message in `helm-values/jenkins.yaml`, commit/push and deploy.
If needed restart the controller to load updated configuration (there is no live
reload sidecar): `kubectl --kubeconfig .local/aks.kubeconfig -n jenkins rollout restart statefulset/jenkins`.
Wait for rollout before verifying. Prefer reviewed code to GUI-only drift.
Do not bulk-upgrade plugins in the GUI. Change pinned versions in code and validate
the set against a fresh controller first. Core/plugins and PVC data must be treated
together during an upgrade; a Helm rollback alone does not reverse data migrations.

## Deliberate failure exercise

In `lab-verify`, use Build with Parameters and set SOURCE_REF to an invalid commit.
The shared library checkout should fail before an agent build. Restore the original
deployed commit and rerun successfully. Then run Test-JenkinsRbac and explain why
the controller can create an agent pod but cannot delete Python deployments or read
secrets in another namespace. Do not grant cluster-admin to make a test pass.

## Persistence, cost and evidence limits

Jenkins adds one managed disk/PVC and shares the existing AKS nodes; it does not add
a node pool, public application IP or Azure role. Disk billing follows Azure disk
tiers/minimum provisioning sizes, not just the requested 10 GiB. Add an allowance for
the disk and longer first-boot/test runtime; the previous 6-hour estimate is not a cap.

The PVC survives controller restarts, but `Stop-Lab.ps1 -Destroy` removes the whole
environment including Jenkins data. **Automated external backup/restore is not yet
implemented (stage 4)**. Treat this stage's jobs/configuration as disposable and
recreated from code. Do not put irreplaceable credentials/jobs/data into this lab.
Keep Terraform state until cleanup is verified.

CI runs the real controller and pipeline in kind. It does not prove AKS Entra RBAC,
managed-csi disk behavior, ACR authentication or actual Azure costs. Record those in
a future authorized live test. Preserve useful console/test evidence privately or
sanitize it before publishing. Current code is not a production Jenkins platform.

## Explain it in an interview

* JCasC configures Jenkins; init Groovy provisions an idempotent Pipeline-from-SCM job.
* The shared library centralizes pipeline steps and pod definition at a versioned ref.
* The controller coordinates builds; ephemeral Kubernetes pods execute them.
* Kubernetes RBAC for the controller differs from Jenkins user authorization.
* Agent lifecycle cleanup is different from backing up the controller's persistent home.
* Helm version rollback is not a substitute for testing Jenkins data restoration.

References: [Kubernetes plugin](https://plugins.jenkins.io/kubernetes/),
[shared libraries](https://www.jenkins.io/doc/book/pipeline/shared-libraries/),
[upstream Helm chart](https://github.com/jenkinsci/helm-charts/tree/main/charts/jenkins).
