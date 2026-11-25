# Rättelse av nattlig feature-insamling, 2026-11-25

## Verifierad grundorsak

Den aktiva feature-katalogen rymmer 31 datum inklusive dagens deldygn.
`target_day` pekar på förrgår före 04.15 och på gårdagen därefter.
Det gamla återhämtningsurvalet började vid `target_day - 29 dagar`.
Före 04.15 hamnade därför ett datum utanför de 31 datum som publiceringen
behåller. När datumet lagts tillbaka gallrade `publish()` omedelbart bort det
och anropade sedan `checked()` för samma datum: `KeyError`.

Det förklarar både första felet 00.22 (efter att 00.07 har publicerat dagens
datum) och att felet försvinner efter 04.15. Detta är inte belägg för att
`insufficient_data` eller vintertidsomställningen orsakar publiceringsfelet.

Kontroller i klustret den 25 november:

- Den faktiska insamlarkoden matchade det felande datumurvalet.
- Den aktiva katalogen innehöll 31 datum, 26 oktober–25 november.
- 22–25 oktober hade publiceringskvitton och kvarvarande katalogfiler i arkivet.
  De är gallrade ur det aktiva indexet, inte permanent förlorade dygn.
- Den misslyckade körningen `d47151c6cc81480d9a1c3ad422678a3c` gick att läsa
  med `Catalog`, trots analysens kvalitetsvarningar.
- En lokal reproduktion med syntetiskt 31-dagarsindex gav exakt
  `KeyError: '2026-10-25'` i `feature_store.checked`.

Det ursprungliga felets första datum har inte fastställts. Rapportens nätter
23–25 november stöds av den beskrivna kataloggränsen; ingen äldre logghistorik
har här verifierats.

## Ändring

Insamlingens äldsta tillåtna datum begränsas även av
`today - (MAX_DAYS - 1)`. Dagens insamling prioriteras fortfarande och högst två
avslutade dygn återhämtas per körning. Gårdagen får fortfarande stängas först
04.15. Arkiv, indexformat, upplösningskrav, kvalitetsvarningar och larmgränser
ändras inte. Inga openHAB-inställningar ändras.

Felstatus får säkra fält för `stage`, `date` och `error_type`.
Undantagstext, credentials, URL:er och mätvärden loggas inte i dessa fält.

Källpatch: `../clusters/production/apps/openhab-analytics/feature-retention-0.7.2.patch`.
Endast huvudcontainern i CronJob `analytics-collect-features` får den nya imagen
`openhab-analytics-collector:0.7.2-retention1`, låst med digest i `features.json`.
Övriga insamlare, backup, monitor och MCP-tunnel behåller sina image-digests.

## Tester och verifiering

- Nytt regressionstest bygger en full katalog genom faktiska testinsamlingar
  mot en lokal låtsas-openHAB, inklusive 25-timmarsdygnet den 25 oktober.
- Gamla koden misslyckas exakt vid 25 november 00.22 i detta test.
- Fixen passerar 00.07, 00.22, 01.37, 04.07, 04.14, 04.15 och 04.22.
  Gamla datum återhämtas inte, gårdagen stängs vid rätt gräns och originalets
  dagliga energikatalog är oförändrad.
- Feltest verifierar datum/steg och att undantagets känsliga text utelämnas.
- 220 tester passerade i ARM64-byggmiljön. OCI-arkivets checksummor,
  arkitektur, användare och 22 källfiler verifierades.

En hel natt i produktion är ännu inte verifierad. Efterföljande natt ska
kontrolleras för lyckade kvartskörningar 00.00–04.30, inga nya nattfel och
normal stängning av gårdagen vid 04.22. Larm ska inte tystas för att uppfylla
detta kriterium.

GitOps-ändring `addb533` applicerades av Flux den 25 november. Första ordinarie
körningen `analytics-collect-features-29927407` använde den nya digesten och
slutfördes med `success`, 54 GET och publicerat datum 2026-11-25.
Körningens starttid var 23.07 CET; ny generation blev
`c4dc29898c664dd791f479e86adbe025`. Detta verifierar skarp publicering efter
driftsättningen, men ersätter inte nattkontrollen ovan.

De tre gamla terminala feljobben har metadata och nio poddloggar arkiverade i
Analytics-arbetsytans `work/feature-retention-fix-2026-11-25/`.
Avgränsad städning finns i `scripts/cleanup-analytics-nightly-failures-20261125.sh`,
med namn/UID-kontroll och krav på lyckad ersättningskörning med rätt image.

Återgång: återställ den tidigare huvudcontainer-digesten
`sha256:042b7446a1433c40f96f9104fc438dbd5a026c5b890d92d4d67ce81a497ec80d`
i just CronJob `analytics-collect-features`, via Git/Flux. Ingen datamigrering.
