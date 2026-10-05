# CPU-begränsning och Alertmanager 2026-10-05

## Ändring och motiv

Den tidigare `NodeCPUThrottling`-regeln räknade fler än 10 begränsade
CPU-perioder under fem minuter, med `for: 5m`. Det var ett absolut antal,
inte en procentandel. Regeln ersattes med andelen begränsade CFS-perioder
under fem minuter: strikt över 25 % sammanhängande i 15 minuter.
Andelen avser schemaläggningsperioder, inte nodens CPU-användning eller
andelen förlorad CPU-tid.

Namnet `NodeCPUThrottling`, nivån `warning` och identitetslabelarna
`namespace`, `pod`, `container` behölls. Meddelandet är på svenska och visar
uppmätt procent. Båda räknarna använder samma kubelet/cAdvisor-källa;
tomma containrar/poddnamn och `POD` filtreras bort. En nollnämnare eller
saknad räknare ska inte bli ett throttlinglarm. `increase` hanterar
räknaromstarter.

Chartens överlappande standardlarm `CPUThrottlingHigh` inaktiverades med
`defaultRules.disabled.CPUThrottlingHigh: true`. Standardlarmets tröskel
var också 25 % / 15 minuter, men med severity `info`.

Alertmanagers CPU-limit `100m` togs bort. CPU-request `10m`, minnesrequest
`64Mi` och minneslimit `128Mi` behölls. Detta tillåter korta CPU-toppar när
noden har kapacitet. Samma princip används redan för Grafana och Prometheus.
Chartversionen behölls på `kube-prometheus-stack` 55.5.0.

## Validering och utrullning

15 scenarier verifierades med klustrets `promtool` 2.48.1:
exakt 25 %, en incidentlik andel på 23,75 %, över 25 % under 15 minuter,
en kort topp, återgång under tröskeln, noll/saknade räknare,
räknaromstart, separation mellan namespaces/poddar samt bortfiltrerade
containrar och andra mätkällor. Samtliga passerade. Alla nio regler i
`node-resource-alerts.yaml` klarade syntaxkontrollen.

Kör om testerna med Python 3, PyYAML och promtool tillgängliga:

```bash
python3 scripts/test-prometheus-throttling.py
```

För en separat promtool-värd:

```bash
python3 scripts/test-prometheus-throttling.py --export-dir /tmp/throttling-tests
# Kopiera katalogens två YAML-filer till testvärden och kör där:
cd /tmp/throttling-tests
promtool check rules node-resource-alerts.rules.yaml
promtool test rules node-cpu-throttling.test.yaml
```

Helm-rendering före/efter visade att första steget endast tog bort
standardlarmet från chartens PrometheusRule. Andra steget ändrade endast
Alertmanager-resursens CPU-limit. Inga andra renderade objekt ändrades.
Den separata anpassade regeln klarade även API-serverns torrkörning.

Utrullningen genomfördes via Git och Flux i två separata commits:

- `ad00562`: larmregel, borttagen dubblett och tester.
- `24f1cb6`: borttagen CPU-limit för Alertmanager.

Första steget verifierades med frisk, laddad regel i Prometheus och utan
poddbyten eller containeromstarter. Helm-revisionerna blev 49 respektive
50. AI-remediatorns huvudflöde `aiRemMainAgent03` pausades före det andra
steget, med noll pågående/väntande körningar. Aktiveringsstatus och både
publicerad version och utkast registrerades före pausen.

## Driftobservation

Alla tider nedan är UTC den 2026-10-05 (svensk tid är UTC+2).
Alertmanagers enda podd ersattes som följd av resursändringen. Den skapades
07:23:36 och blev Ready 07:23:57, cirka 21 sekunder senare. Schemaläggaren
placerade den på `k3s-w-6`; den föregående podden låg på `k3s-w-1`.
Poddens båda containrar startade utan ytterligare omstarter. En kort paus
i larmleveransen var möjlig under bytet; denna kontroll mäter inte exakt
avbrottstid hos Mattermost.

Stabilitetskontrollen genomfördes 07:24–07:44 UTC. 21 mätomgångar över
20 minuter och 7 sekunder passerade. Slutkontrollen efter återaktivering
av AI-remediatorn genomfördes 07:44:48 UTC:

- Alla sex noder var Ready; Ceph visade HEALTH_OK och 129 active+clean-PG.
- Övriga 90 icke-Job-poddar behöll UID, container-ID och omstartsräknare.
- Alertmanagers två containrar hade noll omstarter efter poddbytet.
- Inga nytillkomna larm eller leveransfel upptäcktes.
- Prometheus hade exakt en throttlingregel, `NodeCPUThrottling`, med
  `for: 15m`, severity `warning` och utvärderingshälsa `ok`.
- Den nya Alertmanager-podden registrerade fem ordinarie webhook-notifieringar
  och noll misslyckade notifieringar. Prometheus använde den nya poddadressen
  och hade noll sändningsfel i den avslutande 20-minuterskontrollen.
  Detta verifierar notifieringsräknarna; visningen i Mattermost testades
  inte separat.
- Alertmanagers uppmätta CPU-förbrukning låg mellan
  0.36 och 0.90 millicores i observationsproverna.
  w-6 låg mellan 9.0 och 9.8 % CPU. Alertmanager använde cirka 20 MiB minne vid slutkontrollen.

AI-remediatorn återaktiverades 07:44:41 UTC med exakt den tidigare
publicerade versionen `339d7f6e-6ad7-4dfe-b2ba-5220eafbeece`.
Utkastets version var oförändrad, och aktiveringsstatusen verifierades på
nytt. Ingen återställning av konfigurationsändringarna behövdes.
Den aktiva HelmRelease-konfigurationen och den anpassade PrometheusRule
jämfördes med Git och stämde överens.

Skyddat kontrollunderlag och tillfälliga renderade manifest finns på Mac:
`/Users/jan.gustafsson/.secrets/k3s-cpu-throttling/20261005T0717Z/`.
Inga hemligheter ingår i denna rapport eller ändringens Git-diff.

## Återställning

Vid problem med Alertmanagers resurser: återställ `24f1cb6` med en separat
`git revert`, pusha och invänta Flux. Det ger tillbaka CPU-limit `100m`
och medför normalt ännu ett poddbyte. Behåll AI-remediatorn pausad tills
klustret är stabilt.

Om själva larmregeln behöver återställas kan `ad00562` återställas separat.
Det återinför både den gamla anpassade regeln och chartens standardregel.
