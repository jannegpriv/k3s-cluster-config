# n8n Workflows

Denna mapp innehåller backups av n8n workflows för K3s-klustret.

## Workflows

- **K3s** (OovUiuo0GcJ1Wftw) - Övervakar K3s kluster-status med CPU, minne, alerts och Kubernetes events
- **Daglig Energianalys** (J54qTYk9YbJezmHQ) - Daglig analys av energiförbrukning
- **Vecko Energisammanfattning** (WX2uKcMMSgeP8Qaf) - Veckovis energisammanfattning

## Export av workflows

För att exportera workflows från n8n, använd följande kommando:

```bash
./export-workflows.sh
```

## Restore av workflows

Workflows kan importeras via n8n UI under **Settings → Import from File**.

## Senast uppdaterad

2026-01-11 - Lade till Kubernetes events monitoring i K3s workflow

## Certifikatrapportering (2026-09-30)

`k3s-format-report.js` är källan till K3s-flödets `Format data`-nod.
Efter ändringar, synka exporten och kör regressionstesterna:

```sh
node n8n-workflows/sync-k3s-report.mjs
node n8n-workflows/sync-k3s-report.mjs --check
node --test n8n-workflows/test/k3s-report.test.mjs
```

Certifikatavsnittet beräknas i kod och läggs oförändrat efter AI-sammanfattningen.
Nod, utgångsdatum (Europe/Stockholm), återstående dagar och senaste observation
behålls. Fullständiga eventmeddelanden finns i `certificateFindings`; inget
certifikatevent klipps till 100 tecken eller faller bort genom tiopostersgränsen.

- Högst 120 dagar kvar: **VARNING**.
- Högst 30 dagar kvar: **HÖG PRIORITET**.
- Högst 7 dagar kvar, utgånget certifikat eller ett uttryckligt certifikatfel:
  **KRITISKT**, om eventet är aktuellt.
- Saknat eller ogiltigt utgångsdatum: **VARNING**, begär direkt kontroll utan
  att gissa utgångsdatum. Ett faktiskt certifikatfel är fortfarande kritiskt.
- Senaste observation äldre än 24 timmar: historiskt underlag, inte aktuellt
  larm. Saknad observationstid eller mer än fem minuters framtida tid ger okänd
  aktualitet. Återkommande events bedöms efter senaste observation, inte skapandet.
- Frånvaro av events bevisar inte att certifikaten är friska eller att gamla
  problem är lösta. Misslyckad dataläsning ger okänd status.

AI:n sammanfattar endast övrig aktuell driftstatus. Rapportens anslutning till
`Simple Memory` är borttagen för att tidigare rapporter inte ska blandas in.
Minnesnoden finns kvar frånkopplad. Alertmanager-flödet och Claude-chattflödet
har kvar sina befintliga anslutningar.

### Uppdatering av aktivt flöde

Jämför alltid både utkast och publicerad version med exporten. De kan skilja
sig även när `versionId` och `activeVersionId` är lika efter äldre CLI-importer.
Säkerhetskopiera båda utanför Git eftersom fullständiga exporter kan innehålla
webhook-hemligheter. Patcha endast rapportnoderna och minnesanslutningen.

Använd n8n:s API för publicering så att körande triggers laddar rätt version.
I n8n 2.29.9 publicerar API:ts PUT automatiskt om flödet är aktivt. Om separata
utkaständringar måste bevaras: avpublicera kort, spara den korrigerade
publicerade versionen, spara det korrigerade utkastet, och aktivera uttryckligen
den först sparade versionens ID. Kontrollera sedan publicerade noder,
utkast, registrerade triggers och att flödet fortfarande är aktivt.

Vid problem: återaktivera föregående publicerade versions-ID via API. Ingen
n8n- eller K3s-omstart behövs. Kör inte hela produktionsflödet som test om det
skulle skicka oönskade Mattermost-meddelanden.
