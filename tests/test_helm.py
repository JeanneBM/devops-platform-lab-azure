"""Check rendered chart contracts rather than Helm template implementation details."""
from pathlib import Path
import subprocess

import pytest
import yaml

ROOT = Path(__file__).resolve().parents[1]


@pytest.mark.parametrize('name,namespace,port', [
    ('pycalculator', 'python', 5000),
    ('g4g7singleton', 'java', 8080),
])
def test_rendered_application(name, namespace, port):
    rendered = subprocess.check_output([
        'helm', 'template', name, str(ROOT / 'charts/lab-app'),
        '--namespace', namespace, '--values', str(ROOT / f'helm-values/{namespace}.yaml'),
        '--set-string', f'image.repository=example.azurecr.io/{name}',
        '--set-string', 'image.tag=test-commit',
    ], text=True)
    docs = {d['kind']: d for d in yaml.safe_load_all(rendered) if d}
    assert set(docs) == {'Deployment', 'Service', 'ServiceAccount'}
    dep = docs['Deployment']
    pod = dep['spec']['template']['spec']
    app = pod['containers'][0]
    assert app['image'] == f'example.azurecr.io/{name}:test-commit'
    assert pod['automountServiceAccountToken'] is False
    assert docs['ServiceAccount']['automountServiceAccountToken'] is False
    assert pod['serviceAccountName'] == docs['ServiceAccount']['metadata']['name']
    assert pod['securityContext']['runAsNonRoot'] is True
    assert app['securityContext']['allowPrivilegeEscalation'] is False
    assert app['securityContext']['readOnlyRootFilesystem'] is True
    assert app['resources']['requests'] and app['resources']['limits']
    assert app['ports'][0]['containerPort'] == port
    assert all(app[p]['httpGet']['path'] == '/healthz'
               for p in ('startupProbe', 'readinessProbe', 'livenessProbe'))
    service = docs['Service']
    assert service['spec']['type'] == 'ClusterIP'
    assert service['spec']['selector'] == dep['spec']['selector']['matchLabels']
    assert service['spec']['ports'][0]['targetPort'] == app['ports'][0]['name']
