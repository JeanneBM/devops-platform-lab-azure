# Stage 2 — application images and Helm

## Scope and evidence

The existing Python calculator and Java Singleton greeting service are reused from
the local lab at commit `0797b65e403d60b206b07655312ff565f6f534a4`.
Both images are multistage, run as UID 10001 and expose `/healthz`.
Python's build stage produces dependency wheels; its runtime installs only from those
wheels. Java's build stage compiles sources and creates the executable JAR; its runtime
contains the JRE and JAR. Developer tests stay outside both runtime images.
Base image tags track their runtime lines; builds are not claimed to be bit-reproducible.

The chart deploys one release per namespace: `pycalculator` in `python` and
`g4g7singleton` in `java`. Each has a ClusterIP service, private loopback access via
port-forward, startup/readiness/liveness probes, resource requests/limits and a
dedicated ServiceAccount with token automount disabled. The applications do not call
Azure or Kubernetes APIs, so they receive no cloud roles or Kubernetes RoleBindings.
Workload Identity support remains enabled on AKS for later actual consumers.

CI tests application behavior, renders/asserts Helm objects, builds both runtime images,
deploys them through PowerShell into kind and tests HTTP behavior. The kind cluster is
test infrastructure only; the Azure operator path never creates a local kind cluster.
CI has no Azure credentials and proves neither ACR authentication nor AKS operations.

## One-command Azure path — future authorized session

Complete stage 1 preflight and `lab.tfvars`. Use PowerShell 7.2+ and install Docker
with Linux containers, kubectl, Azure kubelogin and **Helm 3** in addition to Terraform
and Azure CLI. Helm 4 is rejected because this stage uses Helm 3 atomic upgrade flags.
The Docker daemon must support `linux/amd64` builds (emulation is needed on ARM).
The deploying operator should be the identity specified by `operator_object_id`.

```powershell
# Read-only Azure plan; no image publishing or Helm installation:
pwsh ./scripts/Start-Lab.ps1

# Creates billable infrastructure and deploys/tests both applications:
pwsh ./scripts/Start-Lab.ps1 -Apply
```

Start-Lab fails early if required local application tools are missing. It applies the
plan, sets the local Azure CLI subscription to the explicitly configured subscription,
gets a dedicated `.local/aks.kubeconfig`, converts it for Azure CLI authentication,
builds/pushes images, installs/upgrades Helm releases and runs the HTTP checks.
Every Kubernetes/Helm command targets the explicit kubeconfig rather than a user's
unrelated active context. Terraform state, kubeconfig and plan stay private.

The node identity has registry-scoped AcrPull. The named operator now also receives
registry-scoped AcrPush; no registry admin account is enabled. Role propagation can
take several minutes after creation. If ACR authentication/push or initial AKS access
is denied, inspect the assignment, wait for propagation and retry; do not enable
admin keys as a workaround. Use the original state/config to clean up a partial run.

Each invocation builds a new UTC session tag; do not overwrite earlier tags during
rollback exercises. The generated tag is printed at completion. Build context changes
on the workstation are included, so record the git commit and any uncommitted changes
with live evidence. ACR storage is deleted by Stop-Lab with the rest of the lab.
No ACR Tasks builds or paid monitoring services are introduced in this stage.

## Verify independently

```powershell
$kube = Join-Path (Get-Location) '.local/aks.kubeconfig'
helm list --all-namespaces --kubeconfig $kube
kubectl --kubeconfig $kube -n python get deploy,pods,svc,sa
kubectl --kubeconfig $kube -n java get deploy,pods,svc,sa
pwsh ./scripts/Test-Applications.ps1 -Kubeconfig $kube
```

Expected: two deployed Helm releases; a ready pod in each namespace; ClusterIP
services; health endpoints return 200; addition 2+3 returns 5.0; division by zero
returns 400; Java returns its original Polish, German and Spanish greetings.
The script opens temporary port-forward processes on dynamically allocated loopback
ports and closes them even after test failure. It does not expose services publicly.

To browse manually, run in separate terminals and stop each with Ctrl+C:

```powershell
kubectl --kubeconfig .local/aks.kubeconfig -n python port-forward svc/pycalculator 5000:80
kubectl --kubeconfig .local/aks.kubeconfig -n java port-forward svc/g4g7singleton 8080:80
```

Visit http://localhost:5000 and http://localhost:8080.

## Deliberate failure and rollback exercise

Only run against this disposable lab. First capture the deployed image/tag and history:

```powershell
$kube = Join-Path (Get-Location) '.local/aks.kubeconfig'
helm history pycalculator --namespace python --kubeconfig $kube
kubectl --kubeconfig $kube -n python get deployment pycalculator -o jsonpath='{.spec.template.spec.containers[0].image}'

helm upgrade pycalculator ./charts/lab-app --namespace python --kubeconfig $kube --reuse-values --set-string image.tag=intentionally-missing --atomic --wait --timeout 90s
# Expected nonzero exit: Helm rolls back to the last successful release.

helm history pycalculator --namespace python --kubeconfig $kube
kubectl --kubeconfig $kube -n python get events --sort-by=.lastTimestamp
pwsh ./scripts/Test-Applications.ps1 -Kubeconfig $kube
```

In another terminal, watch pods/events during the failed upgrade. Explain
ErrImagePull/ImagePullBackOff, readiness, and how a Service selects ready endpoints.
Verify the restored image matches the original and the final HTTP tests pass.
Helm's atomic rollback covers that release, not the entire infrastructure or both
applications as a transaction. A failure after Python succeeds may leave Python
running while Java failed; use diagnostics and retry or destroy the lab.

## End every session

```powershell
pwsh ./scripts/Stop-Lab.ps1
pwsh ./scripts/Stop-Lab.ps1 -Destroy
```

Verify both resource groups are gone using the commands in stage 1. The applications
are stateless; stage 2 needs no application backup. Stage 3 now installs disposable Jenkins data. Automated backup/restore remains
stage 4; do not rely on persistence across whole-environment destruction yet.

## Explain it in an interview

* A multistage build separates build dependencies from runtime content; non-root and
  a read-only root filesystem address separate runtime concerns.
* A chart is a versioned deployment template; a release is one installed instance.
* Readiness controls traffic eligibility, liveness triggers restart, startup protects
  slow startup from premature liveness failures.
* ACR authorization differs for the image publisher and kubelet image pull.
* Pods with no API need have no API token. Enabling Workload Identity alone grants nothing.
* CI kind success is application/Kubernetes evidence; ACR/AKS success requires live evidence.

## References

[Helm 3 upgrade and atomic rollback](https://docs.helm.sh/docs/v3/helm/helm_upgrade/)
and [ACR authentication](https://learn.microsoft.com/en-us/azure/container-registry/container-registry-authentication).
