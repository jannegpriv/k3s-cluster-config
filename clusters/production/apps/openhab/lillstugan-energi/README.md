# Lillstugan just nu

Homey-style energy page for Lillstugan at Landet (Glava): a photo of the cottage with live
labels (sol, hus, SigenStor, nät, laddare), a plain-Swedish "Just nu" summary, and cards for
SigenStor, solceller, elnät and the Sigen EVAC charger. The same files run in both openHABs:

- **Landet** (Pi `openhab3`, http://192.168.1.86:8080): native SigenStor items, no Lynk & Co card.
- **Huddinge** (K3s, http://192.168.50.75:30080): SigenStor items mirrored from Landet via
  Remote openHAB, plus a Lynk & Co 08 card.

Not applied by Flux. Files are copied into the pod / pushed via REST with
`scripts/lillstugan-energi-deploy.sh [huddinge|landet] [photo.jpg]`.

| File | What | Lives in |
|---|---|---|
| `lillstugan.items` | String items for the summary and card badges | `conf/items/` |
| `lillstugan-justnu.js` | JS Scripting rule that writes those items on every SigenStor change | `conf/automation/js/` |
| `widget-lillstugan-hero.yaml` | photo + markers + "Just nu" text | Main UI widget (jsondb) |
| `widget-lillstugan-kort.yaml` | reusable dark card (big value, badge, bar, 8 rows) | Main UI widget (jsondb) |
| `widget-lillstugan-bil.yaml` | Lynk & Co 08 card | Main UI widget (jsondb) |
| `page-lillstugan.yaml` | layout page `lillstugan_just_nu` | Main UI page (jsondb) |

Notes
- The photo (`conf/html/lillstugan.jpg`, 1600x920) is not in Git because the repo is public.
  Marker positions are percentages of the photo, set in `widget-lillstugan-hero.yaml`.
- Sign conventions: battery power > 0 charging, grid power > 0 import (verified against history).
- No spot price source exists in either openHAB (checked 2026-10-25), so there is no spot price card.
- Independent of the "Solel", "Solel Historik" and "SigenStor AI Utvärdering" pages.

Rollback: delete the page and the three widgets in Main UI, remove the two files from
`conf/items/` and `conf/automation/js/`, and `conf/html/lillstugan.jpg`.
