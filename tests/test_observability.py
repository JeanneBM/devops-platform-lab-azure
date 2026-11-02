from pathlib import Path
import json
import subprocess
import yaml

ROOT = Path(__file__).resolve().parents[1]


def test_observability_contract():
    rendered = subprocess.check_output(['helm', 'template', 'observability', str(ROOT / 'charts/observability'), '--namespace', 'observability'], text=True)
    docs = [d for d in yaml.safe_load_all(rendered) if d]
    deployments = [d for d in docs if d['kind'] == 'Deployment']
    assert len(deployments) == 6
    assert not any(d['kind'] in ('ClusterRole', 'ClusterRoleBinding', 'PersistentVolumeClaim') for d in docs)
    assert all(d['spec']['type'] == 'ClusterIP' for d in docs if d['kind'] == 'Service')
    for d in deployments:
        pod = d['spec']['template']['spec']
        assert pod['securityContext']['runAsNonRoot']
        assert all(c['resources']['limits']['memory'] for c in pod['containers'])
        assert all('hostPath' not in v for v in pod['volumes'])
        assert pod['automountServiceAccountToken'] == (d['metadata']['name'] in ('alloy', 'kube-state-metrics'))
    config = next(d for d in docs if d['kind'] == 'ConfigMap')['data']
    rules = yaml.safe_load(config['alerts.yml'])
    assert 'LabApplicationUnavailable' in {rule['alert'] for rule in rules['groups'][0]['rules']}
    dashboard = json.loads(config['lab.json'])
    assert {p['datasource']['uid'] for p in dashboard['panels']} == {'prometheus', 'loki'}
    assert len(dashboard['panels']) >= 5
