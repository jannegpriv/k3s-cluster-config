// camera-bridge rules. Deployed to /openhab/conf/automation/js/cameras.js (JS Scripting).
//
// 1) Last-frame stills: whenever a camera's HLS stream stops (binding sets startStream
//    OFF), grab one frame from the newest segment into conf/html/<cam>-last.jpg so the
//    Kameror page always shows the latest picture without touching the camera.
//
// 2) Battery cameras (C425): tapping the still sends startStream ON. We then remove
//    the stale playlist and poll the binding's HLS endpoint (each call blocks ~4.5 s
//    inside the binding) until it returns a playlist with segments; only then
//    <Cam>_Ready goes ON and the page swaps the still for a player. Cold start is
//    10-40 s (camera wake; first Tapo attempt is often refused) - far more than the
//    4.5 s the binding waits, and Safari never retries a 404 playlist. A 120 s timer
//    switches the stream OFF again (battery cap).
const { rules, triggers, items, actions, time, log } = require('openhab');
const logger = log('cameras');

const CAMERAS = [
  { name: 'Lillstugan',     item: 'C720_Lillstugan_PermanentStream',     ready: null,                      thing: 'c720_lillstugan',     hlsDir: '/dev/shm/ipcamera/c720_lillstugan' },
  { name: 'Landet baksida', item: 'C425_LandetBaksida_PermanentStream', ready: 'C425_LandetBaksida_Ready', thing: 'c425_landet_baksida', hlsDir: '/dev/shm/ipcamera/c425_landet_baksida' },
  { name: 'Carport',        item: 'C425_Carport_PermanentStream',       ready: 'C425_Carport_Ready',       thing: 'c425_carport',        hlsDir: '/dev/shm/ipcamera/c425_carport' },
];
const MAX_ON_MS = 120000;   // battery cap for the C425s
const POLL_MAX_MS = 90000;  // give up waking after this
const POLL_EVERY_MS = 2000;
const STILL_DIR = '/openhab/conf/html';

function saveLastFrame(cam) {
  // The newest .ts may be truncated (ffmpeg was just killed) -> prefer the 2nd newest.
  // First frame of a segment is a keyframe, so one decode is enough. Explicit -f image2:
  // the .tmp name carries no extension for ffmpeg to guess the format from.
  const out = `${STILL_DIR}/${cam.thing}-last.jpg`;
  const cmd = `set -- $(ls -t ${cam.hlsDir}/*.ts 2>/dev/null); f="$2"; [ -n "$f" ] || f="$1"; [ -n "$f" ] || exit 3; ` +
              `ffmpeg -y -hide_banner -loglevel error -i "$f" -frames:v 1 -q:v 3 -f image2 ${out}.tmp && mv ${out}.tmp ${out} && echo ok $(basename "$f")`;
  const res = actions.Exec.executeCommandLine(time.Duration.ofSeconds(20), '/bin/sh', '-c', cmd);
  logger.info(`${cam.name}: last frame -> ${res || 'FAILED'}`);
}

for (const cam of CAMERAS) {
  const playlist = `http://127.0.0.1:8080/ipcamera/${cam.thing}/ipcamera.m3u8`;

  rules.JSRule({
    name: `Kamera ${cam.name}: stillbild vid stopp`,
    id: `cameras_${cam.thing}_still`,
    triggers: [triggers.ItemStateChangeTrigger(cam.item, undefined, 'OFF')],
    execute: () => {
      if (cam.ready) items.getItem(cam.ready).postUpdate('OFF');
      // the binding kills ffmpeg within ~8 s of OFF; the segments stay on disk
      setTimeout(() => saveLastFrame(cam), 1000);
    },
  });

  if (!cam.ready) continue;   // mains camera: no wake flow needed

  rules.JSRule({
    name: `Kamera ${cam.name}: väck`,
    id: `cameras_${cam.thing}_wake`,
    triggers: [triggers.ItemStateChangeTrigger(cam.item, undefined, 'ON')],
    execute: () => {
      actions.Exec.executeCommandLine(time.Duration.ofSeconds(5), 'rm', '-f', `${cam.hlsDir}/ipcamera.m3u8`);
      const started = Date.now();
      setTimeout(() => items.getItem(cam.item).sendCommand('OFF'), MAX_ON_MS);
      const poll = () => {
        if (items.getItem(cam.item).state !== 'ON') return;           // stopped meanwhile
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
}
