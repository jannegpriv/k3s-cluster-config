# SigenStor AI Utvärdering

Main UI chart page `chart_sigenai` in the Huddinge openHAB (K3s, http://192.168.50.75:30080).
Month view of what the SigenStor battery at Landet is worth per day.

Not applied by Flux. `page-chart-sigenai.json` is a copy of the page as stored in openHAB's
jsondb. Restore it with an API token:

```bash
curl -X PUT http://192.168.50.75:30080/rest/ui/components/ui:page/chart_sigenai \
  -H "Authorization: Bearer $OPENHAB_TOKEN" -H "Content-Type: application/json" \
  --data @page-chart-sigenai.json
```

- Upper chart: `SigenStorAI_Daily_Battery_Value` (bar) and `SigenStorAI_Cumulative_Battery_Value`
  (line, accumulated since `SigenStorAI_Battery_Value_Since`).
- Lower chart: avoided grid purchase, battery export, grid charging cost, opportunity cost of
  solar charging, and equivalent cycles.
- The values are written at 07:00 for the previous day by the n8n workflow
  "SigenStor AI Dygnsrapport" (`n8n-workflows/sigenstor-ai-dygnsrapport.json`), so each bar sits
  on the day after the day it describes.
- Persistence is rrd4j, which does not accept old timestamps. The history for 1-18 November 2026
  was recalculated with the workflow's own code and written by rebuilding the rrd files
  (2026-11-20). Days before 14 November are based on 15-minute data.
- The legacy items `SigenStorAI_Daily_Net` and `SigenStorAI_Cumulative_Net` (export revenue minus
  grid charging cost) still exist but are no longer on the page.
