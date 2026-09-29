# Flytt av openHAB från w5 till w6

Status: **driftsatt och kontrollerad på w6 2026-09-29; nästa nattbackup och tre enhetsstatusar återstår att följa upp**.
Janne godkände genomförande och avbrott med ”Jag tycker vi kör nu!”.
Nedan bevaras planen; genomförandeloggen anger vad som faktiskt är gjort.

## Mål och avgränsning

Flytta `openhab/openhab-production` från `k3s-w-5` (ARM64,
`192.168.50.21`) till `k3s-w-6` (AMD64, `192.168.50.168`). Återanvänd de fyra
befintliga Ceph-volymerna. Kör endast en openHAB-instans åt gången.

Behåll openHAB 5.2.1, Promtail 2.9.2, minneslimit 4Gi, minnesrequest 2000Mi,
CPU-request 1, CPU-limit 4.5 och `-Xmx1500m -Duser.timezone=Europe/Stockholm`.
Behåll också Service/NodePort, ingress, volymnamn och lagringsklass.
Kamerabryggan stannar på w3. W5 finns kvar som klusternod och återgångsmål.
Ingen uppgradering av K3s, Rook eller Ceph ingår.

**Tidsbudget:** reservera 60 minuter för underhåll och räkna preliminärt med
30–45 minuters avbrott i Huddinges openHAB. Det är en försiktig uppskattning,
inte en uppmätt flyttid: nattens backupjobb tog cirka 16 minuter och en ny
cache kan förlänga uppstarten. Förberedelser görs före avbrottet. Landets
separata openHAB-instans fortsätter, men dess spegling till Huddinge avbryts.

## Verifierat nuläge

Kontrollerat genom Kubernetes-API, SSH, läsande openHAB REST-anrop,
Docker Registry och ZIP-integritetskontroll 2026-09-29 cirka 09:55–10:10 CEST.

| Område | Resultat |
| --- | --- |
| Kluster/lagring | Ceph `HEALTH_OK`, 129 PG `active+clean`; w6 Ready och tillgänglig för schemaläggning. RBD-skrivning/läsning på w6 verifierades vid onboarding. |
| Kapacitet w6 | 8 logiska CPU, cirka 15,1 GiB allokerbart minne. Uppmätt nodanvändning cirka 1,7 GiB; openHAB på w5 cirka 3,0 GiB inklusive sidovagn. |
| Körning | En replika, `hostNetwork: true`, `ClusterFirstWithHostNet`, 300 sekunders avslutningstid. Inga readiness-/startup-/liveness-prober. Pod Ready bevisar därför inte att openHAB har startat färdigt. |
| Lokala beroenden | Endast tidszonsfiler monteras från värden; de finns på w6. Inga USB-/serieportsmonteringar i podspecen. Inga `/dev/tty`-beroenden hittades i Thing-konfigurationerna. |
| Portar w6 | Ingen lyssnare observerad på 8080, 8443, 8101 eller Promtails 9080. Kontrollera även bindingarnas portar före flytt. |
| Applikation | 244 Things: 174 ONLINE, 66 OFFLINE, 3 UNKNOWN, 1 UNINITIALIZED. 987 Items, varav 300 NULL/UNDEF. 64 REST-regler, alla IDLE. Detta är en referensbild, inte krav på att alla enheter ska vara online. |
| Integrationer | Bland annat MQTT, Modbus/IVT, Remote openHAB, kameror, Hue, Tradfri, Tellstick och Lynk & Co. Fem IP Camera-Things var ONLINE; de använder `/usr/bin/ffmpeg`. |
| Extra tillägg | `/openhab/addons/org.openhab.binding.lynkco-5.2.2-SNAPSHOT.jar`; inga `.so`, `.dll`, `.dylib` eller `.node`-filer hittades i detta JAR-arkiv. Faktisk funktion på x86 återstår att verifiera. |
| Persistens | `rrd4j`-katalog finns i userdata. Historik måste kontrolleras efter flytt. |

### Volymer

Alla är Bound, `ReadWriteOnce`, `rook-ceph-block`, återtagningspolicy `Retain`,
utan nodaffinitet och nu anslutna till w5. Ingen ny PVC eller dataimport behövs
för själva nodbytet. RWO innebär här att volymerna ska lossas från w5 innan
de ansluts till w6.

| Mount | PVC | Storlek | Ceph-image i `replicapool` |
| --- | --- | --- | --- |
| `/openhab/conf` | `openhab-production-conf-claim` | 1Gi | `csi-vol-8be09a67-0b91-447b-8231-178888070de7` |
| `/openhab/userdata` | `openhab-production-userdata-claim` | 16Gi | `csi-vol-fd2cf8a8-df45-450a-b613-126186cadf21` |
| `/openhab/addons` | `openhab-production-addons-claim` | 4Gi | `csi-vol-4c880b91-36fe-4889-a20f-2c49e1f9c336` |
| `/openhab/.karaf` | `openhab-production-karaf-claim` | 100Mi | `csi-vol-c7727005-1ac3-4812-a6f2-5517fd0e53d3` |

Image-identiteterna ska läsas på nytt från PV/CSI före snapshot/återställning,
inte användas blint om PVC:er har ändrats sedan planeringen.

### Backup och återställningsluckor

- Senaste jobb: `openhab-backup-29844000`, lyckat 2026-09-29 02:16 CEST.
- Arkiv: `openhab-backup-26_09_29-02_00_22.zip`, **528712689 byte**.
  `unzip -tq` godkändes. SHA-256:
  `d838770d885054be4b73ef844a74f6cff79201e134e5bd6df3814bf8f90e1c28`.
- Jobbloggen bekräftar SCP till NAS `192.168.50.25:4711`, katalog
  `/volume1/k3s_backups/openhab`. NAS-kopian har **inte** lästs tillbaka eller
  checksummeverifierats i planeringen. Detta återstår före flytten.
- ZIP-filen innehåller `conf`, `userdata`, `backup.properties`. Den innehåller
  **inte** de separata `addons`- och `.karaf`-volymerna. `--full` inkluderar
  cache/tmp; det betyder inte backup av alla fyra PVC:erna.
- Userdata är cirka 85 % fullt, cirka 2,5 GiB ledigt. Ungefär 12 GiB ligger i
  backupkatalogen, inklusive äldre `userdata-*.tar` som dagens ZIP-rensning
  inte tar bort. Ingen rensning eller volymutökning har gjorts.
- `restore-backup.sh` har fel NAS-katalog och gammal pod-label-selector.
  Äldre restore-/addons-jobb använder image 4.3.2 och ingår inte i aktiv
  kustomization. **Använd dem inte som återställningsrutin för denna flytt.**
- Snapshot-API:t `snapshot.storage.k8s.io` är inte installerat. Planen använder
  därför namngivna, tillfälliga RBD-snapshots via Ceph efter kontrollerat stopp,
  kompletterat med arkiv på NAS. Snapshots i samma kluster ersätter inte backup.

### Nätverk och processorarkitektur

- `org.openhab.network.primaryAddress` är `10.42.2.97/24`, inte w5:s LAN-adress.
  `useOnlyOneAddress` är false. Detta är en avvikelse att hantera vid flytten;
  det är inte bevisat att den orsakar befintliga offline-enheter.
- Inga exakta referenser till `192.168.50.21` hittades i Thing-konfigurationerna.
  Klientappar, Cloudflare Dashboard, externa callbacks och tillåtelselistor
  är inte fullständigt inventerade. De måste kontrolleras före avbrottet.
- Stabil lokal ingång är `http://192.168.50.75:30080`. Service och NodePort
  följer podden. Direktadressen `192.168.50.21:8080` följer däremot inte med.
- Båda containerbildernas manifest stöder linux/amd64 och linux/arm64.
  Behåll samma version och lås till verifierat **multiarch-index**, vilket även
  tillåter återgång till ARM:
  - `openhab/openhab:5.2.1-debian@sha256:bfd4a60e90da18cf917a9004bbc22354fc818825f3c6f0351e471a2e938d6c3c`
  - `grafana/promtail:2.9.2@sha256:3ec78a089e5cb5173f5348ee29de4d3cdab29493776ac5704db8727fa0cda60f`
- openHABs `postStart` installerar ffmpeg genom apt. Kontrollera nedladdning
  och x86-paket före avbrottet i en isolerad förberedelse utan produktionsdata
  eller startade hemautomationer. Första produktionsstarten är fortfarande
  beroende av att apt fungerar. Ingen imagebyggnad eller versionsuppgradering
  bakas in i flytten.

## Rekommenderat genomförande efter godkännande

### 1. Förbered utan avbrott

1. Hämta senaste Git-revisionen och kontrollera att ingen annan ändring pågår.
   Dokumentera basrevision, image-index och resursvärden. Alla manifeständringar
   görs i repot och tillämpas av Flux; inga manuella scale-/selector-patchar.
2. Kontrollera Ceph, CSI, w5, w6, DNS, ledigt minne, volymutrymme och Flux igen.
   Hämta bilder i förväg. Säkerställ nätåtkomst till binding-/paketkällor.
3. Spara en färsk referensbild med Thing-UID/status, Item-antal, regler, sidor,
   nätverksinställningar och historik. Känsliga fullständiga REST-svar och
   backupdata lagras privat med begränsade rättigheter, aldrig i Git eller minnet.
4. Kontrollera Cloudflare-tunnelns verkliga backend och mobil-/klockapparnas
   lokala URL. Om en ingång pekar direkt på w5:8080, förbered ändring till
   stabil Service/NodePort-ingång och en motsvarande återgång. DNS-namn och
   certifikat behöver normalt inte ändras.
5. Kontrollera nya LAN-adressens åtkomst till MQTT, IVT/Modbus, NAS,
   kamerabryggan och Landet. Kontrollera callbacks, multicast och eventuella
   IP-tillåtelselistor. Inga kommandon till värme, lås eller andra enheter skickas.
6. Läs tillbaka NAS-backupen, jämför storlek/SHA-256 och testa ZIP. Bekräfta att
   det finns utrymme för ett separat migrationsarkiv på NAS och temporär lagring.
   Skapa inte extra stora arkiv på den nästan fulla userdata-volymen.
7. Förbered och granska ett tillfälligt underhållsjobb i Git, med de fyra PVC:erna,
   utan openHAB-start och utan produktionspodens `app`-label. Det får först
   aktiveras efter stoppet. Använd en prövad arkiv-/SSH-miljö och befintlig
   Secret-referens; inga lösenord i manifest eller kommandologgar.
8. Säkerställ att automatisk remediators omstarter inte kan konkurrera med
   underhållet. Använd ett avgränsat, tidsbegränsat underhållsundantag för
   openHAB och dokumentera hur det återtas. Befintlig `maintenance-mode`
   ConfigMap finns bara som referensfil och ska inte antas vara aktiv.

**Startvillkor:** fungerande verifierad backup, frisk lagring, tillgänglig
återgångsnod, godkända förberedelser och ett av Janne godkänt avbrottsfönster.

### 2. Stoppa, säkra data och förbered x86

1. Git-fas A1: sätt `openhab-backup.spec.suspend: true`. Reconcile Flux och
   vänta tills eventuellt pågående backupjobb är färdigt; suspend avslutar inte
   redan startade jobb. Därefter Git-fas A2: sätt StatefulSet `replicas: 0`,
   fortfarande på w5. Reconcile och kontrollera faktiskt tillstånd;
   Flux Ready räcker inte som applikationskontroll.
2. Vänta tills produktionspodden har avslutats normalt. Respektera
   300 sekunders grace period. Kontrollera
   att alla fyra volymer är avmonterade och VolumeAttachments till w5 har släppt.
   Använd inte force-delete eller tvingad RBD-detach vid väntan.
3. Skapa en daterad RBD-snapshot av var och en av de fyra verifierade
   Ceph-imagesen medan ingen pod skriver. Anteckna image, snapshotnamn,
   tidsstämpel och basrevision i genomförandeloggen.
4. Aktivera underhållsjobbet på w5. Ta ett konsekvent arkiv av `conf`,
   `userdata`, `addons` och `.karaf`, med ägarskap/rättigheter bevarade.
   Uteslut endast den gamla rekursiva `userdata/backup`-samlingen; behåll
   konfiguration, JSONDB, persistens, tillägg och övriga användardata.
   Strömma eller skriv till separat temporär lagring och överför till NAS.
   Kontrollera arkivets läsbarhet, SHA-256 på båda sidor och att alla fyra
   kataloger ingår. Befintliga nattbackuper lämnas kvar.
5. Förbered ren `userdata/cache` och `userdata/tmp` med openHAB stoppat,
   först efter godkänd backup och snapshots. Återskapa katalogerna med samma
   rättigheter. Dessa återskapas för den nya arkitekturen. Rör inte JSONDB,
   persistens, UUID, hemligheter, Things/Items/regler, addons eller `.karaf`.
6. Ta bort underhållsjobbet via Git/Flux och vänta på avmontering/avanslutning
   innan w6 får starta. Avbryt om backup eller frånkoppling inte kan bekräftas.

### 3. Starta på w6

1. Git-fas B, medan `replicas: 0`: byt nodeSelector till `k3s-w-6`, lås de två
   image-indexen ovan och uppdatera endast openHABs två nodspecifika minneslarm
   från `192.168.50.21:9100` till `192.168.50.168:9100`. Resurser och övrig
   JVM-konfiguration är oförändrade. Reconcile och kontrollera podmallen.
2. Git-fas C: sätt `replicas: 1`. Reconcile och följ volymanslutning,
   imagehämtning, ffmpeg-installation, Java-start och loggar. Bekräfta AMD64,
   rätt image-index, rätt PVC:er och att ingen openHAB-process finns på w5.
3. Läs nätverksinställningarna via REST, bevara övriga värden och välj w6:s
   LAN-adress `192.168.50.168/24` som Primary Address via stödd REST/UI.
   Dokumentera ändringen och återgångsvärdet; redigera inte JSONDB direkt.
   Bedöm om en kontrollerad omstart behövs för berörda bindings.
4. Kontrollera appen funktionellt enligt nedan. En grön podstatus är inte
   tillräcklig eftersom applikationsprober saknas.

### 4. Godkänn drift och återställ backup/övervakning

1. API/UI ska svara på stabil lokal URL och `openhab.k3s.nu`. Kontrollera
   Cloudflare-vägen separat; den är inte verifierad bara för att NodePort svarar.
2. Jämför Things per UID med referensbilden. Utred **nya** offline-/felstatusar;
   gamla offline-enheter ska inte omdefinieras som migrationsfel. Verifiera
   särskilt MQTT, Modbus/IVT, Landet-spegling, kameror och Lynk & Co.
3. Kontrollera Item-/regel-/sidantal, nya sensorvärden och att befintliga
   rrd4j-diagram har kvar sin historik och fortsätter uppdateras. Janne kan
   därefter göra ett överenskommet enkelt manuellt funktionstest.
4. Kontrollera ffmpeg, loggflödet till Loki, inga OOM/restartloopar, JVM-minne
   och fortsatt `HEALTH_OK`. Följ stabilitet minst 30 minuter efter uppstart.
5. Git-fas D: återaktivera backup och avsluta underhållsundantaget. **Behåll
   backupjobbet på w5.** Det använder Kubernetes-API/exec/cp och monterar inga
   openHAB-volymer; det kan därför säkerhetskopiera podden på w6. Jobbets
   nedladdning av ARM64-kubectl gör att det inte ska flyttas till w6 oförändrat.
6. Kör ett dokumenterat extra backupjobb efter flytten med unikt arkivnamn,
   så att dagens befintliga fil inte återanvänds av misstag. Verifiera en ny
   tidsstämpel, ZIP-integritet och identisk NAS-checksumma. Kontrollera också
   nästa schemalagda nattbackup innan migreringen slutmarkeras som klar.
7. Behåll migrationsarkiv och snapshots tills Janne godkänt utfallet och
   minst nästa nattbackup har verifierats. Dokumentera senare snapshot-rensning
   som ett separat, avgränsat steg. Ingen automatisk bevakning skapas av planen.

## Återgång

Påbörja återgång vid nya kritiska integrationsfel, upprepade krascher/OOM,
lagringsfel eller om appen inte når godtagbar funktion inom avbrottsfönstret.
Om volymanslutning fastnar: felsök efter cirka fem minuter, fatta återgångsbeslut
efter cirka tio minuter utan framsteg. Återgångstid är inte garanterad vid
kluster-/lagringsfel; forcera aldrig en anslutning för att hålla tidsplanen.

1. Pausa backup/avgränsad remediation och sätt `replicas: 0` via Git. Bekräfta
   att w6-podden är borta och alla fyra volymer har lossats.
2. Återställ selector och openHAB-nodlarm till w5 via Git, fortfarande med
   noll repliker. Multiarch-indexen fungerar även på w5 och kan behållas.
3. Återskapa cache/tmp med samma stoppade underhållsförfarande före återstart
   på ARM. Behåll de senaste konfigurationerna och persistensdata om de är
   oskadade; en vanlig återgång ska inte kasta bort nytillkommen historik.
4. Starta en replika på w5, välj w5:s verkliga LAN-adress
   `192.168.50.21/24` i nätverksinställningarna och verifiera funktion.
   Den tidigare `10.42.2.97/24`-inställningen dokumenteras som referens men
   återinförs inte slentrianmässigt. Återställ externa URL-/callbackändringar
   om sådana gjordes för w6.
5. **Dataåterställning används endast om nödvändigt.** Ta först en kopia av
   läget efter felet, stoppa alla skrivare och återställ då samtliga fyra
   samordnade snapshots eller det verifierade kalla NAS-arkivet. Det förlorar
   ändringar efter återställningspunkten och kräver ett uttryckligt beslut
   utifrån det observerade felet. Gör inte blind `git revert` till en revision
   med `replicas: 1` innan lagrings-/cacheförberedelserna är klara.
6. Återaktivera backup och ordinarie övervakning, kontrollera ny backup,
   dokumentera orsaken och lämna w6 utan openHAB tills ny plan är godkänd.

## Filer och gräns mellan Git och applikationsdata

Föreslagna framtida manifeständringar:

- `clusters/production/apps/openhab/openhab-statefulset.yaml`: fasvis
  replicas, nodeSelector och image-index. Inga ändrade minnes-/Java-gränser.
- `clusters/production/apps/openhab/backup-cronjob.yaml`: tillfällig suspend;
  w5-selector och ARM64-verktyg behålls i denna flytt.
- `clusters/production/apps/monitoring/node-specific-memory-alerts.yaml`:
  endast openHABs två larm får ny nodadress.
- Tillfälligt underhållsjobb och dess GitOps-inkludering: granska före
  genomförande, aktivera först med openHAB stoppat och ta sedan bort.

Snapshots, säkerhetskopior och openHABs UI-/REST-lagrade data är driftdata.
Åtgärder/metod och verifierade resultat dokumenteras i Git; hemligheter och
fullständiga backup-/JSONDB-data ska inte läggas där. Delat minne uppdateras
först när genomförandet är godkänt och resultatet verifierat.

Den historiska regeln `openhab-node-silence.yaml` pekar på `.115` och utgör
inte ett verifierat underhållsskydd. Prometheus-nodens gamla IP i samma
larmområde samt generell modernisering av backup/restore hanteras separat.
Ingen av dessa kringändringar ska fördröja en säker återgång.

## Underlag

- [G10-onboarding och verifiering](new-node-g10.md).
- Liveinventering och backupkontroll ovan; ingen produktion ändrades vid planering.
- [openHABs containerdokumentation](https://www.openhab.org/docs/installation/docker)
  beskriver beständig conf/userdata/addons och hostnät för nätverksintegrationer.
- [openHABs backup/restore-dokumentation](https://www.openhab.org/docs/installation/linux#backup-and-restore)
  samt den faktiskt installerade `/openhab/runtime/bin/backup` användes för att
  kontrollera vad dagens backup omfattar.

## Genomförandelogg 2026-09-29

- 11:13 CEST: samtliga noder Ready, Flux synkroniserat, Ceph HEALTH_OK och
  129 PG active+clean. openHAB fortfarande på w5; inget aktivt backupjobb.
- NAS-kopian av nattens ZIP är 528712689 byte och har exakt samma SHA-256
  som det tidigare integritetstestade podarkivet. Cirka 1,9 TB ledigt på NAS.
- Förberedelse: backup schemaläggning pausas, remediatorns RoleBinding i
  endast openhab får tillfälligt tom subjects-lista. Övriga namespace lämnas
  oförändrade. Ett isolerat förberedelsejobb på w6 startar inte openHAB och
  monterar inga produktionsvolymer.

- 11:20 CEST: x86-förberedelsejobb godkänt (ffmpeg, DNS, MQTT, kamerabrygga,
  NAS). Tunnelns mottagna konfiguration pekar på
  `https://openhab-production.openhab:8443`, inte en nod-IP. Extern åtkomst
  visar ordinarie Cloudflare Access-inloggning; autentiserat sluttest återstår.
- Referensbild säkrad privat: 244 Things (174 ONLINE), 987 Items, 64 regler och
  30 UI-sidor. Backup pausad utan aktivt jobb; remediator kan inte radera poddar
  i openhab under underhållet. Förberedelsemanifest för underhållsjobb
  servervaliderat. Nästa fas stoppar openHAB genom Git/Flux.

- 11:23:42 CEST: StatefulSet=0, ingen openHAB-pod och inga VolumeAttachments
  för dess fyra PV:er. Fyra snapshots `openhab-pre-w6-20260929-112344` skapade
  och verifierade med openHAB stoppat. Ingen tvingad frånkoppling användes.
- Modbus TCP från w6 till 192.168.50.242:502 lyckades vid omkontroll efter
  initialt anslutningsfel. Kontroll av bindingen efter start krävs fortfarande.
- Aktiverar underhållsjobbet på w5 för kall backup; openHAB förblir stoppat.

- 11:32:12 CEST: kallt arkiv av samtliga fyra datavolymer verifierat på NAS:
  `openhab-migration-20260929-112344.tar.gz`, 529851553 byte, SHA-256
  `f62609b0c4ebe0a12a1223ec1a2447ef386ee4687415033f6bb8e9dfa34dc4f1`.
  Gzip och tar-innehåll kontrollerade; gamla rekursiva backupkatalogen exkluderad.
- Cache och tmp tömda först efter ny kontroll av stoppad app, snapshots och
  identisk lokal/NAS-checksumma. Katalogernas 9001:9001/0755 bevarade.
  Konfiguration, JSONDB och persistens oförändrade.
- W6-selector, multiarch-index och openHABs nodlarm förberedda med repliker=0.
  Tar nu bort förberedelse-/underhållsjobben och inväntar lossade volymer.

- 11:37:32 CEST: openHAB-container startad på w6; Promtail startad 11:39:04.
  Alla fyra PV:er anslutna till w6. Vid kontroll 11:43:09 svarar API/UI och
  innehållet är kvar: 244 Things, 987 Items, 64 regler och 30 sidor, inga
  containeromstarter. Vissa integrationer återansluter fortfarande.
- Primary Address ändrad via stödd REST till 192.168.50.168/24; övriga
  nätverksvärden bevarade och ändringen läst tillbaka.
- Aktiverar ett separat backupjobb från den befintliga w5-baserade mallen
  för att verifiera backup av openHAB som nu kör på w6. Ordinarie CronJob
  och remediator-guard återställs efter godkänt resultat.

- 11:49:23 CEST: extra backupjobbet slutfört. Ny ZIP från w6:
  `openhab-backup-26_09_29-11_47_21.zip`, 525304859 byte, SHA-256
  `e5787ee2bdf3d7435f779b96ad210e8667fcbf56081ff7f68385e526fba4a992`.
  ZIP-integritet godkänd i podden och identisk storlek/checksumma på NAS.
  Den ordinarie mallens retention kördes för ZIP-filer; migrationsarkivet
  `.tar.gz` och de fyra snapshots är kvar.
- 11:47 CEST: stickprov av Hue-, Verisure- och SigenStor-historik visar både
  tidigare värden och nya värden efter starten. Alla 64 REST-regler IDLE,
  oförändrat antal Things/Items/sidor. Inga kommandon till fysisk utrustning
  skickades som del av verifieringen.
- 11:56 CEST: MQTT, Modbus/IVT, Remote openHAB-servern och alla fem
  IP Camera-Things ONLINE. ffmpeg 7.1.5-0+deb13u1 installerat och körbart.
  Lynk & Co krävde ny inloggning; Janne genomförde den och både API- och
  fordons-Thing har därefter verifierats ONLINE.
- Kvar att kontrollera: autentiserad extern åtkomst (Cloudflare Access-kod
  uteblev och kodförsöket löpte ut), en Chromecast med anslutningstimeout,
  två Verisure-Things med UNKNOWN samt minst 30 minuters stabil drift.
  Verisure-bryggan är ONLINE. Chromecast-porten svarar varken från m-1
  eller w6, vilket inte ensamt avgör om statusändringen hör ihop med flytten.
- Nästa nattbackup 2026-09-30 återstår. Migrationsarkiv och snapshots behålls
  tills även den är verifierad och Janne godkänt utfallet.

- 11:58 CEST: Loki tar emot aktuella openHAB-loggar och händelser (92 respektive
  1430 rader i de senaste fem minuterna). Chromecast 192.168.50.173:8009 ger
  timeout även från gamla w5 samt m-1; felet är alltså inte begränsat till w6.
- 12:05 CEST: två Verisure-Things visar UNKNOWN, men den berörda rökgivarens
  tre Item-värden är identiska med referensbilden. Ingen färsk uppdatering av
  just dessa värden har därmed bevisats; Verisure-bryggan och övriga sensorer
  fungerar. Inga larm-/enhetskommandon skickades.
- 12:07 CEST: Cloudflare-panelen visar att policyn `Sweden Email` för openhab
  kräver anslutning från Sverige och e-post `janne@k3s.nu`. Inloggningsförsöken
  använde en annan adress, vilket förklarar utebliven kod. Ingen Access-policy,
  tunnel eller DNS ändrades. Janne ombedd prova den redan tillåtna adressen.

- 12:08 CEST: mer än 30 minuters drift sedan 11:37:32, båda containrar Ready
  och noll omstarter. Förberedd återställning av ordinarie backup/remediator
  validerad mot API-servern. Kustomize-bygget lyckas; en full torrkörning utan
  Flux-dekryptering avbryts av befintliga SOPS-dokument, varför just ändrade
  CronJob/RoleBindings också torrkördes separat och godkändes.
- Git-fas D: tar bort det slutförda extra backupjobbet från aktiv GitOps,
  återställer ordinarie CronJob och remediatorns tidigare openhab-behörighet.
  Referensmanifest, migrationsarkiv och snapshots behålls.

- 12:11 CEST: Flux apps/infrastructure/flux-system har tillämpat revision
  `6910346`. CronJob suspend=false, remediatorns delete-pod-behörighet i
  openhab återställd och det extra backupjobbet prunat. Janne bekräftade
  fungerande extern inloggning på openhab.k3s.nu med korrekt e-postadress.
- 12:12 CEST: Janne rapporterade NodeCPUThrottling FIRING 11:47 och RESOLVED
  11:57. Prometheus bekräftar inget aktivt larm. Senaste 5-minuters CPU-medel
  cirka 0,285 kärnor, throttlade perioder cirka 0,183 %. Vid uppstart nådde
  5-minutersandelen cirka 29,1 % (CPU-medel som mest cirka 2,31 kärnor;
  korta toppar kan ändå nå CPU-kvoten). Mönstret är förenligt med tillfällig
  uppstartsbelastning. Regeln larmar på >10 throttlade perioder på fem minuter
  ihållande i fem minuter, inte på en procentsats. Ingen CPU-/minnesgräns
  eller larmregel ändrad för detta.
- Delat minne uppdaterat i befintliga anteckningar om openHAB och K3s.
  Flytten är driftsatt; full slutmarkering väntar på nästa nattbackup.
  Noterade enhetsavvikelser: Chromecast c2f7b2073b timeout och Verisure
  gateway 26DUK7BD/smokeDetector 2AU3W2KC UNKNOWN. Övriga kontroller enligt
  ovan godkända. Bevarade återställningspunkter ska inte städas automatiskt.
