# Stage 4 — offline Jenkins backup and recovery

`Backup-Jenkins.ps1` refuses active agent pods, stops the controller, waits for its
pod to disappear and mounts the home PVC in a non-root, tokenless maintenance pod.
The home directory is archived with no concurrent controller writer. The controller
is restarted afterwards, including after backup errors once shutdown succeeded.
Run only after builds/queue activity has settled; do not submit new builds during backup.

The archive excludes `secrets/master.key`. The controller key is copied separately
to the operator's user-profile `.devops-lab-keys` directory. The local backup contains
the administrator Kubernetes Secret, home archive and a SHA-256 manifest. On Unix,
sensitive files receive mode 0600. On Windows, use a private user folder and restrict
its NTFS ACLs. Backups are not encrypted by this script: use an encrypted disk or
encrypted backup store. Do not publish archives, keys or administrator Secrets.
The SHA-256 manifest detects accidental corruption, not malicious replacement of
both archive and manifest. Restore only trusted backups made by this lab.

```powershell
$kube = Join-Path (Get-Location) '.local/aks.kubeconfig'
$backup = ./scripts/Backup-Jenkins.ps1 -Kubeconfig $kube
# The command prints the separately stored key path. Preserve both artifacts privately.
```

`Restore-Jenkins.ps1` validates all checksums and the controller image version before
changing storage. It creates a NEW 10 GiB PVC and a new administrator Secret, stops
the controller, extracts home as UID/GID 1000, restores the separate key and updates
Helm to use that claim and Secret. Existing backup/source claims are not overwritten.
Source PVCs use Helm's keep annotation; inspect retained disks during manual cleanup.
Whole-environment Terraform destruction still removes the Azure resource groups/disks.

```powershell
$ref = git rev-parse HEAD
$recovered = ./scripts/Restore-Jenkins.ps1 -Kubeconfig $kube -BackupFolder $backup `
  -KeyFile '<private path to matching .key file>' -SourceRef $ref
./scripts/Test-Jenkins.ps1 -Kubeconfig $kube -AdminSecretName $recovered.AdminSecretName
```

For a recreated environment, first install the same Jenkins version into the new
cluster, then restore. Do not combine recovery with a core/plugin upgrade. The
backup includes plugin files and Jenkins identity/credential data; JCasC and the
init job script intentionally reapply the lab configuration and chosen source ref.
The separate administrator Secret must match the restored Jenkins user configuration.
When backing up an already-restored instance, pass its AdminSecretName explicitly.

## Exercise and evidence

The CI recovery test runs a successful dynamic-agent job, writes a marker, backs up,
restores onto a new PVC, verifies the marker and `builds/1/build.xml`, then runs a
new successful dynamic-agent build. It deletes its temporary local backup files.
It does not upload secret-bearing archives as Actions artifacts. This proves a new
PVC recovery in kind; it does not prove a cross-AKS recreation, Azure disk attachment
or Windows client file-copy behavior. Those remain live-test checks.

For a corruption exercise, copy a backup folder, append one byte to its `home.tgz`,
and attempt restoration: checksum validation must fail before scaling the controller
or creating a new PVC. Restore the unchanged original and verify a fresh build.

If a restore fails, retain the original PVC and backup. Check maintenance pod/events,
the StatefulSet's configured claim and Helm history before retrying. Do not delete
the original claim to force recovery. A stopped controller can be restarted with:

```powershell
kubectl --kubeconfig .local/aks.kubeconfig -n jenkins scale statefulset/jenkins --replicas=1
```

The final lifecycle integration calls backup before destruction and
offers explicit restoration on the next start. Backups and keys must outlive the cluster.

Explain in an interview: quieting builds is different from stopping the controller;
a consistent offline home backup needs the credential key and matching admin Secret;
file ownership matters on restore; a backup is only useful after a recovery test.

[Jenkins backup guidance](https://www.jenkins.io/doc/book/system-administration/backing-up/).

## Stable restart behavior

Jenkins installs plugins once per fresh home PVC (`initializeOnce: true`). The
initialization marker is included in backup/recovery, so restarting a backed-up or
restored controller does not re-download plugin dependencies or depend on an available
update mirror. JCasC reads YAML directly from the mounted /var/jenkins_config ConfigMap;
configuration changes still apply on restart without an auto-reload sidecar. Updating
plugins is a deliberate separate upgrade exercise against a backed-up/test home, not
an implicit side effect of backup or restart. The initial empty controller still needs
plugin download access. CI exposed HTTP 503 failures in repeat downloads before this fix.
