import fs from 'node:fs';
const source = fs.readFileSync(new URL('./k3s-format-report.js', import.meta.url), 'utf8');
const path = new URL('./k3s-workflow.json', import.meta.url);
const workflow = JSON.parse(fs.readFileSync(path, 'utf8'));
const node = workflow.nodes.find(node => node.name === 'Format data');
if (process.argv.includes('--check')) {
  if (node.parameters.jsCode !== source) throw new Error('Run node n8n-workflows/sync-k3s-report.mjs');
} else {
  node.parameters.jsCode = source;
  fs.writeFileSync(path, JSON.stringify(workflow, null, 2) + '\n');
}
