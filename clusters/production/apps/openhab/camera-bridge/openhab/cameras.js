// Battery-camera stream control for the camera-bridge C425s.
// Deployed to /openhab/conf/automation/js/cameras.js (JS Scripting add-on).
//
// <Cam>_PermanentStream (= IP Camera binding channel startStream) is the "Ström PÅ/AV"
// toggle on the Kameror page.
//   ON  -> remove the stale playlist, then poll the binding's HLS endpoint (each call
//          blocks ~4.5 s inside the binding) until it returns a playlist with segments;
//          only then <Cam>_Ready goes ON and the page renders a player. Cold start is
//          10-40 s (camera wake; the first Tapo attempt is often refused) - far more
//          than the 4.5 s the binding waits, and Safari never retries a 404 playlist.
//          A 120 s timer switches the stream OFF again (battery cap).
//   OFF -> <Cam>_Ready OFF (player removed); the binding stops ffmpeg within ~8 s.
const { rules, triggers, items, actions, time, log } = require('openhab');
const logger = log('cameras');

const CAMERAS = [
  { name: 'Landet baksida', item: 'C425_LandetBaksida_PermanentStream', ready: 'C425_LandetBaksida_Ready', thing: 'c425_landet_baksida' },
  { name: 'Carport',        item: 'C425_Carport_PermanentStream',       ready: 'C425_Carport_Ready',       thing: 'c425_carport' },
];
const MAX_ON_MS = 120000;   // battery cap
const POLL_MAX_MS = 90000;  // give up waking after this
const POLL_EVERY_MS = 2000;

for (const cam of CAMERAS) {
  const playlist = `http://127.0.0.1:8080/ipcamera/${cam.thing}/ipcamera.m3u8`;
  const playlistFile = `/dev/shm/ipcamera/${cam.thing}/ipcamera.m3u8`;

  rules.JSRule({
    name: `C425 ${cam.name}: wake`,
    id: `cameras_${cam.thing}_wake`,
    triggers: [triggers.ItemStateChangeTrigger(cam.item, undefined, 'ON')],
    execute: () => {
      actions.Exec.executeCommandLine(time.Duration.ofSeconds(5), 'rm', '-f', playlistFile);
      const started = Date.now();
      setTimeout(() => items.getItem(cam.item).sendCommand('OFF'), MAX_ON_MS);
      const poll = () => {
        if (items.getItem(cam.item).state !== 'ON') return;           // switched off meanwhile
        const body = actions.HTTP.sendHttpGetRequest(playlist, 8000);   // null on 404/timeout
        if (body && body.includes('.ts')) {
          logger.info(`${cam.name}: stream ready after ${Math.round((Date.now() - started) / 1000)} s`);
          items.getItem(cam.ready).postUpdate('ON');
        } else if (Date.now() - started < POLL_MAX_MS) {
          setTimeout(poll, POLL_EVERY_MS);
        } else {
          logger.warn(`${cam.name}: no playlist after ${POLL_MAX_MS / 1000} s - switching off`);
          items.getItem(cam.item).sendCommand('OFF');
        }
      };
      setTimeout(poll, 4000);
    },
  });

  rules.JSRule({
    name: `C425 ${cam.name}: sleep`,
    id: `cameras_${cam.thing}_sleep`,
    triggers: [triggers.ItemStateChangeTrigger(cam.item, undefined, 'OFF')],
    execute: () => items.getItem(cam.ready).postUpdate('OFF'),
  });
}
