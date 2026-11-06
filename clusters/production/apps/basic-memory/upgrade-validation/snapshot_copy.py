"""Copy a stable production snapshot to an empty, separate validation PVC."""
import hashlib
import json
from pathlib import Path
import shutil
import sqlite3

source = Path('/source')
target = Path('/data')
if any(p.name != 'lost+found' for p in target.iterdir()):
    raise RuntimeError('Validation target is not empty; refusing to overwrite it')

def files(root):
    return {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in sorted(root.rglob('*')) if p.is_file()}

def state(db):
    pending = db.execute("SELECT count(*) FROM note_content WHERE file_write_status != 'synced' OR file_version IS NULL OR file_version != db_version").fetchone()[0]
    vacated = db.execute('SELECT count(*) FROM note_file_vacate').fetchone()[0]
    if pending or vacated:
        raise RuntimeError('Source has unsettled writes; retry only after they settle')
    return db.execute('SELECT entity_id, db_version, file_checksum FROM note_content ORDER BY entity_id').fetchall()

with sqlite3.connect('file:/source/config/memory.db?mode=ro', uri=True) as db:
    before_state = state(db)
    before_files = files(source / 'memory')
    config_before = (source / 'config/config.json').read_bytes()
    (target / 'config').mkdir()
    with sqlite3.connect(target / 'config/memory.db') as out:
        db.backup(out)
    shutil.copytree(source / 'memory', target / 'memory', symlinks=True)
    (target / 'config/config.json').write_bytes(config_before)
    if before_state != state(db) or before_files != files(source / 'memory'):
        raise RuntimeError('Production changed during copying; target must not be used')
    if config_before != (source / 'config/config.json').read_bytes():
        raise RuntimeError('Source configuration changed during copying')
    if before_files != files(target / 'memory'):
        raise RuntimeError('Copied note hashes do not match')
    counts = {t: db.execute('SELECT count(*) FROM ' + t).fetchone()[0]
              for t in ['entity', 'observation', 'relation']}

if (source / 'cache').exists():
    shutil.copytree(source / 'cache', target / 'cache', symlinks=True)
evidence = target / 'upgrade-evidence'
evidence.mkdir()
(evidence / 'source-manifest.json').write_text(json.dumps({'files': before_files, 'counts': counts}, ensure_ascii=False))
print(json.dumps({'copy_verified': True, 'project_files': len(before_files), 'counts': counts}), flush=True)
