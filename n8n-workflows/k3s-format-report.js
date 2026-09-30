// Source for the K3s workflow's "Format data" Code node.
// Run node n8n-workflows/sync-k3s-report.mjs after editing.
const now = Date.now();
const DAY = 86400000;
const EVENT_MAX_AGE = DAY; // The report runs daily. Repeated events refresh their last-seen time.
const levels = { OK: 0, OKÄNT: 1, VARNING: 2, 'HÖG PRIORITET': 3, KRITISKT: 4 };

function timestamp(value) {
  if (typeof value !== 'string') return null;
  const parts = /^(\d{4})-(\d{2})-(\d{2})T/.exec(value);
  const parsed = Date.parse(value);
  if (!parts || !Number.isFinite(parsed)) return null;
  // Date.parse normalizes impossible dates such as February 30 in some runtimes.
  const calendar = new Date(Date.UTC(+parts[1], +parts[2] - 1, +parts[3]));
  if (calendar.toISOString().slice(0, 10) !== value.slice(0, 10)) return null;
  return parsed;
}

function lastSeen(event) {
  const candidates = [event.series?.lastObservedTime, event.lastTimestamp,
    event.deprecatedLastTimestamp, event.eventTime].map(timestamp).filter(v => v !== null);
  // Creation time alone cannot tell whether an old, repeating event is still occurring.
  return candidates.length ? Math.max(...candidates) : null;
}

function freshness(seen) {
  if (seen === null || seen > now + 5 * 60000) return 'unknown';
  return now - seen > EVENT_MAX_AGE ? 'historical' : 'current';
}

function expiryDates(message) {
  const dates = [];
  const pattern = /\b(?:will expire|expires?|expired|notAfter)\b[^;\n]*?(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2}))/gi;
  for (const match of message.matchAll(pattern)) {
    const value = timestamp(match[1]);
    if (value !== null && !dates.includes(value)) dates.push(value);
  }
  return dates.sort((a, b) => a - b);
}

function expiryLevel(expires) {
  const remaining = expires - now;
  if (remaining <= 7 * DAY) return 'KRITISKT';
  if (remaining <= 30 * DAY) return 'HÖG PRIORITET';
  if (remaining <= 120 * DAY) return 'VARNING';
  return 'OK';
}

function dateLabel(value) {
  return new Intl.DateTimeFormat('sv-SE', {
    timeZone: 'Europe/Stockholm', year: 'numeric', month: '2-digit', day: '2-digit',
    hour: '2-digit', minute: '2-digit', hourCycle: 'h23',
  }).format(new Date(value)) + ' (Europe/Stockholm)';
}

const cpuData = $('Get K3s CPU usage').first().json;
const memoryData = $('Get K3s memory usage').first().json;
const alertsItems = $('Get K3s active alerts').all().map(item => item.json);
const alerts = alertsItems.flatMap(item => Array.isArray(item) ? item : [item]);
const eventsResponse = $('Get K3s Events').first().json;

function metrics(label, data) {
  const results = data?.data?.result;
  if (!Array.isArray(results)) return label + ':\n- Data unavailable\n';
  return label + ':\n' + results.map(node =>
    '- ' + (node.metric?.instance || 'unknown').split(':')[0] + ': ' +
    Number.parseFloat(node.value?.[1]).toFixed(1) + '%').join('\n') + '\n';
}

const validAlerts = alerts.filter(alert => alert?.labels?.alertname);
const alertsInfo = 'Active alerts:\n' + (validAlerts.length
  ? validAlerts.map(alert => '- [' + (alert.labels.severity || 'unknown').toUpperCase() + '] ' +
    alert.labels.alertname + ' (' + (alert.status?.state || 'unknown') + ')').join('\n')
  : alerts.every(alert => alert && typeof alert === 'object' && Object.keys(alert).length === 0)
    ? '- No active alerts'
    : '- Alert data unavailable or unexpected; do not assume there are no alerts') + '\n';

const eventsAvailable = Array.isArray(eventsResponse?.items);
const findings = [];
const otherEvents = [];
const certificateError = /\bx509:\s*certificate (?:has expired|is not yet valid|signed by unknown authority)|\bcertificate has expired\b|\bcertificate is not yet valid\b|\btls:\s*(?:bad certificate|failed to verify certificate)|\bcertificate verify failed\b/i;

for (const event of eventsAvailable ? eventsResponse.items : []) {
  if (event.type === 'Normal') continue;
  const message = String(event.message ?? event.note ?? '');
  const reason = event.reason || 'Unknown';
  const seen = lastSeen(event);
  const age = freshness(seen);
  const actualError = certificateError.test(message) || /^(CertificateExpired|CertificateError|CertificateValidationFailed|TLSCertificateError)$/i.test(reason);
  const isCertificate = reason === 'CertificateExpirationWarning' || actualError;
  if (!isCertificate) {
    if (age === 'current') otherEvents.push({ event, seen, message });
    continue;
  }
  const object = event.involvedObject || event.regarding || {};
  const node = object.kind === 'Node' ? object.name :
    event.source?.host || event.reportingInstance || 'okänd';
  const expires = expiryDates(message);
  for (const expiry of expires.length ? expires : [null]) {
    const severity = age !== 'current' ? 'OKÄNT' : actualError ? 'KRITISKT' :
      expiry === null ? 'VARNING' : expiryLevel(expiry);
    findings.push({ node, object: (object.kind || 'Unknown') + '/' + (object.name || 'unknown'),
      namespace: event.metadata?.namespace || object.namespace || 'unknown', reason,
      message, lastSeen: seen === null ? null : new Date(seen).toISOString(), freshness: age,
      expiresAt: expiry === null ? null : new Date(expiry).toISOString(),
      remainingDays: expiry === null ? null : Math.ceil((expiry - now) / DAY),
      severity, actualError });
  }
}

// Keep certificate findings outside the AI response so dates and severity cannot be rewritten.
// Group only equivalent findings; retain complete event messages in certificateFindings.
const unique = new Map();
for (const finding of findings) {
  const key = JSON.stringify([finding.node, finding.object, finding.expiresAt,
    finding.freshness, finding.severity, finding.actualError]);
  const previous = unique.get(key);
  if (!previous || (finding.lastSeen || '') > (previous.lastSeen || '')) unique.set(key, finding);
}
const summaries = [...unique.values()].sort((a, b) => levels[b.severity] - levels[a.severity] ||
  a.node.localeCompare(b.node) || (a.expiresAt || '').localeCompare(b.expiresAt || ''));
const overall = !eventsAvailable ? 'OKÄNT' : summaries.length
  ? summaries.reduce((level, item) => levels[item.severity] > levels[level] ? item.severity : level, 'OK')
  : 'INGA AKTUELLA VARNINGAR I EVENTUNDERLAGET';
const lines = summaries.map(item => {
  const expiry = item.expiresAt === null ? 'utgångsdatum saknas — kontrollera certifikatet' :
    'utgång ' + dateLabel(Date.parse(item.expiresAt)) + ', ' +
    (Date.parse(item.expiresAt) <= now ? 'utgånget enligt eventets datum' : item.remainingDays + ' dagar kvar');
  const status = item.freshness === 'historical' ? 'HISTORISKT — inte ett aktuellt larm' :
    item.freshness === 'unknown' ? 'AKTUALITET OKÄND — kontrollera aktuell status' : item.severity;
  const evidence = item.lastSeen ? '; senast observerat ' + dateLabel(Date.parse(item.lastSeen)) : '; observationstid saknas';
  return '- **' + item.node + ': ' + status + '** — ' + expiry +
    (item.actualError ? '; certifikatfel rapporterat (' + item.reason + ')' : '') + evidence + '.';
});
let certificateReport = '**Certifikat: ' + overall + '**\n' + lines.join('\n');
if (!eventsAvailable) certificateReport += '\nKubernetes-events kunde inte läsas; certifikatstatus är okänd.';
else if (!summaries.length) certificateReport += '\nInga certifikatvarningar i det hämtade eventunderlaget. Detta bekräftar inte att tidigare problem är lösta.';
else if (overall === 'KRITISKT') certificateReport += '\nÅtgärd: kontrollera och åtgärda det aktuella certifikatproblemet omgående.';
else if (overall === 'HÖG PRIORITET') certificateReport += '\nÅtgärd: prioritera certifikatförnyelse snarast och före utgångsdatum.';
else if (overall === 'VARNING') certificateReport += '\nÅtgärd: verifiera certifikatstatus och planera förnyelse före utgångsdatum.';
if (summaries.some(item => item.expiresAt === null)) certificateReport += '\nUtgångsdatum saknas för minst ett certifikat och behöver kontrolleras direkt på berörd nod.';
if (summaries.some(item => item.freshness !== 'current')) certificateReport += '\nHistoriska events och events utan tillförlitlig observationstid bevisar varken ett aktuellt fel eller att felet är löst.';

const eventsInfo = 'Recent Kubernetes Events (non-certificate, last 24h):\n' +
  (otherEvents.sort((a, b) => b.seen - a.seen).slice(0, 10).map(({ event, message }) =>
    '- [' + (event.metadata?.namespace || 'unknown') + '] ' + event.reason + ': ' + message).join('\n') ||
    (eventsAvailable ? '- No recent non-certificate events in the retrieved data' : '- Event data unavailable'));
const report = 'K3s Cluster Status Report\n' + metrics('CPU usage per node', cpuData) + '\n' +
  metrics('Memory usage per node', memoryData) + '\n' + alertsInfo + '\n' + eventsInfo;
return [{ json: { report, certificateReport, certificateFindings: findings,
  certificateSeverity: overall, generatedAt: new Date(now).toISOString() } }];
