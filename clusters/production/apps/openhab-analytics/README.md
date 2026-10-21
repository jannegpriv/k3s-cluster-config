# OpenHAB Analytics – avgränsat Landet-prov

Aktiverat och verifierat för avgränsat prov 2026-10-20. Den befintliga Mac-piloten, dess datakatalog och OpenAI-tunnel fortsätter oförändrat.

## Verifierat driftläge 2026-10-20

- Flux har aktiverat gatewayen via Git. Båda containrarna är Ready på `k3s-w-1`; egen PVC är Bound, 100 MiB.
- Tailscale-enheten `openhab-analytics-landet` har egen adress `100.66.87.41` och endast `tag:openhab-analytics`. Backend är Running och enheten Online. Status anger ingen nyckelutgång (`KeyExpiry: null`), i enlighet med registreringsformulärets inställning för taggade enheter.
- Engångsjobbet `analytics-landet-probe-20261017` är Complete, 1/1. Det hämtade nio historikkällor med totalt 20 godkända GET-anrop. Energiräknaren förblev primär och källavvikelsen mot effektintegralen rapporterades.
- Gatewayen avvisade POST med 405 och ett otillåtet item med 403. Ingen skrivning skickades till openHAB.
- Gatewayen lämnas igång för fortsatt arbete. Det slutförda jobbet har ingen tidsschemaläggning. Inget MCP-, tunnel-, NAS- eller dygnsinsamlingsjobb har aktiverats här.
- Privat verifieringsrapport finns i Analytics-arbetsytan under `private-data/landet-identity-probe-20261020/`. Identitet över poddomstart, privat registry och NAS-återläsning ingår inte i detta genomförda prov.

Detta paket omfattar en egen Tailscale-identitet, en gateway som endast vidarebefordrar godkända GET-anrop till `192.168.1.86:8080`, och ett engångsjobb som läser nio historikkällor för 2026-10-17. Husets primära energikälla är `SigenStor_Total_Load`.

Gatewayen har egen 100 MiB RWO-volym i `rook-ceph-block` för Tailscale-tillstånd. Den kör utan hostNetwork, TUN, Linux capabilities eller Kubernetes API-token. Utgående trafik tillåts till DNS och publik HTTPS för Tailscales kontrollplan och reläer. SOCKS-lyssnaren är endast tillgänglig på loopback i gatewaypodden. Provet kan bara nå gatewayens HTTP-port.

De offentliga Python- och Tailscale-avbildningarna är låsta till digest. Applikationskoden monteras skrivskyddad från ConfigMap och dess hash finns på poddarna. Detta verifierar nätväg och läsning, inte distributionen via det framtida privata avbildningsregistret.

## Hemligheter och policy

`tailscale-secret.enc.yaml` innehåller endast gatewayens registreringsnyckel. `landet-secret.enc.yaml` innehåller endast läsprovets openHAB-token. Båda krypteras med befintlig SOPS/PGP-nyckel och monteras i olika poddar. Inga klartextnycklar ska skrivas i Git, kommandorader eller loggar.

Tailscale-taggen `tag:openhab-analytics` får endast nå `192.168.1.86` på TCP 8080. Policyn sparades efter Jannes uttryckliga godkännande 2026-10-20. Den tidigare generella källregeln ersattes med befintliga medlemsenheter och de befintliga routade näten `192.168.50.0/24` samt `192.168.1.0/24`. SSH-regeln bevarades. Policyn har positiva och negativa åtkomsttester. Kamerabryggans läsning från Landet kontrollerades efter ändringen.

Engångsnyckeln gäller en dag för registrering. Den tidsgränsen avslutar inte en redan registrerad enhets åtkomst. Enhetens tillstånd bevaras på egen PVC; dess nyckelutgång måste kontrolleras efter registreringen.

## Start och kontroll

1. Granska manifests och krypterade Secrets. Lägg till denna katalog i övergripande apps-kustomization och gör commit/push för Flux.
2. Kontrollera Bound PVC, gatewayens båda containrar och readiness. Verifiera Tailscale-namn, egen IP och endast Analytics-taggen.
3. Ändra engångsjobbets `spec.suspend` till `false` genom Git. Jobbet avvisningstestar endast gatewayen; inga skrivningar skickas till openHAB. Därefter körs den befintliga GET-insamlaren.
4. Spara jobbets verifieringsresultat lokalt. Kontrollera räknarens primärroll, källornas kvalitet och skillnaden mot effektintegralen. Använd 13,8 kWh från tidigare mätning som jämförelse, inte som ett påtvingat svar.

Inga CronJobs, MCP-servrar, OpenAI-tunnlar eller NAS-backupjobb ingår. Inga pilotdata publiceras eller ersätts.

## Utökning 2026-10-21: beständig lagring

Janne har godkänt genomförandet av driftsättningsplanens punkt 1–6, med bevarad
Mac-pilot som återställningsväg och utan ändringar i openHAB.

`storage.json` lägger till `analytics-data` (2 GiB) och `analytics-operations`
(100 MiB) på `rook-ceph-block`. Båda är verifierat Bound. Samtliga tre PVC:er
har `kustomize.toolkit.fluxcd.io/prune: disabled`, så att en återställning av
applikationsmanifest inte automatiskt tar bort data eller Tailscale-identiteten.

`storage-write-job.json` har skrivit och fsync:at provdata i båda volymerna som
UID 10001. Efter att skrivjobbet avslutats har `storage-read-job.json` monterat
volymerna skrivskyddat, verifierat samma checksumma/ägare och fått skrivförsök
nekade. Båda jobben är Complete 1/1. De har ingen nätåtkomst eller hemligheter.

Datakatalogen är ännu inte importerad. Registry, NAS-åtkomst, driftlarm,
produktionsnycklar och tunnelövergång återstår att aktivera. Mac-piloten är kvar.

## Avbryt eller återställ

Stoppa gatewayen genom att sätta dess replicas till 0 i Git. Avlägsna eller suspendera provjobbet via Git vid behov. Bevara PVC:n så att samma identitet kan återanvändas; ta inte bort den eller Tailscale-enheten rutinmässigt. Vid enbart nätfel i provet ska den fungerande Mac-piloten fortsätta.

En full återgång till den tidigare Tailscale-policyn kräver separat granskning: den skulle ge även en kvarvarande Analytics-enhet obegränsad nätåtkomst. Stoppa och återkalla den nya enheten innan en sådan återgång. Ursprunglig policy och föreslagen policy finns i Analytics-arbetsytans privata kontrollunderlag daterat 2026-10-20.
