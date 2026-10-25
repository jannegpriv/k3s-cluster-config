# Lillstugan just nu

Homey-style energy page in openHAB (Huddinge) for Lillstugan at Landet (Glava): a photo of
the cottage with live labels (sol, hus, SigenStor, nät, laddare), a plain-Swedish "Just nu"
summary, cards for SigenStor, solceller, elnät and the Sigen EVAC charger, and a Lynk & Co 08
card. All values come from the SigenStor items mirrored from Landet via Remote openHAB.

Not applied by Flux. Files are copied into the pod / pushed via REST with
`scripts/lillstugan-energi-deploy.sh [photo.jpg]`.

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
