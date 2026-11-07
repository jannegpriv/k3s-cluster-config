"""Private loopback acceptance client. Run inside the isolated validation pod."""
import http.client
import json
import hashlib
from pathlib import Path
import sqlite3
import sys
import time


class Client:
    def __init__(self):
        self.sequence = 0
        self.headers = {'Content-Type': 'application/json', 'Accept': 'application/json, text/event-stream'}
        result = self.request('initialize', {'protocolVersion': '2025-03-26', 'capabilities': {}, 'clientInfo': {'name': 'basic-memory-upgrade-validation', 'version': '1'}})
        self.headers['MCP-Protocol-Version'] = result['protocolVersion']
        self.request('notifications/initialized', notification=True)

    def request(self, method, params=None, notification=False):
        self.sequence += 1
        payload = {'jsonrpc': '2.0', 'method': method}
        if not notification:
            payload['id'] = self.sequence
        if params is not None:
            payload['params'] = params
        conn = http.client.HTTPConnection('127.0.0.1', 8000, timeout=120)
        try:
            conn.request('POST', '/mcp', json.dumps(payload).encode(), self.headers)
            response = conn.getresponse()
            session = response.getheader('Mcp-Session-Id')
            if session:
                self.headers['Mcp-Session-Id'] = session
            body = response.read().decode()
            if response.status not in (200, 202):
                raise RuntimeError('HTTP ' + str(response.status))
            if notification:
                return None
            if response.getheader('Content-Type', '').startswith('text/event-stream'):
                messages = [json.loads(line[5:].strip()) for line in body.splitlines() if line.startswith('data:')]
                result = next(item for item in messages if item.get('id') == self.sequence)
            else:
                result = json.loads(body)
            if 'error' in result:
                raise RuntimeError(result['error'])
            return result['result']
        finally:
            conn.close()

    def call(self, name, **arguments):
        result = self.request('tools/call', {'name': name, 'arguments': arguments})
        if result.get('isError'):
            raise RuntimeError(result)
        return result


def unpack(result):
    data = result.get('structuredContent')
    if data is None:
        data = json.loads(result['content'][0]['text'])
    return data.get('result', data) if isinstance(data, dict) else data


def validate(client=None):
    client = client or Client()
    tools = client.request('tools/list')['tools']
    names = {tool['name'] for tool in tools}
    assert {'bm_read', 'bm_write', 'bm_edit', 'bm_delete', 'bm_search', 'bm_project', 'bm_list'} <= names
    assert all(name.startswith('bm_') for name in names)
    def call(name, **args):
        return unpack(client.call(name, project='main', output_format='json', **args))
    for mode, query in [('text', 'vatten'), ('semantic', 'stänga av vattnet på landet'), ('hybrid', 'stänga av vattnet på landet')]:
        result = call('bm_search', query=query, mode=mode, compact=True, page_size=5)
        assert result['results'], mode
        assert any('vatten' in row['title'].lower() or 'brunn' in row['title'].lower() for row in result['results']), mode
        print(json.dumps({'search_mode': mode, 'results': len(result['results']), 'relevant_match': True}), flush=True)
    default = call('bm_search', query='stänga av vattnet på landet', compact=True, page_size=5)
    hybrid = call('bm_search', query='stänga av vattnet på landet', mode='hybrid', compact=True, page_size=5)
    assert default['results'] == hybrid['results'], 'Default search differs from hybrid'
    recent = call('bm_project', command='recent', since='7d', page_size=5)
    call('bm_list', path='/projects', page_size=5)
    call('bm_read', identifier='memory://profile/konventioner-for-ai-minnet', include_content=False)
    identifier = 'validation/upgrade-20261106.md'
    # Search before creating the one synthetic note owned by this test.
    existing = call('bm_search', query='bmupgrade20261106probe', mode='text', compact=True)
    assert not existing['results'], 'Test note already exists; do not overwrite'
    call('bm_write', identifier=identifier, title='Tillfälligt uppgraderingstest 2026-11-06', content='# Uppgraderingstest\n\nbmupgrade20261106probe original.\n', tags=['validation'])
    note = call('bm_read', identifier=identifier)
    assert 'bmupgrade20261106probe original' in json.dumps(note)
    checksum = note['checksum']
    call('bm_edit', identifier=identifier, command='find_replace', find_text='original', content='uppdaterad', expected_checksum=checksum)
    stale = client.request('tools/call', {'name': 'bm_edit', 'arguments': {'project': 'main', 'identifier': identifier, 'command': 'append', 'content': 'MUST NOT APPEAR', 'expected_checksum': checksum}})
    assert stale.get('isError') and 'REVISION_CONFLICT' in json.dumps(stale), 'Stale edit was not rejected'
    note = call('bm_read', identifier=identifier)
    assert 'uppdaterad' in json.dumps(note) and 'MUST NOT APPEAR' not in json.dumps(note)
    assert call('bm_search', query='bmupgrade20261106probe', mode='text', compact=True)['results']
    call('bm_delete', identifier=identifier, expected_checksum=note['checksum'])
    deleted = client.request('tools/call', {'name': 'bm_read', 'arguments': {'project': 'main', 'identifier': identifier}})
    assert deleted.get('isError') and 'NOT_FOUND' in json.dumps(deleted)
    print(json.dumps({'crud': 'passed', 'revision_guard': 'passed', 'default_hybrid': True, 'recent_and_list': 'passed', 'tool_count': len(names)}), flush=True)


def verify_copy(restored=False):
    root = Path('/data/memory')
    expected = json.loads(Path('/data/upgrade-evidence/source-manifest.json').read_text())
    for attempt in range(20):
        actual = {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(root.rglob('*')) if p.is_file()}
        if actual == expected['files']:
            break
        time.sleep(1)
    assert actual == expected['files'], 'Original files changed or test file was not removed'
    with sqlite3.connect('file:/data/config/memory.db?mode=ro', uri=True) as db:
        assert db.execute('PRAGMA integrity_check').fetchone()[0] == 'ok'
        counts = {table: db.execute('SELECT count(*) FROM ' + table).fetchone()[0] for table in expected['counts']}
        if restored:
            import frontmatter
            from basic_memory.markdown.entity_parser import parse
            expected_relations = set()
            for path in root.rglob('*.md'):
                for relation in parse(frontmatter.loads(path.read_text()).content).relations:
                    expected_relations.add((str(path.relative_to(root)), relation.type, relation.target, relation.context))
            actual_relations = set(db.execute('SELECT e.file_path,r.relation_type,r.to_name,r.context FROM relation r JOIN entity e ON e.id=r.from_id').fetchall())
            assert actual_relations == expected_relations, 'Rebuilt graph does not match authored Markdown'
            assert counts['entity'] == expected['counts']['entity']
            assert counts['observation'] == expected['counts']['observation']
            print(json.dumps({'restored_relations_match_parser': len(expected_relations)}), flush=True)
        else:
            assert counts == expected['counts'], 'Migrated graph counts differ'
        pending = db.execute("SELECT count(*) FROM note_content WHERE file_write_status != 'synced' OR file_version IS NULL OR file_version != db_version").fetchone()[0]
        assert pending == 0
    print(json.dumps({'original_files_unchanged': len(actual), 'graph_counts': counts, 'sqlite_integrity': 'ok', 'pending_writes': 0}), flush=True)


if __name__ == '__main__':
    if '--graph-only' not in sys.argv:
        validate()
    verify_copy(restored='--restored' in sys.argv)
