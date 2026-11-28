# Diagnostik för deldygnsgallring

## Bakgrund

Gallringen 2026-11-27 misslyckades med endast `feature_backup_operation_failed`.
NAS-störningen var en möjlig orsak, men loggen kunde inte bevisa det. Omkörningen
lyckades efter NAS-återställningen. Ordinarie körning 2026-11-28 kl. 03:20 svensk
tid lyckades också innan denna uppgradering.

## Ändring

Endast `analytics-feature-maintenance` uppgraderas till backup-imageversion
`0.7.3-diagnostics1`, pinnad till verifierad digest i `features.json`.
Gallringsgränser, låsning, kontrollsummor och NAS-verifiering är oförändrade.

Varje försök får ett `attempt_id`. JSON-loggen visar operation, arbetssteg,
tidsåtgång och resultat. Fel visar även feltyp, fast felkod, eventuell exitkod,
timeout eller operativsystemets errno samt källfil/funktion/rad. Ett validerat
run-ID och antal redan borttagna versioner följer med om felet inträffar mitt i
gallringen. Samma diagnos sparas i `/operations/features/maintenance-status.json`.
Om statusfilen inte kan skrivas loggas det separat utan att dölja ursprungsfelet.

SSH-fel klassificeras exempelvis som `nas_connection_timeout`,
`nas_authentication_failed`, `nas_host_key_rejected`, `nas_disk_full` eller
`nas_permission_denied`. Okända fel behåller typ och källposition men får en
generell kod. Råa feltexter, kommandon, filnamn, credentials och lokala variabler
skrivs aldrig ut. Bara en begränsad privat stderr-sample används för klassificering.

## Verifiering

- 227 tester passerade i ARM64-byggmiljön, inklusive gallrings-/backupskydd.
- Feltester omfattar SSH-timeout, autentisering, host key, full disk,
  filrättigheter, oväntade fel och misslyckad skrivning av statusfilen.
- Syntetiska hemligheter får inte förekomma i logg eller statusfil.
- Test av riktig gallringsfunktion visar att fel vid NAS-verifieringen lämnar
  körningskatalogerna orörda.

Byggunderlag och verifieringsresultat finns i Analytics-arbetsytans
`work/maintenance-logging-2026-11-28/`. Feltestet använder isolerade temporära
filer och simulerad transport; det orsakar inget produktionsavbrott.

## Felsökning och återställning

Läs jobbets containerlogg och följ `attempt_id`, `stage`, `error_code` och
`source`. Statusfilen kan läsas via monitor-podden under
`/feature-operations/features/maintenance-status.json` även efter att jobbet
städats bort. Okända fel kräver fortsatt felsökning på angiven källrad; slå inte
på generell utskrift av credentials eller råa subprocess-fel.

Återställ vid behov bara gallringsjobbets image-digest till föregående version
genom Git. Undertryck inte larmet och ändra inte backupbevisen manuellt.
