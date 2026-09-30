import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

const workflow = JSON.parse(fs.readFileSync(new URL('../k3s-workflow.json', import.meta.url)));
const code = workflow.nodes.find(node => node.name === 'Format data').parameters.jsCode;
const now = Date.parse('2026-09-30T08:00:00Z');
const DAY = 86400000;
class Clock extends Date { static now() { return now; } }
const iso = offset => new Date(now + offset).toISOString();
function event(offset = 102 * DAY, extra = {}) {
  return { type: 'Warning', reason: 'CertificateExpirationWarning',
    involvedObject: { kind: 'Node', name: 'k3s-m-1' }, metadata: { namespace: 'default' },
    lastTimestamp: iso(-60000), message: 'Node certificates require attention - restart k3s on this node to trigger automatic rotation: ' +
      'admin/client-admin.crt: certificate CN=system:admin,O=system:masters will expire within 120 days at ' + iso(offset), ...extra };
}
function run(items, options = {}) {
  const inputs = {
    'Get K3s CPU usage': [{ json: { data: { result: [] } } }],
    'Get K3s memory usage': [{ json: { data: { result: [] } } }],
    'Get K3s active alerts': options.alerts || [{ json: [] }],
    'Get K3s Events': [{ json: options.response ?? { items } }],
  };
  const value = vm.runInNewContext('(function(){' + code + '\n})()', {
    Date: Clock, Intl, $: name => ({ first: () => inputs[name][0], all: () => inputs[name] }),
  }, { timeout: 1000 });
  return JSON.parse(JSON.stringify(value[0].json));
}

test('embedded Code node matches the maintained source', () => {
  assert.equal(code, fs.readFileSync(new URL('../k3s-format-report.js', import.meta.url), 'utf8'));
});

for (const [offset, expected] of [
  [120 * DAY + 1000, 'OK'], [120 * DAY, 'VARNING'], [102 * DAY, 'VARNING'],
  [30 * DAY + 1000, 'VARNING'], [30 * DAY, 'HÖG PRIORITET'],
  [7 * DAY + 1000, 'HÖG PRIORITET'], [7 * DAY, 'KRITISKT'],
  [1000, 'KRITISKT'], [0, 'KRITISKT'], [-DAY, 'KRITISKT'],
]) test('exact expiry boundary ' + offset + ' ms => ' + expected, () => {
  assert.equal(run([event(offset)]).certificateSeverity, expected);
});

test('long K3s message retains node, complete original, date, and remaining days', () => {
  const input = event();
  const result = run([input]);
  assert.equal(result.certificateFindings[0].message, input.message);
  assert.equal(result.certificateFindings[0].expiresAt, '2027-01-10T08:00:00.000Z');
  assert.equal(result.certificateFindings[0].remainingDays, 102);
  assert.match(result.certificateReport, /k3s-m-1: VARNING/);
  assert.match(result.certificateReport, /2027-01-10 09:00.*102 dagar kvar/);
  assert.doesNotMatch(result.certificateReport, /KRITISKT|omgående/);
  assert.doesNotMatch(result.report, /CertificateExpirationWarning|restart k3s/);
});

test('all distinct expirations are retained and the nearest controls severity', () => {
  const result = run([event(102 * DAY, { message: event().message + ', kubelet/client-kubelet.crt: certificate will expire within 120 days at ' + iso(3 * DAY) })]);
  assert.equal(result.certificateFindings.length, 2);
  assert.equal(result.certificateSeverity, 'KRITISKT');
  assert.match(result.certificateReport, /2027-01-10/);
  assert.match(result.certificateReport, /2026-10-03/);
});

for (const message of ['certificate expiration warning, date unavailable',
  'certificate will expire at 2027-02-30T08:00:00Z',
  'certificate will expire at 2027-99-01T08:00:00Z']) {
  test('missing or invalid expiry is a warning, not a guessed critical date: ' + message, () => {
    const result = run([event(DAY, { message })]);
    assert.equal(result.certificateSeverity, 'VARNING');
    assert.equal(result.certificateFindings[0].expiresAt, null);
    assert.match(result.certificateReport, /utgångsdatum saknas/);
  });
}

test('certificate events beyond the ten other-event limit are still included', () => {
  const input = Array.from({ length: 20 }, (_, i) => event(DAY, { reason: 'Unhealthy', message: 'probe ' + i }));
  input.push(event());
  assert.equal(run(input).certificateFindings.length, 1);
});

test('old expiry warning cannot produce a current critical alarm', () => {
  const result = run([event(-DAY, { lastTimestamp: iso(-2 * DAY) })]);
  assert.equal(result.certificateSeverity, 'OKÄNT');
  assert.match(result.certificateReport, /HISTORISKT/);
  assert.doesNotMatch(result.certificateReport, /KRITISKT|omgående/);
});

test('repeating old event uses last observation, not creation time', () => {
  const result = run([event(3 * DAY, { lastTimestamp: iso(-10 * DAY),
    series: { lastObservedTime: iso(-60000) }, metadata: { creationTimestamp: iso(-20 * DAY) } })]);
  assert.equal(result.certificateSeverity, 'KRITISKT');
});

for (const [offset, freshness] of [[-DAY, 'current'], [-DAY - 1, 'historical'], [6 * 60000, 'unknown']]) {
  test('observation age boundary ' + offset, () => {
    assert.equal(run([event(DAY, { lastTimestamp: iso(offset) })]).certificateFindings[0].freshness, freshness);
  });
}

test('missing observation time remains unknown, even with a creation timestamp', () => {
  const result = run([event(-DAY, { lastTimestamp: null, metadata: { creationTimestamp: iso(-1000) } })]);
  assert.equal(result.certificateSeverity, 'OKÄNT');
  assert.match(result.certificateReport, /AKTUALITET OKÄND/);
});

test('events.k8s.io API fields note, regarding, eventTime work', () => {
  const input = event();
  const result = run([{ type: input.type, reason: input.reason, note: input.message,
    regarding: input.involvedObject, eventTime: input.lastTimestamp }]);
  assert.equal(result.certificateFindings[0].node, 'k3s-m-1');
  assert.equal(result.certificateSeverity, 'VARNING');
});

for (const message of ['x509: certificate has expired or is not yet valid',
  'x509: certificate signed by unknown authority', 'remote error: tls: bad certificate',
  'tls: failed to verify certificate: error']) {
  test('fresh actual certificate error is critical: ' + message, () => {
    assert.equal(run([event(102 * DAY, { reason: 'Failed', message })]).certificateSeverity, 'KRITISKT');
  });
}

test('old actual TLS error does not cause a current critical alarm', () => {
  assert.equal(run([event(DAY, { reason: 'Failed', message: 'x509: certificate has expired',
    lastTimestamp: iso(-2 * DAY) })]).certificateSeverity, 'OKÄNT');
});

test('ordinary TLS handshake timeout is not invented into a certificate error', () => {
  const result = run([event(DAY, { reason: 'Failed', message: 'TLS handshake timeout' })]);
  assert.equal(result.certificateFindings.length, 0);
  assert.match(result.report, /TLS handshake timeout/);
});

test('Normal events are not treated as failures', () => {
  assert.equal(run([event(DAY, { type: 'Normal' })]).certificateFindings.length, 0);
});

test('missing event data is unknown; empty data does not claim resolution', () => {
  assert.equal(run([], { response: { error: 'forbidden' } }).certificateSeverity, 'OKÄNT');
  assert.match(run([]).certificateReport, /bekräftar inte att tidigare problem är lösta/);
});

test('duplicate events have one displayed line and retain full evidence', () => {
  const result = run([event(), event(102 * DAY, { lastTimestamp: iso(-1000) })]);
  assert.equal(result.certificateFindings.length, 2);
  assert.equal((result.certificateReport.match(/k3s-m-1:/g) || []).length, 1);
});

test('all n8n alert items are included; unexpected response is not healthy', () => {
  const result = run([], { alerts: ['one', 'two'].map(alertname => ({ json: { labels: { alertname } } })) });
  assert.match(result.report, /one/); assert.match(result.report, /two/);
  assert.match(run([], { alerts: [{ json: { error: 'failed' } }] }).report, /Alert data unavailable/);
});

test('rendered Mattermost text appends the deterministic certificate block', () => {
  const expression = workflow.nodes.find(node => node.name === 'Result to k3s-cluster')
    .parameters.bodyParameters.parameters.find(parameter => parameter.name === 'text').value;
  const result = run([event()]);
  const text = vm.runInNewContext(expression.slice(3, -2), {
    $json: { output: 'CPU och minne är stabila.' },
    $: () => ({ first: () => ({ json: result }) }),
  });
  assert.ok(text.endsWith(result.certificateReport));
  assert.match(text, /\n\n\*\*Certifikat: VARNING/);
  assert.equal(workflow.connections['Simple Memory'], undefined);
});
