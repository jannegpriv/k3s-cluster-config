#!/usr/bin/env python3
"""Export/run real Prometheus rule tests. Requires PyYAML and promtool."""
import argparse
from pathlib import Path
import subprocess
import tempfile
import yaml

ROOT = Path(__file__).resolve().parents[1]
NS = 'namespace="basic-memory"'
CJ = NS + ',cronjob="basic-memory-backup"'


def series(metric, value, labels=CJ):
    return {'series': metric + '{' + labels + '}', 'values': str(value) + '+0x1930'}


def export(directory):
    directory.mkdir(parents=True, exist_ok=True)
    source = yaml.safe_load((ROOT / 'clusters/production/apps/basic-memory/monitoring.yaml').read_text())
    (directory / 'rules.yaml').write_text(yaml.safe_dump(source['spec'], sort_keys=False))
    summaries = {r['alert']:r['annotations'] for r in source['spec']['groups'][0]['rules'] if 'alert' in r}
    created = series('kube_cronjob_created', 0)
    old = series('kube_cronjob_status_last_successful_time', 0)
    fresh = series('kube_cronjob_status_last_successful_time', 111000)
    manual_labels = NS + ',job_name="basic-memory-backup-recovery-test"'
    manual = [series('kube_job_status_completion_time', 111000, manual_labels),
              series('kube_job_status_succeeded', 1, manual_labels)]
    failed = [series('kube_job_status_completion_time', 111000, manual_labels),
              series('kube_job_status_succeeded', 0, manual_labels)]
    restore_labels = NS + ',job_name="basic-memory-v1-restore"'
    restore = [series('kube_job_status_completion_time', 111000, restore_labels),
               series('kube_job_status_succeeded', 1, restore_labels)]
    cases = [
        ('fresh scheduled backup', [created, fresh], False, False),
        ('manual recovery clears freshness only', [created, old, *manual], False, True),
        ('all backups stale', [created, old], True, True),
        ('failed manual run cannot clear freshness', [created, old, *failed], True, True),
        ('restore job is not a NAS backup', [created, old, *restore], True, True),
        ('never succeeded', [created], True, True),
        ('new schedule has grace period', [series('kube_cronjob_created', 111000)], False, False),
        ('manual first success before any scheduled success', [created, *manual], False, True),
        ('deleted completed jobs retain cron success', [created, fresh], False, False),
        ('missing schedule with fresh manual backup', manual, False, True),
        ('missing schedule without backups', [], False, True),
    ]
    tests = []
    for name, inputs, stale, scheduled in cases:
        checks = []
        for alert, firing in [('BasicMemoryBackupStale', stale), ('BasicMemoryScheduledBackupStale', scheduled)]:
            labels = {'namespace':'basic-memory', 'severity':'warning'}
            if alert == 'BasicMemoryScheduledBackupStale':
                labels['cronjob'] = 'basic-memory-backup'
            checks.append({'eval_time':'32h','alertname':alert,'exp_alerts':
                [{'exp_labels':labels,'exp_annotations':summaries[alert]}] if firing else []})
        tests.append({'name':name,'interval':'1m','input_series':inputs,'alert_rule_test':checks})
    # Exact 30h threshold plus five-minute pending period.
    tests.append({'name':'threshold and pending duration','interval':'1m','input_series':[created,old],
        'alert_rule_test': [
            {'eval_time':when,'alertname':alert,'exp_alerts':
             ([{'exp_labels':dict({'namespace':'basic-memory','severity':'warning'}, **({'cronjob':'basic-memory-backup'} if alert.endswith('ScheduledBackupStale') else {})),
                'exp_annotations':summaries[alert]}] if firing else [])}
            for when,firing in [('30h',False),('30h5m',False),('30h6m',True)]
            for alert in ['BasicMemoryBackupStale','BasicMemoryScheduledBackupStale']]})
    (directory / 'tests.yaml').write_text(yaml.safe_dump({'rule_files':['rules.yaml'],'evaluation_interval':'1m','tests':tests},sort_keys=False))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--export-dir', type=Path)
    parser.add_argument('--promtool', default='promtool')
    args = parser.parse_args()
    if args.export_dir:
        export(args.export_dir)
        return
    with tempfile.TemporaryDirectory(prefix='bm-alert-tests-') as tmp:
        export(Path(tmp))
        for command in [['check','rules','rules.yaml'], ['test','rules','tests.yaml']]:
            subprocess.run([args.promtool, *command],cwd=tmp,check=True)


if __name__ == '__main__':
    main()
