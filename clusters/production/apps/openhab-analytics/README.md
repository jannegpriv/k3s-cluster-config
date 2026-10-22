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
Ett separat prov av levererad larmnotis är ännu inte gjort.

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

Publiceringsnyckeln finns aldrig i klustret. Inga nyckelvärden ska finnas i Git,
kommandorader, rapporter eller loggar. openHAB-koden använder endast GET; det
bevisar inte att serverns tokenbehörighet är skrivskyddad.

Gatewayen vidarebefordrar endast godkända GET-anrop till `192.168.1.86:8080`.
Tailscale-policyn, uttryckligen godkänd 2026-10-20, begränsar Analytics-taggen till
just den adressen/porten. Övriga befintliga medlemsenheter och de routade näten
behåller tidigare åtkomst. Inga host-rutter, TUN, hostNetwork eller
NET_ADMIN används; userspace SOCKS och HTTPS-reläer används.

## Återstår före tunnelövergång

1. Separat OpenAI-produktionsnyckel är sparad och SOPS-krypterad lokalt;
   verifiering av faktiska datum/rättigheter och rotationsprov återstår.
2. Kontrollerad tunnelövergång, text-/röstprov i båda klientlägena med Mac
   avstängd samt verifierad återgång.
3. End-to-end-prov av larmleverans återstår. NAS-uppladdning och återläsning är
   verifierade; första återkommande backupkörningen följs separat.

Ingen OpenAI-tunnel körs ännu i klustret. Mac-piloten är kvar. Slutförda
engångsjobb är verifieringsunderlag och ska inte användas som återkommande jobb.

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
