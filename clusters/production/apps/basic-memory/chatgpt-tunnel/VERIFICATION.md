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

## Återstår före klart

- Slutligt användargodkännande av åtkomstkopplingen i webbläsaren.
- Verifiera personlig ChatGPT-arbetsyta och tunnelns faktiska tilldelningar.
- Skapa tunnel och begränsad runtime-nyckel, lagra med SOPS, aktivera via Flux.
- Faktisk Ready-status och verktygsupptäckt i ChatGPT.
- Läsanrop från ChatGPT och Voice-test på användarens avsedda enhet.
- Kontroll av nätverksisolering och offentlig nätverksgräns efter aktivering.

Inga produktionsresurser eller minnesanteckningar ändrades under förberedelsen.
