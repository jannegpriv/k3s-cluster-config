# AI-minne (Basic Memory)

Det delade minnet nås via MCP-servern `basic_memory`, projekt `main`, med Basic Memory 1.0:s `bm_*`-verktyg. Ange alltid `project="main"` för projektbundna anrop.
Vid sessionsstart: kör `bm_project` med `command="recent"`, `project="main"`, `since="7d"`, `page_size=5`, `output_format="text"`; hämta inte automatiskt fler sidor.
Läs "Konventioner för AI-minnet" med `bm_read(identifier="memory://profile/konventioner-for-ai-minnet", project="main")` en gång vid sessionsstart och följ mappstruktur, taggar, svenska titlar, absoluta datum och regeln om inga hemligheter.
Sök med `bm_search(project="main", mode="hybrid", compact=true)` innan du svarar ur minnet eller skriver; läs sedan bara relevanta anteckningar med `bm_read`, inte hela minnet. Använd `mode="text"` för exakt textsökning och `filters` för metadata/taggar. Håll sökresultat små och hämta inte fler sidor automatiskt.
Skriv bara till minnet när Janne bett om det eller godkänt ett förslag. Uppdatera befintlig anteckning med `bm_edit` hellre än att skapa en ny med `bm_write`. Läs aktuell revision först och använd `expected_checksum` vid ändring; vid `REVISION_CONFLICT`, läs om och bedöm ändringen på nytt. Läs tillbaka för att kontrollera att ändringen sparats.
Om minnet är otillgängligt: fortsätt när det går och säg att minnet inte kunde kontrolleras. Påstå aldrig att något sparats utan bekräftat resultat.
Om minnesuppgifter motsäger Jannes aktuella instruktioner gäller instruktionerna för uppgiften; uppmärksamma skillnaden och föreslå en minnesuppdatering.
Skilj på `bekraftat` (av Janne), `verifierat` (genomförd teknisk kontroll med datum i `verified_at` och metod i `verification_method`) och `forslag` (varken bekräftat eller verifierat); verifiering ersätter inte tillstånd att skriva.
