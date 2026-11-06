"""Round trip a validation backup through a separate NAS folder onto a fresh PVC."""
import datetime
import json
import os
from pathlib import Path
import shlex
import shutil
import tarfile
import backup

os.umask(0o077)
target = Path('/restore')
if any(p.name != 'lost+found' for p in target.iterdir()):
    raise RuntimeError('Restore PVC must be empty')
os.environ['SSHPASS'] = Path('/credentials/password').read_text().rstrip('\n')
destination = os.environ['BASIC_MEMORY_BACKUP_DESTINATION']
assert destination == '/volume1/k3s_backups/basic-memory-upgrade-test-20261106'
stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
archive = Path('/work') / ('basic-memory-' + stamp + '.tar.gz')
backup.create_archive(Path('/data'), archive)
expected = backup.verify_archive(archive)
assert expected['basic_memory'] == '1.0.0'
backup.upload(archive)
download = Path('/work/download.tar.gz')
with download.open('wb') as stream:
    backup.remote('cat ' + shlex.quote(destination + '/' + archive.name), stdout=stream)
assert backup.file_digest(download) == backup.file_digest(archive)
assert backup.verify_archive(download) == expected
with tarfile.open(download, 'r:gz') as tar:
    for name in expected['sha256']:
        path = target / name
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open('wb') as stream:
            shutil.copyfileobj(tar.extractfile(name), stream)
assert backup.snapshot(target) == expected['sha256']
assert not (target / 'config/memory.db').exists()
shutil.copytree('/data/cache', target / 'cache', symlinks=True)
shutil.copytree('/data/upgrade-evidence', target / 'upgrade-evidence')
for path in [target, *target.rglob('*')]:
    os.chown(path, 1000, 1000, follow_symlinks=False)
print(json.dumps({'nas_round_trip': 'passed', 'restored_files': len(expected['sha256']), 'database_restored': False, 'archive': archive.name}), flush=True)
