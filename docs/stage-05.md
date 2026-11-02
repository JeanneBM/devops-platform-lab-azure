# Stage 5 — bounded observability and fault exercises

The local chart deploys Prometheus, Blackbox Exporter, Grafana, Loki, Alloy and
kube-state-metrics in `observability`. Image versions are pinned in chart values.
No Azure monitoring workspace, managed Grafana, public service IP or additional PVC
is created. All services are ClusterIP. The complete lifecycle will install this
chart after applications and Jenkins; the namespace roles assume those namespaces exist.

| Signal | Implementation |
| --- | --- |
| Application counters | Python and Java `/metrics`; HTTP request count by status |
| Python latency | Prometheus histogram by normalized route |
| End-to-end availability | HTTP `/healthz` probes through application Services |
| Kubernetes state | Replica configuration, PVC/pod state and restart counters from kube-state-metrics |
| Logs | Alloy reads selected pod logs through the API; Loki stores them on temporary disk |
| Dashboard | Provisioned Azure DevOps Lab dashboard with metrics, alerts and Python logs |
| Alerts | Application unavailable, repeated container restarts, HTTP 5xx increases |

This stage does not collect node CPU utilization, traces, audit logs or APM spans.
Replica/restart metrics are Kubernetes state, not measured CPU/memory usage. Python
uses one Gunicorn worker so in-process counters are accurate for this small lab;
multiple workers would need a tested multiprocess metrics setup. Java uses atomic
status counters. Counters reset on process restart. Dependencies/runtime-line base
images still need maintenance; pinned top-level versions are not a full supply-chain lock.

## Resource and access bounds

Prometheus retains 6 hours / 256 MB of TSDB blocks on a 1 GiB emptyDir. WAL/temporary
files also use that volume, so the block-size flag is not a hard total disk cap.
Loki uses filesystem storage on a 1 GiB emptyDir, with 24-hour retention/compaction
and small ingestion/stream limits. For shorter sessions, destroy/recreation clears
all data. Grafana and Alloy use small bounded emptyDirs. Every component has CPU and
memory limits. Data and dashboards' runtime edits disappear on pod replacement;
dashboard/configuration definitions remain in Git. This is intentionally not durable
production observability. Monitor eviction/OOM events if a limit is exceeded.

Alloy can read pods/logs only in Python, Java, Jenkins and agent namespaces.
kube-state-metrics can read selected objects in those namespaces. Neither gets
cluster-admin, secret-read rights, hostPath mounts or node privileges. Grafana,
Prometheus, Loki and Blackbox have no mounted API token. Loki has no built-in auth
in this lab and relies on internal access; namespace separation alone is not network
isolation. Use only nonsensitive training logs. Grafana has a generated admin password
in a Kubernetes Secret; anonymous access and signup are not enabled.

## Deploy and verify in a running disposable lab

```powershell
$kube = Join-Path (Get-Location) '.local/aks.kubeconfig'
./scripts/Deploy-Observability.ps1 -Kubeconfig $kube
./scripts/Test-Applications.ps1 -Kubeconfig $kube
./scripts/Test-Observability.ps1 -Kubeconfig $kube
```

Expected: both app metric targets up, request counters present, Python deployment
state present, real Python logs in Loki, and a provisioned Grafana dashboard. CI tests
these signals in kind; this is not proof of AKS networking/log behavior.

```powershell
kubectl --kubeconfig .local/aks.kubeconfig -n observability port-forward svc/grafana 3000:3000
kubectl --kubeconfig .local/aks.kubeconfig -n observability port-forward svc/prometheus 9090:9090
```

Use separate terminals. Grafana is http://localhost:3000 (user admin); retrieve its
password locally from `secret/grafana-admin` key `password` using base64 decoding.
Do not share it. Browse the DevOps Lab folder and Explore with Prometheus or Loki.
Prometheus Alerts at http://localhost:9090/alerts shows pending/firing rules.
No external email/Slack notification receiver is configured or contacted.

## Deliberate failures

1. `Test-Observability.ps1 -Kubeconfig $kube -ExerciseAlerts` scales the calculator to
   zero, waits for the availability alert to fire, then restores one replica in a
   finally block and waits for the alert to resolve. Run only against this lab.
2. Repeat the stage 2 missing-image exercise while watching events, the dashboard and
   logs. A rolling update can keep the old pod healthy, so do not assume every failed
   deployment makes the Service unavailable; distinguish rollout failure from outage.
3. Temporarily lower a container memory limit below startup needs through Helm values
   in an isolated session. Inspect OOMKilled, restart count and the restart alert,
   then restore the original values. A controlled OOM is not expected to produce 5xx
   if no process remains available to answer HTTP.
4. Send invalid calculator input and inspect HTTP 400 counters/logs. Client errors
   should not trigger the server-error alert. Explain label cardinality and why raw
   user-provided paths are not used as metric labels.

Explain the signal chain: application exposes metrics; Prometheus scrapes/evaluates;
Grafana queries; Alloy collects logs; Loki stores/query indexes. Alerts here are
visible in Prometheus/Grafana; production notification delivery needs a separate,
authorized receiver and an actual delivery test.
