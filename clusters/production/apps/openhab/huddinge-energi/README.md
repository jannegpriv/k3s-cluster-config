# Huddinge just nu

One-screen overview for the house in Huddinge, in the same dark style as
[Lillstugan just nu](../lillstugan-energi/README.md): a plain-Swedish "Just nu" summary with
four tiles (ute, framledning, effekt nu, el idag), the IVT Premiumline HQ C8 heat pump,
electricity per phase (Currently One) and the Lynk & Co 08.
Page: http://192.168.50.75:30080/page/huddinge_just_nu

Not applied by Flux. Deploy with `scripts/huddinge-energi-deploy.sh`. The page reuses
`lillstugan_kort` and `lillstugan_bil`, which `scripts/lillstugan-energi-deploy.sh huddinge` deploys.

| File | What | Lives in |
|---|---|---|
| `huddinge.items` | summary, badges, daily figures, forecast, main fuse | `conf/items/` |
| `huddinge-justnu.js` | JS Scripting rules: live text/badges, 5-min rrd4j stats, hourly forecast | `conf/automation/js/` |
| `widget-huddinge-hero.yaml` | "Just nu" text + four tiles | Main UI widget (jsondb) |
| `widget-huddinge-el.yaml` | power, kWh today / 24 h, bar per phase, highest phase, voltages | Main UI widget (jsondb) |
| `page-huddinge.yaml` | layout page `huddinge_just_nu` | Main UI page (jsondb) |

Notes
- "El sedan 00:00" and "senaste dygnet" are meter deltas of `Currently_One_Currently_Used`
  from rrd4j. Compressor and auxiliary heater hours are the share of rrd4j minute samples
  that were ON / above 0 over the last 24 h.
- Phase bars scale against `FUSE_A` in `huddinge-justnu.js` (20 A main fuse, confirmed 2026-10-25), written
  to `Huddinge_Huvudsakring`; orange from 80 %, red at 100 %.
- Tomorrow's forecast comes from VäderKollen's public `smhi-forecast` edge function (SMHI data,
  no key), queried hourly for central Huddinge (city-level coordinates, not the address).
- No photo yet; the hero can get one like Lillstugan's when there is a picture of the house.
- Read-only: nothing is sent to the heat pump, the meter or the car.

Rollback: delete the page and the two widgets in Main UI, and remove `huddinge.items` and
`huddinge-justnu.js` from `conf/items/` and `conf/automation/js/`.
