from pathlib import Path
import yaml

ROOT = Path(__file__).resolve().parents[1]


def test_helm_uses_complete_plugin_lock():
    locked = (ROOT / "jenkins/plugins.lock.txt").read_text().splitlines()
    locked = [line for line in locked if line.strip()]
    controller = yaml.safe_load((ROOT / "helm-values/jenkins.yaml").read_text())["controller"]
    assert len(locked) == len(set(locked))
    assert controller["installPlugins"] == locked
    assert controller["installLatestPlugins"] is False
    assert controller["installLatestSpecifiedPlugins"] is False
