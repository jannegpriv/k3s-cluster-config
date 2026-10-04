# K3s-certifikatförnyelse 2026-10-04

## Metod och förutsättningar

Underhållet omfattar k3s-m-1 (192.168.50.75) och k3s-w-4
(192.168.50.243), K3s v1.34.3+k3s1. Certifikaten som varnade löpte ut
2027-01-10. Endast systemd-tjänsten startas om, först `k3s` på m-1,
sedan `k3s-agent` på w-4. Ingen drain, cordon, uncordon, reboot,
killall, CA-rotation eller applikationsuppgradering ingår.

Båda tjänsterna verifierades med `KillMode=process`, utan `ExecStop` eller
`ExecStopPost`. Sex noder var Ready, 91 körande poddar var friska och Ceph
visade HEALTH_OK med 129 active+clean-PG. Cephs monitorer och manager har
5 sekunders tolerans efter att en unreachable-taint har lagts på noden;
därför jämförs även poddarnas UID, container-ID och omstartsräknare.

## Verktyg och kontroller

`scripts/safe-k3s-restart.sh` har ett separat `--service-only`-läge som
delegerar till `k3s-service-restart.py`. Det ursprungliga drain-läget används
inte här. Flaggor utan uttryckligt service-only-läge avvisas.

Kör från m-1 med fungerande kubectl och SSH till arbetarnoden:

Exemplen utgår från en kopia av repositoryts skript. Vid denna körning
kopierades de två omstartsfilerna till
`/home/janne/k3s-certificate-maintenance-20261004T072047Z/` på m-1.

```bash
export KUBECONFIG=/home/janne/.kube/config
bash scripts/safe-k3s-restart.sh k3s-m-1 master --service-only \
  --expected-machine-id 3caa80b4b95e4f0b8b3824273bbd6443 --dry-run
bash scripts/safe-k3s-restart.sh k3s-w-4 worker --service-only \
  --expected-machine-id c7b0d03e0da640c996578c3aa724f29a --dry-run
```

Ta bort endast `--dry-run` för den godkända omstarten, en nod i taget.
Skriptet kontrollerar nodroll, maskinidentitet, sudo, stoppbeteende, API och
nodstatus innan det gör en ändring. Efteråt krävs ändrad tjänstestarttid,
aktiv tjänst, ett nytt nodlivstecken efter att den nya processen upptäckts,
Ready och fungerande API. Maximal återhämtningstid är 180 sekunder.
Fel stoppar rutinen utan automatisk omstart, evakuering eller återställning.
Backup, applikationskontroller och pausen av AI-remediatorn är separata
obligatoriska steg i körningen, inte garantier som skriptet ensamt ger.

`scripts/k3s-maintenance-backup.py master|worker DESTINATION` körs som root
på respektive nod. Destinationen måste vara ny. Serverns SQLite-databas
kopieras via en fixerad WAL-läsögonblicksbild så att skrivningar kan fortsätta
utan att starta om kopieringen. Kontrollen kräver WAL-läge, integritet `ok`,
stängda databasanslutningar och en fristående backup. Tillåt utrymme för
växande WAL under läsningen. Verktyget sparar också token, TLS, relevanta
agentfiler, systemd-konfiguration och Jannes kubeconfig, med privata
rättigheter och SHA-256-manifest. Kopiera off-node och kontrollera manifestet
innan omstart; en backup som inte är klar och verifierad inom 30 minuter
tillåter inte fortsatt underhåll. Detta är inte en backup av applikationsdata.

Tester:

```bash
python3 -m unittest discover -s scripts -p 'test_k3s_*.py' -v
bash -n scripts/safe-k3s-restart.sh
git diff --check
```

17 tester täcker bland annat fel identitet/roll, stoppinställningar,
otillgängligt API, gammal Ready/lease, torrkörning, timeout utan upprepad
omstart och en riktig SQLite-backup med parallella skrivningar.

## Backup och observationsunderlag

Verifierad off-node-backup och privat kontrollunderlag:

`/Users/jan.gustafsson/.secrets/k3s-certificate-renewal/20261004T072047Z/`

Nodernas root-skyddade backupkatalog:

`/var/backups/k3s-certificate-renewal/20261004T072047Z-snapshot/`

Serverdatabasen är cirka 6,7 GB. Integritetskontroll och SHA-256 för både
databas och konfigurationsarkiv godkändes före första omstarten. Den första
inkrementella kopieringen avbröts utan att röra K3s eftersom skrivningar
fördröjde kopieringen; den ersattes av en konsekvent WAL-ögonblicksbild.
Den ofullständiga första kopian togs bort efter verifieringen.
Katalogen med suffix `-snapshot` är den godkända backupen.

Hälsokontroller omfattar API, noder, samtliga körande icke-Job-poddar, Ceph,
Authelia, Mattermost, Grafana, Prometheus, Basic Memory och båda
PostgreSQL-tjänsterna. Basic Memory kontrolleras inifrån podden eftersom
dess NetworkPolicy avvisar direktanslutning från nodvärden.

AI-remediatorns huvudflöde `aiRemMainAgent03` pausas via n8n:s API utan
omstart av n8n. Före underhållet var det aktivt, utan pågående/väntande
körningar, med publicerad version och utkast
`339d7f6e-6ad7-4dfe-b2ba-5220eafbeece`. Efter godkänd slutkontroll
återaktiverades exakt samma publicerade version. Utkastet är oförändrat.
Aktiveringen och klusterhälsan verifierades på nytt 07:51 UTC.

## Resultat och versionsspecifik avvikelse

m-1 återhämtade sig efter cirka 17 sekunder. Förnyade servercertifikat
gäller till 2027-10-04 07:28:35 UTC och agentcertifikat på m-1 till
07:28:36–37 UTC samma dag. Ett nytt `CertificateExpirationOK`-event kom
2026-10-04 07:28:41 UTC.

w-4 återhämtade sig efter cirka 19 sekunder. Alla fyra tidigare varnande
agentcertifikat gäller till 2027-10-04 cirka 07:34:28 UTC. Deras publika
nycklar är oförändrade. Båda noderna klarade `k3s certificate check` utan
varningar efter omstarterna. Totalt förnyades de 14 certifikat som varnade.
Ett nytt `CertificateExpirationOK`-event kom för w-4
2026-10-04 07:34:29 UTC.

En separat API-kontroll från Mac observerade sex misslyckade anrop under
m-1-omstarten, 07:28:32–07:28:38 UTC. Närmaste lyckade kontroller före och
efter avbrottet låg 11,1 sekunder från varandra; tjänstens fullständiga
återhämtning med nytt nodlivstecken tog 17 sekunder. Inga certifikat- eller
TLS-fel hittades i tjänsternas journaler vid den slutliga efterkontrollen.

Antagandet att samtliga privata nycklar behålls gällde inte denna
serverversion. Tio servercertifikat och deras nycklar förnyades tillsammans.
Jämförelse med backupen visar att CA-certifikat, CA-nycklar,
ServiceAccount-signering och övriga kontrollerade nycklar är oförändrade.
Källkoden för v1.34.3+k3s1 sätter `regen` när ett servercertifikat behöver
förnyas och skickar flaggan till nyckelgenereringen. Därför måste kopierade
kubeconfigs få både nytt klientcertifikat och matchande nyckel.
Jannes `/home/janne/.kube/config` uppdaterades atomiskt med dessa två fält;
anslutningsadresser, sammanhang, övrigt innehåll, ägare och rättigheter
bevarades. API-åtkomst verifierades därefter. Macen saknade standardkubeconfig
och inga kopierade kubeconfigs hittades i root/Jannes hemkataloger på w-4.

Fem stabila minuter efter m-1 följdes av mer än 15 minuters observation
efter w-4, med slutkontroll 07:50:02 UTC. Samtliga 91 körande
icke-Job-poddar behöll UID, container-ID och omstartsräknare. Alla sex
noder var Ready i kontrollerna, Ceph var HEALTH_OK och alla
applikationskontroller godkändes. Inga nya Prometheus-larm tillkom under
underhållet. Historiska certifikatvarningar finns kvar med oförändrade
gamla tidsstämplar; båda noderna har nyare CertificateExpirationOK-events.

Under observationen gav den första kontrollen ett falskt stopp när en PG
gick från `active+clean` till `active+clean+scrubbing+deep`. Ceph var hela
tiden HEALTH_OK, alla OSD:er var up/in och inga poddar ändrades. Det var
normal integritetskontroll, inte en lagringsstörning. Kontrollen korrigerades
till att kräva active och clean men tillåta tilläggen scrubbing/deep;
degraded, inconsistent och remapped avvisas fortfarande. Samtliga sparade
ögonblicksbilder kontrollerades igen och observationsperioden fortsatte.
Inga Ceph-inställningar ändrades.

## Källor

- [K3s certifikathantering](https://docs.k3s.io/cli/certificate)
- [Stopp av K3s och containerbeteende](https://docs.k3s.io/upgrades/killall)
- [Backup och obligatorisk server-token](https://docs.k3s.io/datastore/backup-restore)
- [Installerad versions förnyelsekod](https://github.com/k3s-io/k3s/blob/v1.34.3%2Bk3s1/pkg/daemons/control/deps/deps.go#L580-L621)
- [Cephs PG-tillstånd](https://docs.ceph.com/en/reef/rados/operations/pg-states/)
