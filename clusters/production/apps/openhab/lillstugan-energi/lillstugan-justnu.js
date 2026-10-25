// "Lillstugan just nu" text and badges. Deployed to /openhab/conf/automation/js/lillstugan-justnu.js (JS Scripting).
//
// Builds the plain-Swedish summary ("Huset drar 1,7 kW. Batteriet levererar ...") and the
// card badges for the Lillstugan page from the SigenStor items. Runs unchanged in both
// openHABs: Huddinge (items mirrored from Landet) and Landet (openhab3, native items);
// items that do not exist in an instance (the Lynk & Co on Landet) are skipped.
// Sign conventions (checked against 48 h of history, load = grid + pv - battery):
//   SigenStor_Battery_Power > 0 charging, < 0 discharging
//   SigenStor_Grid_Power    > 0 import,   < 0 export
// A second rule computes "förbrukning igår" and "senaste dygnet" every 5 min from rrd4j deltas
// of the cumulative SigenStor_Total_Load meter.
// Read-only towards SigenStor: only the Lillstugan_* items are updated.
const { rules, triggers, items, log, time } = require('openhab');
const logger = log('lillstugan');

const IDLE_KW = 0.05;
const SOURCES = [
  'SigenStor_PV_Power', 'SigenStor_Load_Power', 'SigenStor_Battery_Power', 'SigenStor_Grid_Power',
  'SigenStor_Battery_SOC', 'SigenStor_Avail_Discharge_Cap', 'SigenStor_Avail_Charge_Cap',
  'SigenStor_OnOff_Grid', 'SigenStor_EVAC_State', 'SigenStor_EVAC_Power',
  'LynkCo_Vehicle_Charger_Connection_Status', 'LynkCo_Vehicle_Charging_State', 'LynkCo_Vehicle_Charging_Power',
];

function exists(name) {
  return items.getItem(name, true) !== null;
}

function num(name) {
  if (!exists(name)) return null;
  const v = items.getItem(name).numericState;
  return (v === null || Number.isNaN(v)) ? null : v;
}

function str(name) {
  return exists(name) ? items.getItem(name).state : null;
}

// Swedish decimal comma, kW with one or two decimals.
function kw(v, decimals = 1) {
  return Math.abs(v).toFixed(decimals).replace('.', ',') + ' kW';
}

function hours(h) {
  if (h < 1) return `${Math.max(1, Math.round(h * 60))} minuter`;
  return `${h.toFixed(h < 10 ? 1 : 0).replace('.', ',')} timmar`;
}

function set(name, value) {
  const item = items.getItem(name);
  if (item.state !== value) item.postUpdate(value);
}

function update() {
  const pv = num('SigenStor_PV_Power');
  const load = num('SigenStor_Load_Power');
  const bat = num('SigenStor_Battery_Power');
  const grid = num('SigenStor_Grid_Power');
  const soc = num('SigenStor_Battery_SOC');
  const left = num('SigenStor_Avail_Discharge_Cap');
  const room = num('SigenStor_Avail_Charge_Cap');
  const ev = num('SigenStor_EVAC_Power');
  if ([pv, load, bat, grid].includes(null)) {
    set('Lillstugan_JustNu', 'Inga aktuella värden från Lillstugan just nu.');
    set('Lillstugan_JustNu_Detalj', 'Speglingen från Landet svarar inte.');
    return;
  }

  // Summary sentence
  const parts = [`Huset drar ${kw(load, 2)}.`];
  const flows = [];
  if (bat < -IDLE_KW) flows.push(`Batteriet levererar ${kw(bat, 2)}`);
  else if (bat > IDLE_KW) flows.push(`Batteriet laddar med ${kw(bat, 2)}`);
  else flows.push('Batteriet vilar');
  flows.push(pv > IDLE_KW ? `solen ger ${kw(pv, 2)}` : 'solen ger ingenting just nu');
  parts.push(flows.join(', ') + '.');
  if (grid > IDLE_KW) parts.push(`Köper ${kw(grid, 2)} från nätet.`);
  else if (grid < -IDLE_KW) parts.push(`Säljer ${kw(grid, 2)} till nätet.`);
  else parts.push('Ingen import eller export.');
  if (ev !== null && ev > IDLE_KW) parts.push(`Laddaren levererar ${kw(ev, 1)}.`);
  set('Lillstugan_JustNu', parts.join(' '));

  // Detail line
  let detail = '';
  if (bat < -IDLE_KW && left !== null) {
    detail = `Ungefär ${left.toFixed(1).replace('.', ',')} kWh kvar i batteriet, räcker i cirka ${hours(left / Math.abs(bat))} i nuvarande takt.`;
  } else if (bat > IDLE_KW && room !== null) {
    detail = `Fullt om cirka ${hours(room / bat)} i nuvarande takt (${room.toFixed(1).replace('.', ',')} kWh kvar att ladda).`;
  } else if (soc !== null) {
    detail = `Batteriet står på ${Math.round(soc)} %` + (left !== null ? `, ungefär ${left.toFixed(1).replace('.', ',')} kWh tillgängligt.` : '.');
  }
  set('Lillstugan_JustNu_Detalj', detail);

  // Badges
  if (bat < -IDLE_KW) set('Lillstugan_Badge_Batteri', `Urladdar · ${kw(bat, 2)}|warn`);
  else if (bat > IDLE_KW) set('Lillstugan_Badge_Batteri', `Laddar · ${kw(bat, 2)}|ok`);
  else set('Lillstugan_Badge_Batteri', 'Vilar|idle');

  set('Lillstugan_Badge_Sol', pv > IDLE_KW ? `Producerar · ${kw(pv, 2)}|ok` : 'Ingen sol|idle');

  const onGrid = str('SigenStor_OnOff_Grid') === 'ON_GRID';
  if (!onGrid) set('Lillstugan_Badge_Nat', 'Ö-drift|bad');
  else if (grid > IDLE_KW) set('Lillstugan_Badge_Nat', `Köper · ${kw(grid, 2)}|info`);
  else if (grid < -IDLE_KW) set('Lillstugan_Badge_Nat', `Säljer · ${kw(grid, 2)}|ok`);
  else set('Lillstugan_Badge_Nat', 'Ansluten till nät|ok');

  // Sigen EVAC states: A = no car, B = connected, C = charging, E/F = fault
  const evState = String(str('SigenStor_EVAC_State') || '');
  if (evState.startsWith('C')) set('Lillstugan_Badge_Laddare', `Laddar · ${kw(ev || 0, 1)}|ok`);
  else if (evState.startsWith('B')) set('Lillstugan_Badge_Laddare', 'Inkopplad|info');
  else if (evState.startsWith('A')) set('Lillstugan_Badge_Laddare', 'Ej inkopplad|idle');
  else if (evState.startsWith('E') || evState.startsWith('F')) set('Lillstugan_Badge_Laddare', 'Fel|bad');
  else set('Lillstugan_Badge_Laddare', 'Okänd|idle');

  if (!exists('LynkCo_Vehicle_Charging_State')) return;
  const carConn = String(str('LynkCo_Vehicle_Charger_Connection_Status') || '');
  const carState = String(str('LynkCo_Vehicle_Charging_State') || '');
  if (carState.includes('CHARGING') && !carState.includes('IDLE')) set('Lillstugan_Badge_Bil', 'Laddar|ok');
  else if (carConn.includes('CONNECTED') && !carConn.includes('DISCONNECTED')) set('Lillstugan_Badge_Bil', 'Inkopplad|info');
  else set('Lillstugan_Badge_Bil', 'Ej inkopplad|idle');
}

// PersistedState (openhab-js 5) to a number.
function pnum(s) {
  if (s === null || s === undefined) return null;
  const v = s.numericState !== undefined ? s.numericState : Number.parseFloat(s.state);
  return (v === null || Number.isNaN(v)) ? null : v;
}

function setKwh(name, value) {
  const item = items.getItem(name);
  const cur = item.numericState;
  if (cur === null || Number.isNaN(cur) || Math.abs(cur - value) >= 0.01) item.postUpdate(`${value.toFixed(2)} kWh`);
}

function consumption() {
  if (!exists('SigenStor_Total_Load')) return;
  const meter = items.getItem('SigenStor_Total_Load');
  const at = (zdt) => pnum(meter.persistence.persistedState(zdt, 'rrd4j'));
  const now = time.toZDT();
  const midnight = now.truncatedTo(time.ChronoUnit.DAYS);
  const today0 = at(midnight);
  const yesterday0 = at(midnight.minusDays(1));
  if (today0 !== null && yesterday0 !== null) setKwh('Lillstugan_Forbrukning_Igar', Math.max(0, today0 - yesterday0));
  const cur = num('SigenStor_Total_Load');
  const dayAgo = at(now.minusHours(24));
  if (cur !== null && dayAgo !== null) setKwh('Lillstugan_Forbrukning_24h', Math.max(0, cur - dayAgo));
}

rules.JSRule({
  name: 'Lillstugan just nu: text och badges',
  description: 'Bygger sammanfattningen och badgarna för sidan Lillstugan just nu',
  triggers: [
    triggers.SystemStartlevelTrigger(100),
    ...SOURCES.filter(exists).map((name) => triggers.ItemStateChangeTrigger(name)),
  ],
  execute: () => {
    try {
      update();
    } catch (e) {
      logger.warn(`update failed: ${e}`);
    }
  },
  tags: ['lillstugan'],
  id: 'lillstugan-justnu',
});

rules.JSRule({
  name: 'Lillstugan just nu: förbrukning igår och senaste dygnet',
  description: 'Deltan på SigenStor_Total_Load i rrd4j för sidan Lillstugan just nu',
  triggers: [triggers.SystemStartlevelTrigger(100), triggers.GenericCronTrigger('0 */5 * * * ?')],
  execute: () => {
    try {
      consumption();
    } catch (e) {
      logger.warn(`consumption failed: ${e}`);
    }
  },
  tags: ['lillstugan'],
  id: 'lillstugan-forbrukning',
});
