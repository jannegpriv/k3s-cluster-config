"""Authorized one-time 1.0 instruction migration; checksum guarded, read back with another client."""
import importlib.util
import json
from pathlib import Path

spec = importlib.util.spec_from_file_location('mcp_client', Path(__file__).with_name('mcp-client.py'))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def unpack(result):
    data = result.get('structuredContent')
    if data is None:
        data = json.loads(result['content'][0]['text'])
    return data.get('result', data) if isinstance(data, dict) else data


def migrate(content):
    lines = []
    for line in content.splitlines():
        if line.startswith('1. Hämta en kort aktivitetslista med `recent_activity`'):
            line = '1. Hämta en kort aktivitetslista med `bm_project(command="recent", project="main", since="7d", page_size=5, output_format="text")`. Hämta inte automatiskt fler sidor.'
        elif line.startswith('2. Läs denna konventionsnote en gång vid sessionsstart'):
            line = '2. Läs denna konventionsnote med `bm_read(identifier="memory://profile/konventioner-for-ai-minnet", project="main")` en gång vid sessionsstart och följ den.'
        elif line.startswith('3. Kör `search_notes`'):
            line = '3. Kör `bm_search(project="main", mode="hybrid", compact=true)` på uppgiftens ämne innan du svarar ur minnet eller skriver. Hybrid kombinerar textsökning och betydelsebaserad sökning; naturliga svenska frågor fungerar. Använd `mode="text"` för exakt textsökning, citerade fraser och AND/OR/NOT, och `filters` för metadata, exempelvis `filters={"tags": ["bekraftat"]}`. Läs sedan bara relevanta anteckningar med `bm_read`; ladda inte hela minnet. Hämta fler sökträffar först när uppgiften kräver det.'
        line = line.replace('`recent_activity`', '`bm_project(command="recent", project="main")`')
        line = line.replace('`search_notes`', '`bm_search(project="main", mode="hybrid", compact=true)`')
        line = line.replace('`list_directory("/projects")`', '`bm_list(path="/projects", project="main")`')
        lines.append(line)
    updated = '\n'.join(lines) + '\n'
    validation = {'verified_at': '2026-11-06', 'verification_method': 'MCP CRUD, revision conflict, hybrid search and NAS restore on isolated copies', 'version': '1.0.0'}
    assert updated.startswith('---\n')
    updated = '---\ntooling_validation: ' + json.dumps(validation) + '\n' + updated[4:]
    assert not any(old in updated for old in ('`recent_activity`', '`search_notes`', '`list_directory('))
    updated += '\n## Verktyg i Basic Memory 1.0\n\nVerifierat 2026-11-06 genom MCP-test på isolerad kopia och återställning från NAS. Ange alltid `project="main"` för projektbundna verktyg. Använd `bm_edit` med `command` för ändringar av befintliga anteckningar och `bm_write` för nya. Läs aktuell revision med `bm_read` och skicka `expected_checksum` vid ändring; vid `REVISION_CONFLICT`, läs om och bedöm ändringen på nytt. Läs tillbaka för att verifiera sparandet. Dessa tekniska kontroller ändrar inte kravet på Jannes tillstånd att skriva.\n'
    return updated


if __name__ == '__main__':
    client = module.Client('codex')
    identifier = 'memory://profile/konventioner-for-ai-minnet'
    found = unpack(client.call('bm_search', project='main', query='Konventioner för AI-minnet', mode='title', compact=True, page_size=5, output_format='json'))
    assert any(row.get('permalink') == 'main/profile/konventioner-for-ai-minnet' for row in found['results'])
    note = unpack(client.call('bm_read', project='main', identifier=identifier, output_format='json'))
    assert '## Verktyg i Basic Memory 1.0' not in note['content'], 'Migration already applied'
    updated = migrate(note['content'])
    assert updated.startswith('---\n') and updated != note['content']
    client.call('bm_write', project='main', identifier=note['file_path'], content=updated, expected_checksum=note['checksum'], overwrite=True)
    other = module.Client('agent')
    readback = unpack(other.call('bm_read', project='main', identifier=identifier, output_format='json'))
    # Basic Memory canonicalizes YAML; compare the body and parsed metadata separately.
    assert readback['content'].split('---', 2)[2] == updated.split('---', 2)[2]
    actual_metadata = dict(readback['frontmatter'])
    assert actual_metadata.pop('tooling_validation')['version'] == '1.0.0'
    assert actual_metadata == note['frontmatter'], 'Existing frontmatter changed'
    print(json.dumps({'conventions_updated': True, 'readback_account': 'agent', 'frontmatter_preserved': True, 'checksum': readback['checksum']}))
