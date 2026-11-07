"""Build the reviewed, version-locked SQLite indexing overlay for BM 1.0.0.

The local project indexer hardcodes eight concurrent database writers, bypassing
the index_*_max_concurrent settings. Large search projections can hold SQLite's
single writer longer than busy_timeout. Serialize local index batches instead.
The immutable upstream image remains intact; an init container writes this one
module to an emptyDir mounted read-only over the runtime module. A changed source
hash refuses startup so a future image upgrade must explicitly retire/review it.
"""
import hashlib
from pathlib import Path
import sys

SOURCE = Path('/app/src/basic_memory/index/local_project.py')
SOURCE_SHA256 = '568d7a1c3a1398658234f6fbe71de5bae4897387f07a73c627a673a1412ad3f1'
ORIGINAL = '    index_max_concurrent: int = 8\n'
REPLACEMENT = '    index_max_concurrent: int = 1  # Local SQLite compatibility fix\n'


def patched_source(source):
    if hashlib.sha256(source).hexdigest() != SOURCE_SHA256:
        raise RuntimeError('BM source changed: review or remove the SQLite compatibility overlay')
    text = source.decode('utf-8')
    if text.count(ORIGINAL) != 2:
        raise RuntimeError('Unexpected local indexing declarations')
    result = text.replace(ORIGINAL, REPLACEMENT)
    compile(result, str(SOURCE), 'exec')
    return result


if __name__ == '__main__':
    destination = Path(sys.argv[1])
    destination.write_text(patched_source(SOURCE.read_bytes()), encoding='utf-8')
    print('BM 1.0.0 SQLite index overlay verified: local database batch concurrency=1')
