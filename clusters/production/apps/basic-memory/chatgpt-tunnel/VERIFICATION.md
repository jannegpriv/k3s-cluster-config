# Verifiering 2026-09-27

## Genomfört

- Inloggat Platform-konto visar organisationen Personal med Janne som ensam
  medlem och Owner. Tunnelhantering och ChatGPTs Tunnel-formulär är tillgängliga.
- Officiell image `ghcr.io/openai/tunnel-client:v0.0.15` lästes från registret.
  Digest låstes i manifestet och Linux ARM64 finns i image-indexet.
- `kubectl kustomize` och `kubectl apply --dry-run=server` mot befintligt k3s
  godkände ConfigMap, Deployment och båda NetworkPolicy-resurserna.
- Klientens `doctor` kunde läsa konfigurationen med en tillfällig testnyckel
  och lokala testadresser. Profil, tunnel-ID-format och nyckelreferens godkändes.
  Nätverkskontrollerna misslyckades som väntat mot den stängda testporten.
  Macens port 8080 var upptagen; ingen tunnelprocess startades.
- Nyckelskriptet provades med en slumpad testnyckel i en temporär katalog.
  SOPS rapporterade giltig krypterad fil, båda värdena var krypterade, filens
  rättigheter var 0600 och testnyckeln förekom inte i den sparade filen.
- Basic Memorys fem befintliga backuptester godkändes.
- Janne godkände aktiveringen i chatten. Tunneln skapades med enbart den
  personliga organisationen och den valda ChatGPT-arbetsytan.
- Runtime-nyckeln skapades som Restricted. Bekräftelsesidan visade exakt två
  rättigheter: Tunnels Read och Use. Alla andra behörighetsområden visade None.
  Nyckeln har inte skrivits i chatt, loggar eller okrypterade filer.
- Janne förde in nyckeln i den dolda lokala terminalinmatningen. Den resulterande
  filen kontrollerades med SOPS och innehåller krypterade värden för både
  `api-key` och `tunnel-id`.
- Hela Basic Memory-konfigurationen renderades med den aktiverade underkatalogen.
  Klustrets servervalidering godkände alla fem tunnelresurser; hemliga värden
  ersattes med testvärden under denna dry run.
- PR #5 godkändes av konfigurationskontroll, automatisk kodgranskning och
  offentlig nätverkskontroll. Flux tog in ändringen från main.
- Tunnelns metadata lästes med runtime-nyckeln i klustret. Exakt den förväntade
  organisationen och ChatGPT-arbetsytan returnerades, utan andra kontexter.
  Anrop till tunnelmetadata utan inloggning nekades med HTTP 401.
- Klientens `doctor` godkände Basic Memory-anslutningen och dess avsaknad av
  separat OAuth-lager. Första podstarten hann före nätverksreglerna och blev
  därför inte Ready. `startup_wait_timeout: 60s` lades till enligt klientens
  dokumentation för att vänta in anslutningen före den första upptäckten.
- Efter ändringen blev Deployment Ready (1/1), utan omstarter, och `/readyz`
  svarade `ready`. CI för ändringen godkändes.
- En tillfällig obehörig pod kunde varken ansluta till Basic Memorys port 8000
  eller tunnelklientens administrationsport 8080. Testpodden togs bort efteråt.
- Basic Memory skapades och anslöts i ChatGPT. Pluginen visas under Installed:
  `https://chatgpt.com/plugins/plugin_asdk_app_6ab90ce7a1bc81919e48a57fb95414e8`.
- En vanlig ChatGPT-textchatt kunde läsa minneskonventionerna samt söka och
  läsa relevanta anteckningar via den nya pluginen. Skrivverktygen upptäcktes.
- På Jannes uttryckliga begäran uppdaterade samma ChatGPT-anslutning den
  befintliga anteckningen **AI-minne - drift i K3s** med anslutningens lösning,
  åtkomstgräns och genomförda kontroller. Skrivning och återläsning lyckades.
  En oberoende läsning genom den befintliga MCP-anslutningen bekräftade att
  tillägget sparats och att den tidigare texten fanns kvar. Inga hemligheter
  ingår i anteckningen.

## Återstående kontroll

- Praktiskt Voice-test på användarens avsedda enhet.
  Fungerande läsning och skrivning i textchatten verifierar inte Voice.

Efter Jannes godkännande aktiverades produktionsresurserna via GitOps och
minnesanteckningen uppdaterades via ChatGPT-pluginen.
