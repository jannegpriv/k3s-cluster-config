# OpenHAB Analytics – klusterinsamling under övergång

Aktuellt driftläge 2026-10-22. Janne har godkänt genomförandet av punkt 1–6:
privat registry, insamling, NAS-backup, övervakning, nyckelhantering och
kontrollerad tunnelövergång. openHAB-konfiguration och styrning ändras inte.
Mac-piloten med sin egen datakatalog och OpenAI-tunnel är fortfarande aktiv.

## Aktiverat och verifierat

- Fyra privata GHCR-images, låsta till digest. Jobbet
  `analytics-registry-proof-20261022` hämtade och startade alla fyra med separat
  läsnyckel, UID 10001, skrivskyddad rot och utan Kubernetes-token/nätåtkomst.
- `analytics-import-20261022` återställde 17–20 oktober från en verifierad
  Mac-kopia till `analytics-data`. Arkivets checksumma och alla energisvar och
  Lynk & Co-svar överensstämmer exakt med originalet.
- `analytics-collection-proof-20261022` gjorde 38 GET-anrop till Huddinge och
  Landet för 20 oktober inklusive bilhistoriken. Huddinge 61,7656 kWh och Landet
  17,21 kWh stämmer med tidigare kopia. Energiräknarna är fortsatt primära;
  ingen automatisk avräkning av bilen från huset görs.
- Ett prov mot en stängd lokal port behöll hela den gamla publiceringen.
  Sju samtidiga läskontroller passerade under riktig insamling. En redan vald
  äldre generation och övriga dygn förblev läsbara och oförändrade.
- `analytics-collect` är aktiverad: `15 * * * *`, Europe/Stockholm. Applikationen
  publicerar föregående dygn först 04.15 och gör inga HTTP-anrop när katalogen
  redan är aktuell. Timvisa försök hämtar ikapp efter avbrott. `Forbid`,
  exklusivt kataloglås och atomisk publicering skyddar mot samtidiga skrivare.
- Gatewayen kör sin privata image. Omstarten bevarade Tailscale-ID,
  `100.66.87.41`, `tag:openhab-analytics` och befintlig PVC. Båda containrarna är
  Ready. Identiteten ligger på volym; registreringsnyckelns dygnsgräns påverkar
  inte den redan registrerade enheten.
- Alla fem MCP-verktyg har verifierats i separat klusterjobb via officiell SDK:
  285 anrop, 68 statistikkontroller, 204 historiksidor, åtta energisvar och fyra
  EV-svar. Scheman, röstsvarsfält, räknarprioritet och skrivskydd passerar.
- Prometheus rapporterar monitorn som up och läser 19 tidsserier. Katalog,
  lagring och nyckelmetadata är giltiga; inga dygn saknas. NAS-backup redovisas
  korrekt som ännu overifierad. Monitorn läser datakatalog,
  driftvolym och offentliga nyckeldatum skrivskyddat. Den har ingen
  Kubernetes-token, inga hemligheter och ingen utgående nätåtkomst.

Ett separat klusterprov har även arkiverat fyra dygn och fem publicerade
versioner från den skrivskyddade volymen och återställt till en tom temporär
katalog. Alla energi- och EV-svar stämmer. Detta är inte en verifierad NAS-backup.
Första automatiska 04.15-körningen är ännu inte observerad.

## Lagring och hemligheter

Tre RWO-volymer på `rook-ceph-block`, bundna till Ceph-lagring:
`analytics-data` 2 GiB, `analytics-operations` 100 MiB och
`analytics-tailscale-state` 100 MiB. Samtliga har Flux prune disabled; PV har
Retain. Separata skriv-/läspoddar har verifierat beständighet, UID 10001 och
skrivskydd. Behåll volymerna vid rollback.

SOPS/PGP-krypterade Secrets har separata roller:

- `registry-secret.enc.yaml`: endast `read:packages` för privata GHCR-paket.
  Faktisk utgång 2027-01-19 23:15:09 UTC (20 januari svensk tid).
- `openhab-secret.enc.yaml`: befintliga tokens för insamling från båda husen.
- `tailscale-secret.enc.yaml`: ursprunglig engångsregistrering för gatewayen.
- `landet-secret.enc.yaml`: äldre avgränsat läsprov.

Publiceringsnyckeln finns aldrig i klustret. Inga nyckelvärden ska finnas i Git,
kommandorader, rapporter eller loggar. openHAB-koden använder endast GET; det
bevisar inte att serverns tokenbehörighet är skrivskyddad.

Gatewayen vidarebefordrar endast godkända GET-anrop till `192.168.1.86:8080`.
Tailscale-policyn, uttryckligen godkänd 2026-10-20, begränsar Analytics-taggen till
just den adressen/porten. Övriga befintliga medlemsenheter och de routade näten
behåller tidigare åtkomst. Inga host-rutter, TUN, hostNetwork eller
NET_ADMIN används; userspace SOCKS och HTTPS-reläer används.

## Återstår före tunnelövergång

1. Begränsad separat Synology-åtkomst och verifierad NAS-uppladdning,
   nedladdning samt återställning med jämförda energi-/bilsvar.
2. Full Prometheus-larmkedja och säker historikgallring. Reglerna aktiveras efter
   backupberedskap; den installerade monitorn redovisar ännu saknad backup.
3. Separat OpenAI-produktionsnyckel, dokumenterade datum och rotationsprov.
4. Kontrollerad tunnelövergång, text-/röstprov
   i båda klientlägena med Mac avstängd samt verifierad återgång.

Ingen OpenAI-tunnel eller NAS-backup körs ännu i klustret. Slutförda engångsjobb
är verifieringsunderlag och ska inte användas som återkommande jobb.

## Återgång

Alla resursändringar görs i Git för Flux. Pausa `analytics-collect` med
`spec.suspend: true` vid felsökning. Behåll data och tidigare publicerade
kataloggenerationer. Mac-katalogen skrivs inte av klustret.

Vid kommande tunnelövergång får Mac och k3s aldrig köra samma tunnel-ID
samtidigt. Stoppa den ena och verifiera att den avslutats innan den andra
startas. Behåll senaste verifierade datakopia och Macens startskript.

Gatewayen kan stoppas med replicas 0. Ändra inte den gemensamma
Tailscale-policyn för att felsöka: det kan bredda Analytics åtkomst. Bevara
identitetsvolymen så att omstart återanvänder samma identitet.

Detaljerade privata kvittenser finns i Analytics-arbetsytans
`private-data/production-rollout-20261022/`. Registrypubliceringen ligger under
`private-data/production-rollout-20261021/registry-publication.json`.
