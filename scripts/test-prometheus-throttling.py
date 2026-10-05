#!/usr/bin/env python3
"""Test the deployed rule with promtool (requires PyYAML and promtool 2.48.1+).

For a remote promtool, --export-dir writes both inputs without running tests.
"""
import argparse
from pathlib import Path
import shutil
import subprocess
import tempfile

import yaml

ROOT = Path(__file__).resolve().parents[1]


def export(directory):
    directory.mkdir(parents=True, exist_ok=True)
    source = ROOT / 'clusters/production/apps/monitoring/node-resource-alerts.yaml'
    rule = yaml.safe_load(source.read_text())
    (directory / 'node-resource-alerts.rules.yaml').write_text(
        yaml.safe_dump(rule['spec'], allow_unicode=True, sort_keys=False))
    shutil.copyfile(ROOT / 'tests/monitoring/node-cpu-throttling.test.yaml',
                    directory / 'node-cpu-throttling.test.yaml')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--export-dir', type=Path)
    parser.add_argument('--promtool', default='promtool')
    args = parser.parse_args()
    if args.export_dir:
        export(args.export_dir)
        return
    with tempfile.TemporaryDirectory(prefix='prometheus-rule-tests-') as tmp:
        directory = Path(tmp)
        export(directory)
        subprocess.run([args.promtool, 'check', 'rules',
                        'node-resource-alerts.rules.yaml'], cwd=directory, check=True)
        subprocess.run([args.promtool, 'test', 'rules',
                        'node-cpu-throttling.test.yaml'], cwd=directory, check=True)


if __name__ == '__main__':
    main()
