# OpenHAB Analytics – aktiv klusterdrift under slutverifiering

Aktuellt driftläge 2026-10-22. Janne har godkänt genomförandet av punkt 1–6:
privat registry, insamling, NAS-backup, övervakning, nyckelhantering och
kontrollerad tunnelövergång. openHAB-konfiguration och styrning ändras inte.
k3s driver nu även den befintliga privata OpenAI-tunneln. Macens insamlare och
tunnel är stoppade; originaldata, profil och LaunchAgent-plist är sparade.
Janne bekräftade 2026-10-23 att ChatGPT-röst på mobilen fungerade med Macen
helt avstängd. Codex/Work-röstprovet efter övergång är ännu inte rapporterat.

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
  lagring och nyckelmetadata är giltiga; inga dygn saknas. Monitorn läser datakatalog,
  driftvolym och offentliga nyckeldatum skrivskyddat. Den har ingen
  Kubernetes-token, inga hemligheter och ingen utgående nätåtkomst.

Den automatiska insamlingen den 22 oktober kl. 04.15 svensk tid lyckades:
38 GET-anrop hämtade den 21 oktober, inklusive Lynk & Co. Aktiva katalogen
innehåller nu fem dygn (17–21 oktober).

## Synology-backup

Janne har 2026-10-22 uttryckligen godkänt samma konto och metod som Basic Memory:
`jannenasadm`, SSH-lösenord och låst servernyckel mot `192.168.50.25:4711`.
Analytics använder `/volume1/k3s_backups/openhab-analytics`. Basic Memorys
konto, backupkatalog, schema och konfiguration är oförändrade.

`analytics-nas-proof-v2-20261022` har laddat upp sex publicerade dygnsversioner
samt ett återställningsarkiv, verifierat fjärrchecksumma, laddat ned arkivet igen
och återställt till en tom katalog. Samtliga energisvar för båda husen och fem
EV-sammanfattningar överensstämmer exakt; källans active.json är oförändrad.
Arkivet är 621058 byte och har SHA256
`239254a8e7d8b0d75214c051a08a9719de2fc5096376d1d9792a23b7a72d8cb1`.

Backupcontainern `0.6.0-ops4` är privat och digestlåst. Den har verifierats med
170 lokala tester, 16 backup-/gatewaytester i Linux ARM64, SSH-startprov och
verklig hämtning med registry-läsnyckeln. Första NAS-provet avbröts eftersom
SSH saknade passwd-post för UID 10001. Den posten finns i den korrigerade
avbildningen; omprovet är godkänt. Det misslyckade jobbet sparas som underlag.

`analytics-backup` kör vid minut 45 varje timme, Europe/Stockholm, med Forbid.
Datavolymen är skrivskyddad och ett delat lås skyddar publicerade filer.
Kontrollsummor måste stämma innan en backup publiceras eller äldre
återställningsarkiv gallras. Dygnsarkiven sparas utan automatisk NAS-gallring;
återställningsarkiv behåller senaste per sju datum och fyra ISO-veckor.

`analytics-maintenance` kör kl. 02.45. Aktiva generationer skyddas alltid;
övrig lokal historik behålls minst 90 dagar och nyligen skapade generationer
minst sju dagar. Borttagning kräver backupkvittens och en ny matchande
NAS-kontrollsumma. Jobbet raderar inga NAS-arkiv.

14 Prometheus-regler omfattar bland annat saknad/felande backup, katalogfel,
diskutrymme och credential-datum. Reglerna använder befintlig larmrouting.
Separat leveransprov är godkänt 2026-10-22: FIRING 21:54:22 UTC och RESOLVED
21:56:22 UTC har verifierats i både Mattermost `k3s-alerts` och mottagarens
Gmail. Provet aktiverades först efter Jannes uttryckliga tillstånd.

2026-10-22 19:00 UTC verifierades samtliga 14 larmregler med klustrets
`promtool 2.48.1`: 19 isolerade scenarier och 75 kontroller av väntetid,
utlösning och återgång passerar. Alternativa felgrenar, för gammal
backup/gallringskvittens och helt saknad exporter ingår. Testad spec är exakt
identisk med aktuell kluster-spec. Inga levande mätserier eller larm ändrades.
TEST-larmets tillfälliga routning förbi AI-remediator verifierades i körande
Alertmanager innan provregeln aktiverades. Båda leveranserna är kvitterade.
Provregeln och de två tillfälliga rutterna togs bort via commit `c2453dd`;
den ordinarie AlertmanagerConfig-specen återställdes exakt.

Återkommande backup har verifierats, senast 2026-10-22 18:45:43 UTC. Aktuell
backup matchar aktiv generation och inga dygn saknas. Schemalagt underhåll har
ännu inte hunnit köras första gången; separat skarpt underhållsprov är godkänt.

## CPU-varningen 2026-10-22

Gatewayens exec-readiness startade Python var 30:e sekund. Native HTTP-probe
anropar nu samma `/readyz`, som fortfarande testar Landets SOCKS-väg. Vid
femminutersmätning sjönk gatewayens CPU från 39,6m till 0,4m och andelen
throttlade perioder från 65,7 % till 0 %. Request 20m och limit 500m är oförändrade.
Samma Tailscale-ID/IP bevarades; ett separat jobb verifierade två verkliga GET.

Monitorns integritetskontroll hade separat throttling. Request höjdes till
100m och limit till 1000m. Andelen throttlade perioder sjönk 63,1 % till 1,83 %.
Inget NodeCPUThrottling-larm för Analytics var aktivt 18:54 UTC. Periodandelen
ska inte tolkas som andel förlorad CPU-tid. Ändringar: `3fc36a8`, `e3148e1`.

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
- `nas-secret.enc.yaml`: samma befintliga NAS-lösenord som Basic Memory,
  separat SOPS-krypterad Secret. Lösenordet kopieras till minnesvolym med 0600,
  aldrig till argv eller miljövariabler. Inga kontorättigheter har ändrats.
  Vid lösenordsrotation måste både Basic Memory och Analytics uppdateras
  och båda backupjobben verifieras. Granskningsdatum är 2027-01-20.
- `tunnel-secret.enc.yaml`: separat produktionsnyckel, verifierad Tunnels
  Read + Use. Utgång 2027-01-20 07:59:49 UTC, granskning/rotation 2027-01-06
  07:59:49 UTC. Båda datumen läses av Prometheus. Poddens credential-revision
  ska ändras vid rotation eftersom nyckeln kopieras till minne vid start.

Publiceringsnyckeln finns aldrig i klustret. Inga nyckelvärden ska finnas i Git,
kommandorader, rapporter eller loggar. openHAB-koden använder endast GET; det
bevisar inte att serverns tokenbehörighet är skrivskyddad.

Gatewayen vidarebefordrar endast godkända GET-anrop till `192.168.1.86:8080`.
Tailscale-policyn, uttryckligen godkänd 2026-10-20, begränsar Analytics-taggen till
just den adressen/porten. Övriga befintliga medlemsenheter och de routade näten
behåller tidigare åtkomst. Inga host-rutter, TUN, hostNetwork eller
NET_ADMIN används; userspace SOCKS och HTTPS-reläer används.

## Tunnelövergång och kvarvarande acceptans

Samtliga fem riktiga MCP-verktyg fungerar via k3s. Landet 17 oktober ger 13,80
kWh från räknaren; bilsammanfattningen ger tre perioder och 20–100 %, utan
automatiskt husavdrag. Generationen är `e7c5ac1eed53495a92469b54f1720e0e`.

Återgångsprovet är genomfört: k3s stoppades, NAS-arkivet återlästes till ny
Mac-katalog, Mac startades ensam med gamla nyckeln och riktiga MCP-anrop
verifierades. Mac stoppades igen innan k3s återaktiverades med nya nyckeln.
Slutcommit `f45fefd`; ingen samtidig tunnelkörning. Alla energisvar och EV-svar
i NAS-återställningen matchar klustrets katalog exakt.

Kvar: Codex/Work-röstprov efter övergång samt återkallelse av gamla pilotnyckeln
efter acceptans. Mobilprovet i ChatGPT med Mac avstängd är användarbekräftat
2026-10-23; exakt svarsinnehåll har inte återlästs som separat tekniskt kvitto.
Den gamla nyckeln är fortfarande giltig till 17 november och har endast
behållits för återgång. Det särskilda Analytics-leveransprovet är nu godkänt.
Slutförda engångsjobb är verifieringsunderlag, inte återkommande jobb.

## Återgång

Alla resursändringar görs i Git för Flux. Pausa `analytics-collect` med
`spec.suspend: true` vid felsökning. Behåll data och tidigare publicerade
kataloggenerationer. Mac-katalogen skrivs inte av klustret.

Vid tunnelövergång får Mac och k3s aldrig köra samma tunnel-ID
samtidigt. Stoppa den ena och verifiera att den avslutats innan den andra
startas. Behåll senaste verifierade datakopia och Macens startskript.

Gatewayen kan stoppas med replicas 0. Ändra inte den gemensamma
Tailscale-policyn för att felsöka: det kan bredda Analytics åtkomst. Bevara
identitetsvolymen så att omstart återanvänder samma identitet.

Detaljerade privata kvittenser finns i Analytics-arbetsytans
`private-data/production-rollout-20261022/`. Registrypubliceringen ligger under
`private-data/production-rollout-20261021/registry-publication.json`.
