// "Huddinge just nu" text, badges and daily figures. Deployed to /openhab/conf/automation/js/huddinge-justnu.js (JS Scripting).
//
// Three rules:
//   live      summary sentence, badges and "el sedan 00:00" on every change of the house meter,
//             the IVT heat pump and the Lynk & Co charging state
//   stats     every 5 min from rrd4j: midnight and 24 h meter readings, compressor and
//             auxiliary heater hours over the last 24 h, highest phase current today
//   prognos   every hour: tomorrow's min/max temperature, rain and gusts for Huddinge from
//             VäderKollen's public SMHI forecast endpoint (no key)
// Read-only towards the devices: only the Huddinge_* items are updated.
const { rules, triggers, items, log, time, actions } = require('openhab');
const logger = log('huddinge');

const FUSE_A = 20; // main fuse per phase, scale for the phase bars on the page
const PERSIST = 'rrd4j';
const FORECAST_URL = 'https://qtowzkwkpirntmaumbfi.supabase.co/functions/v1/smhi-forecast?lat=59.237&lon=17.982';
const ZONE = time.ZoneId.of('Europe/Stockholm');

const METER = 'Currently_One_Currently_Used';
const PHASES = [
  { l: 'L1', i: 'Currently_One_Currently_I1', p: 'Currently_One_Currently_L1' },
  { l: 'L2', i: 'Currently_One_Currently_I2', p: 'Currently_One_Currently_L2' },
  { l: 'L3', i: 'Currently_One_Currently_I3', p: 'Currently_One_Currently_L3' },
];
const SOURCES = [
  'Currently_One_Currently_Using', METER, ...PHASES.map((x) => x.i),
  'Compressor_State_Value_as_Switch', 'Add_Heat_Status_Value_as_Number', 'Heat_carrier_Forward_Value_as_Number',
  'LynkCo_Vehicle_Charging_State', 'LynkCo_Vehicle_Charging_Power',
];

let meterAtMidnight = null; // kWh, refreshed by the stats rule

function exists(name) {
  return items.getItem(name, true) !== null;
}

function num(name) {
  if (!exists(name)) return null;
  const v = items.getItem(name).numericState;
  return (v === null || Number.isNaN(v)) ? null : v;
}

// PersistedState (openhab-js 5) or HistoricItem to a number.
function pnum(s) {
  if (s === null || s === undefined) return null;
  const v = s.numericState !== undefined ? s.numericState : Number.parseFloat(s.state);
  return (v === null || Number.isNaN(v)) ? null : v;
}

function dec(v, decimals = 1) {
  return v.toFixed(decimals).replace('.', ',');
}

function set(name, value) {
  const item = items.getItem(name);
  if (item.state !== value) item.postUpdate(value);
}

function setNum(name, value, unit) {
  const item = items.getItem(name);
  const cur = item.numericState;
  if (cur === null || Number.isNaN(cur) || Math.abs(cur - value) >= 0.01) item.postUpdate(`${value.toFixed(2)} ${unit}`);
}

function live() {
  const using = num('Currently_One_Currently_Using');
  const used = num(METER);
  const fwd = num('Heat_carrier_Forward_Value_as_Number');
  const comp = exists('Compressor_State_Value_as_Switch') ? items.getItem('Compressor_State_Value_as_Switch').state : null;
  const add = num('Add_Heat_Status_Value_as_Number') || 0;
  const carKw = (num('LynkCo_Vehicle_Charging_Power') || 0) / 1000;

  if (used !== null && meterAtMidnight !== null) setNum('Huddinge_El_Idag', Math.max(0, used - meterAtMidnight), 'kWh');

  const parts = [];
  parts.push(using === null ? 'Elmätaren svarar inte just nu.' : `Huset drar ${dec(using / 1000, 1)} kW.`);
  let heat = comp === 'ON' ? 'Värmepumpen går' : 'Värmepumpen vilar';
  if (fwd !== null) heat += `, framledning ${dec(fwd)} °C`;
  heat += add > 0 ? `, tillskott ${Math.round(add)} %.` : ', inget tillskott.';
  parts.push(heat);
  if (carKw > 0.1) parts.push(`Bilen laddar med ${dec(carKw)} kW.`);
  set('Huddinge_JustNu', parts.join(' '));

  const detail = [];
  const idag = num('Huddinge_El_Idag');
  const dygn = num('Huddinge_El_24h');
  if (idag !== null) detail.push(`Hittills idag ${dec(idag)} kWh`);
  if (dygn !== null) detail.push(`senaste dygnet ${dec(dygn)} kWh`);
  // Tomorrow's forecast is shown in the "Utomhus" tile, not repeated here.
  set('Huddinge_JustNu_Detalj', detail.length ? detail.join(', ') + '.' : '');

  if (comp === 'ON' && add > 0) set('Huddinge_Badge_BVP', `Kompressor + tillskott ${Math.round(add)} %|warn`);
  else if (comp === 'ON') set('Huddinge_Badge_BVP', 'Kompressor går|ok');
  else if (add > 0) set('Huddinge_Badge_BVP', `Bara tillskott ${Math.round(add)} %|bad`);
  else set('Huddinge_Badge_BVP', 'Vilar|idle');

  const amps = PHASES.map((x) => num(x.i)).filter((v) => v !== null);
  if (amps.length) {
    const max = Math.max(...amps);
    const tone = max >= FUSE_A ? 'bad' : (max >= 0.8 * FUSE_A ? 'warn' : 'ok');
    set('Huddinge_Badge_El', `Högsta fas ${dec(max)} A|${tone}`);
  }
}

function stats() {
  if (num('Huddinge_Huvudsakring') !== FUSE_A) items.getItem('Huddinge_Huvudsakring').postUpdate(FUSE_A);
  const now = time.toZDT();
  const midnight = now.truncatedTo(time.ChronoUnit.DAYS);
  const dayAgo = now.minusHours(24);

  const meter = items.getItem(METER);
  meterAtMidnight = pnum(meter.persistence.persistedState(midnight, PERSIST));
  const used = num(METER);
  const before = pnum(meter.persistence.persistedState(dayAgo, PERSIST));
  if (used !== null && before !== null) setNum('Huddinge_El_24h', Math.max(0, used - before), 'kWh');

  // rrd4j keeps one sample per minute for the last day, so the share of samples is the share of time.
  const share = (name, on) => {
    if (!exists(name)) return null;
    const states = items.getItem(name).persistence.getAllStatesSince(dayAgo, PERSIST) || [];
    if (!states.length) return null;
    return states.filter(on).length / states.length;
  };
  const comp = share('Compressor_State_Value_as_Switch', (s) => s.state === 'ON');
  if (comp !== null) setNum('Huddinge_Kompressor_24h', comp * 24, 'h');
  const add = share('Add_Heat_Status_Value_as_Number', (s) => (pnum(s) || 0) > 0);
  if (add !== null) setNum('Huddinge_Tillskott_24h', add * 24, 'h');

  let top = null;
  PHASES.forEach((x) => {
    const m = items.getItem(x.i).persistence.maximumSince(midnight, PERSIST);
    const v = pnum(m);
    if (v !== null && (top === null || v > top.v)) top = { v, l: x.l, t: m.timestamp };
  });
  if (top) {
    const hhmm = top.t ? ` kl ${top.t.withZoneSameInstant(ZONE).format(time.DateTimeFormatter.ofPattern('HH:mm'))}` : '';
    set('Huddinge_Toppfas', `${dec(top.v)} A på ${top.l}${hhmm}`);
  }
  live();
}

function prognos() {
  const body = actions.HTTP.sendHttpGetRequest(FORECAST_URL, 20000);
  if (!body) {
    logger.warn('VäderKollen forecast: no response');
    return;
  }
  const tomorrow = time.toZDT().withZoneSameInstant(ZONE).toLocalDate().plusDays(1).toString();
  const hrs = (JSON.parse(body).timeSeries || [])
    .filter((h) => time.ZonedDateTime.parse(h.time).withZoneSameInstant(ZONE).toLocalDate().toString() === tomorrow);
  if (hrs.length < 12) return; // forecast does not cover tomorrow yet
  const temps = hrs.map((h) => h.temp);
  const rain = hrs.reduce((sum, h) => sum + (h.precip || 0), 0);
  const gust = Math.max(...hrs.map((h) => h.windGust || 0));
  let text = `Imorgon ${Math.round(Math.min(...temps))}–${Math.round(Math.max(...temps))} °C`;
  text += rain >= 0.5 ? `, nederbörd ${dec(rain)} mm` : ', uppehåll';
  if (gust >= 14) text += `, byar ${Math.round(gust)} m/s`;
  set('Huddinge_Prognos_Imorgon', text);
  live();
}

function safely(name, fn) {
  return () => {
    try {
      fn();
    } catch (e) {
      logger.warn(`${name} failed: ${e}`);
    }
  };
}

rules.JSRule({
  name: 'Huddinge just nu: text och badges',
  description: 'Bygger sammanfattningen och badgarna för sidan Huddinge just nu',
  triggers: SOURCES.filter(exists).map((name) => triggers.ItemStateChangeTrigger(name)),
  execute: safely('live', live),
  tags: ['huddinge'],
  id: 'huddinge-justnu',
});

rules.JSRule({
  name: 'Huddinge just nu: dygnssiffror',
  description: 'El idag/senaste dygnet, kompressor- och tillskottstimmar, högsta fasström (rrd4j)',
  triggers: [triggers.SystemStartlevelTrigger(100), triggers.GenericCronTrigger('0 */5 * * * ?')],
  execute: safely('stats', stats),
  tags: ['huddinge'],
  id: 'huddinge-justnu-stats',
});

rules.JSRule({
  name: 'Huddinge just nu: prognos från VäderKollen',
  description: 'Morgondagens min/max, nederbörd och byar för Huddinge (VäderKollen, SMHI)',
  triggers: [triggers.SystemStartlevelTrigger(100), triggers.GenericCronTrigger('0 7 * * * ?')],
  execute: safely('prognos', prognos),
  tags: ['huddinge'],
  id: 'huddinge-justnu-prognos',
});
