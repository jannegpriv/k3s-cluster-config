# Mer minnesmarginal för openHAB, 2026-10-03

Janne godkände att höja openHABs containerlimit från **4Gi till 6Gi** och
minnesrequest från **2000Mi till 4Gi**. `-Xmx1500m`, CPU-gränser, image-digests,
nodval och volymer behålls. Ändringen gäller containern `openhab514` i
`openhab/openhab-production` på `k3s-w-6`.

Före ändringen var working set cirka 3,1 GiB under senaste dygnet.
Totalanvändning inklusive filcache nådde nära 4Gi, med gränsträffar men inga
cgroup-OOM eller OOM-kills. Noden hade cirka 9,7 GiB tillgängligt minne.
Höjningen ger större marginal för hela containern; större Java-heap ingår inte.

## Kontroller före ändringen

- Flux synkroniserat till `d021daf`, Ceph `HEALTH_OK`, w6 utan tryckhändelser.
- openHAB och Promtail Ready, noll omstarter sedan flytten 2026-09-29.
- Referensbild: 244 Things (188 ONLINE, 55 OFFLINE, 1 UNINITIALIZED),
  987 Items, 64 regler och 30 UI-sidor. Endast läsande REST-anrop.
- Inget aktivt backupjobb. Nattens jobb slutfört 2026-10-03.
- `/openhab/userdata/backup/openhab-backup-26_10_03-02_00_08.zip`:
  527914981 byte, ZIP-integritet godkänd, SHA-256
  `a2e81e9ef49be2c5271c344007b05036f63c99fa1008a2fd5b15e10ee6a3369f`.
  Kontrollen läste arkivet i podden; NAS-kopian är inte separat läst tillbaka.
- Manifesten godkända av Kubernetes server-dry-run; `git diff --check` utan fel.

## Genomförande

Commit `97ebd22` ändrar StatefulSet-resurserna och pausar tillfälligt
remediatorns skrivåtkomst till endast namespace openhab. Flux har applicerat
commiten och StatefulSet genomförde en vanlig RollingUpdate med befintlig
300 sekunders termination grace period. Inga appdata eller cachefiler raderas.

Den gamla podden avslutades efter den konfigurerade grace-perioden. Den nya
skapades 16:54:47 Europe/Stockholm; openHAB-containern startade 16:54:54 och
StatefulSet-uppdateringen var klar 16:56:31. Ingen manuell tvångsradering
användes. Uppstarten installerade ffmpeg via den befintliga postStart-hooken.

## Efterkontroll

Kontrollerat 2026-10-03 från cirka 17:00 Europe/Stockholm:

- Ny pod på w6 med 6Gi limit och 4Gi request. Faktisk cgroup `memory.max`
  är 6442450944 byte; Java-processen använder fortfarande `-Xmx1500m`.
- Båda containrar Ready, inga oplanerade omstarter, inga cgroup-OOM/OOM-kills
  eller nya gränsträffar. Working set cirka 2370Mi efter uppstart; det är en
  kort observation, inte en garanti för framtida toppar.
- REST svarar. 244 Things, 987 Items, 64 regler och 30 sidor bevarade.
  Alla regler IDLE. MQTT, Modbus/IVT, Remote openHAB, IP Camera-Things, Lynk & Co
  och Yamaha återanslutna. ffmpeg 7.1.5 finns installerat.
- Två Verisure-Things som var ONLINE före omstarten visar UNKNOWN:
  gateway `26DUK7BD` och smokeDetector `2AU3W2KC`. Bryggan är ONLINE;
  loggen varnar om deviceId. Samma två avvikelser noterades vid flytten
  2026-09-29. Det är en kvarstående integrationsuppföljning; inget belägg
  för att större minnesgränser orsakar den. Inga fysiska enheter har styrts
  och ingen integrationskonfiguration har ändrats under denna kontroll.
- Netatmo-kontobryggan är ONLINE, men vid cirka 17:03 är tre underordnade
  bryggor UNKNOWN och nio barn-Things OFFLINE/BRIDGE_OFFLINE. De var ONLINE
  före omstarten. Väderstationerna pollar var 600:e sekund. Inga Netatmo-
  WARN/ERROR i den kontrollerade loggen. Eventloggen visar att de först
  återanslöt efter podduppstarten och att bindningen sedan startades om
  17:00:03 av den befintliga regeln ”Netatmo Account bridge offline”
  (4f3191b8f3). Regeln har trigger varje hel timme. Ingen sådan regel
  ändrades i detta uppdrag. Samma avvikelse kvar 17:10:44, mer än ett
  600-sekundersintervall efter bindningens omstart. Exakt orsak till
  utebliven återanslutning är inte fastställd; separat uppföljning behövs.
- TP-Link hs110:15502C växlar ONLINE/OFFLINE med COMMUNICATION_ERROR.
  Vid 17:10:44 är totalt 173 Things ONLINE, 65 OFFLINE, 5 UNKNOWN och
  1 UNINITIALIZED (före ändringen 188/55/0/1). Alla 244 Things finns kvar;
  samtliga integrationer ska inte beskrivas som felfria.
- Ceph fortsatt `HEALTH_OK`. Ordinarie backup oförändrad och aktiv.
- CPU-throttling-regeln var tillfälligt pending under uppstarten. Vid
  kontroll 17:05 fanns inget aktivt openHAB-larm. Gränser och larmregler
  har inte ändrats.

Ordinarie remediation återställd via commit `49c3d8e`. Flux apps Ready
med denna revision 17:04; rätt RoleBinding-subject finns och
`kubectl auth can-i delete pods` för automation/ai-remediator i openhab
ger yes. Poddens UID är samma efter behörighetsåterställningen.
Samtliga sex noder Ready och Ceph HEALTH_OK vid kontroll 17:05.

## Återgång

Vid ett fel orsakat av ändringen: återställ endast minneslimit till 4Gi,
request till 2000Mi och ändringsannoteringen i StatefulSet genom en ny
Git-commit och Flux. Behåll remediatorn pausad tills openHABs REST/API och
integrationer har kontrollerats. Resursändringen migrerar inte appdata.
Behåll befintliga migrationsarkiv och snapshots enligt migrationsplanen.
