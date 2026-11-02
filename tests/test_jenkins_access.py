from pathlib import Path
import subprocess
import yaml

ROOT = Path(__file__).resolve().parents[1]


def test_jenkins_authorization_contract():
    rendered = subprocess.check_output([
        'helm', 'template', 'jenkins-access', str(ROOT / 'charts/jenkins-access'),
        '--namespace', 'jenkins',
    ], text=True)
    docs = [doc for doc in yaml.safe_load_all(rendered) if doc]
    assert not any(doc['kind'] in ('ClusterRole', 'ClusterRoleBinding') for doc in docs)
    role = next(doc for doc in docs if doc['kind'] == 'Role')
    assert role['metadata']['namespace'] == 'jenkins-agents'
    assert all(set(rule['resources']) <= {'pods', 'pods/exec', 'pods/log'} for rule in role['rules'])
    assert all('*' not in rule['verbs'] for rule in role['rules'])
    binding = next(doc for doc in docs if doc['kind'] == 'RoleBinding')
    assert binding['subjects'] == [{'kind': 'ServiceAccount', 'name': 'lab-controller', 'namespace': 'jenkins'}]
    agent = next(doc for doc in docs if doc['kind'] == 'ServiceAccount' and doc['metadata']['name'] == 'lab-agent')
    assert agent['automountServiceAccountToken'] is False
    pod = yaml.safe_load((ROOT / 'resources/agents/tester.yaml').read_text())
    assert pod['spec']['serviceAccountName'] == 'lab-agent'
    assert pod['spec']['automountServiceAccountToken'] is False
    assert not pod['spec'].get('volumes'), 'No host or credential mounts in agent template'
    assert all(not c['securityContext'].get('privileged', False) for c in pod['spec']['containers'])
