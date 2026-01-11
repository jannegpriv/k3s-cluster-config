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
