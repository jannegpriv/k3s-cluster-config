# Privat ChatGPT-anslutning till Basic Memory

## Status 2026-09-27

Tunnel och begränsad runtime-nyckel har skapats efter Jannes godkännande.
Tunnel-ID: `tunnel_6ab9098ae97c81919f35baff12de6513`.
Nyckeln väntar på säker lokal inmatning och kryptering. Den här katalogen ingår
ännu inte i Basic Memorys överordnade `kustomization.yaml` och ingen ny
nätverksåtkomst har öppnats i klustret.

OpenAI Secure MCP Tunnel ansluter utgående från k3s till OpenAI. Basic Memory
behåller sin privata adress, sin befintliga inloggning för lokala klienter och
sin befintliga offentliga nätverksgräns. Ingen publik DNS-post, Cloudflare-route
eller ny ingress behövs.

## Nästa steg på Macen

Öppna Terminal och kör följande kommando. När programmet frågar efter nyckeln,
klicka **Copy** på den öppna OpenAI-sidan som visar den nya tunnelnyckeln.
Klistra in i Terminal och tryck Enter. Inmatningen visas inte. Nyckeln ska inte
klistras in i chatten. Skriv **klart** i chatten när krypteringen bekräftats.

```bash
python3 /Users/jan.gustafsson/git/k3s-basic-memory-chatgpt/clusters/production/apps/basic-memory/scripts/prepare-chatgpt-tunnel-secret.py --tunnel-id tunnel_6ab9098ae97c81919f35baff12de6513
```

## Åtkomst: endast Janne

- Platform-organisation: `Personal`, `org-Ij9Q17ytubRQMo7EVcVMSvv5`.
- Janne var ensam medlem och ägare vid kontroll i Platform 2026-09-27.
- Kontots tillgängliga ChatGPT-arbetsyta:
  `f60bc182-7ab7-4639-9cba-54b9870c3d90`. Kontrollera kopplingen innan aktivering.
- Tunneln ska endast kopplas till dessa två kontexter. Ingen delning eller
  publicering av pluginen. Inga andra medlemmar eller tunnelroller får tilldelas.
- En separat **Restricted** runtime-nyckel med enbart **Tunnels Read + Use**.
  Ingen administratörsnyckel och inga rättigheter till modeller eller andra API:er.
- Tunnelnyckelns Read + Use begränsar transportbehörigheten. Basic Memorys
  läs- och skrivverktyg finns kvar; Janne har uttryckligen begärt skrivstöd i Voice.
- ChatGPT-anslutningen använder **Tunnel**. **No authentication** i appformuläret
  betyder att MCP inte har ett ytterligare OAuth-lager; OpenAI kontrollerar
  användarens tunnelbehörighet. Det skapar ingen anonym publik MCP-adress.
- Åtkomstgränsen följer Platform- och ChatGPT-medlemskap. Om någon annan läggs
  till i organisationen eller arbetsytan måste behörigheterna granskas innan dess.

Kubernetes begränsar tunnelklienten till DNS, Basic Memorys port 8000 och utgående
HTTPS till publika adresser. Den saknar Service, ingress och Kubernetes-token.
All inkommande podtrafik nekas; kubelets hälsokontroller fungerar fortfarande.
Administrationsgränssnittet är begränsat till loopback. Runtime-nyckeln monteras
som fil och skrivs endast krypterad med SOPS i Git.

## Aktivering

1. Skapa `Basic Memory – Janne privat` i Platform Tunnels med ovanstående
   organisation och verifierad personlig ChatGPT-arbetsyta. Granska tunnelns
   tilldelningar så att ingen annan får användarrollen.
2. Skapa den begränsade runtime-nyckeln. Ange inte nyckeln i chatt eller Git.
   Kör `python3 ../scripts/prepare-chatgpt-tunnel-secret.py` från denna katalog
   och klistra in nyckeln i den dolda terminalinmatningen.
3. Kontrollera tunnelns organisations- och arbetsyte-ID med `tunnel-client admin
   --json tunnels get <tunnel-id>` och runtime-nyckeln via fil eller miljöreferens.
4. Lägg `credentials.secret.sops.yaml` till denna katalogs `resources` och
   `chatgpt-tunnel` till överordnad `kustomization.yaml`. Validera, committa och
   låt Flux driftsätta enligt GitOps-flödet.
5. Kontrollera att podden är Ready och att `/readyz` svarar 200. Skapa sedan en
   personlig ChatGPT-plugin med Tunnel-ID och upptäck verktygen.
6. Testa ett läsanrop från ChatGPT. Testa Voice separat på den avsedda enheten.
   Tillgängligt formulär och fungerande MCP innebär inte att privat pluginåtkomst
   i mobilens Voice har verifierats.
7. Kör befintligt `scripts/check-public-boundary.py` från ett oberoende publikt
   nätverk. Kontrollera även att en obehörig pod inte kan nå Basic Memory eller
   tunnelns administrationsport.

Image är OpenAI:s officiella ARM64-kompatibla `v0.0.15`, låst till manifestets
SHA-256. Kontrollera [senaste release](https://github.com/openai/tunnel-client/releases/latest)
vid uppgraderingar och uppdatera tagg och digest tillsammans.

## Återkalla åtkomst

Koppla bort ChatGPT-pluginen, återkalla runtime-nyckeln och ta bort tunneln i
Platform. Ta bort `chatgpt-tunnel` från överordnad Kustomization genom GitOps;
Flux tar då bort tunnelklienten och dess särskilda nätverksregler. Den vanliga
Basic Memory-anslutningen på Macen fortsätter fungera.

## Källor

- [OpenAI Secure MCP Tunnel](https://developers.openai.com/api/docs/guides/secure-mcp-tunnels)
- [Tunnelbehörigheter och begränsade nycklar](https://github.com/openai/tunnel-client/blob/v0.0.15/docs/permissions.md)
- [Klientkonfiguration](https://github.com/openai/tunnel-client/blob/v0.0.15/docs/configuration.md)
- [ChatGPT Developer Mode och plan-/mobilbegränsningar](https://help.openai.com/en/articles/12584461-developer-mode-and-mcp-apps-in-chatgpt)
