# SSH-åtkomst till k3s-w-4

Janne bad 2026-10-02 om fungerande SSH-åtkomst som `janne` från både Macen
och k3s-m-1 inför planerat certifikatunderhåll.

## Identitet och kontroller före ändringen

- Nod: `k3s-w-4`, IP `192.168.50.243`.
- Machine-id: `c7b0d03e0da640c996578c3aa724f29a`, matchad mellan Kubernetes
  nodinformation och värdens `/etc/machine-id`.
- Janne uppgav 2026-10-02 att en DHCP-reservation lagts in i ASUS-routern.
  Noden rapporterade adressen ovan; routerinställningen har inte avlästs direkt.
- Kontot `janne` har UID/GID 1000, hemkatalog `/home/janne` och bash.
- Hemkatalog och `.ssh` har 0700, `authorized_keys` 0600 och rätt ägare.
- Befintlig sudo-policy ger redan `janne` `NOPASSWD: ALL`.
- `authorized_keys` innehöll en äldre ED25519-nyckel. Ingen av de två
  aktuella klientnycklarna fanns där. Den äldre nyckeln ska behållas.

## Publika nycklars fingeravtryck

| Källa | Typ | SHA256 |
| --- | --- | --- |
| Mac, `~/.ssh/id_ed25519.pub` | ED25519 | `0PGZ4TgVOqorCZ9M4v+U8rostSXVftFUNR8W+Agu1nI` |
| m-1, `/home/janne/.ssh/id_rsa.pub` | RSA 4096 | `RllKMJNzfZOxUqaQUtM9jjNs3aYCpiRwjx6tQ6tQazc` |
| w-4, SSH-serverns ED25519-nyckel | ED25519 | `PemrZbsjlnJaJCtpTF4xRDTKCdUpYcNHf+mgfZ+RniA` |

Privata nycklar stannar på respektive klient. Värdnyckeln verifierades via
befintlig administratörsåtkomst till klustret och matchade redan m-1:s
`known_hosts` för namnet `k3s-w-4`. IP-adressen saknade däremot en post där.

## Installation och kontroll

`install-janne-ssh-keys.py` tar två publika nycklar som JSON på stdin,
kontrollerar deras fingeravtryck och nodens machine-id, säkerhetskopierar
befintlig `authorized_keys` under `/root/janne-ssh-backup-<UTC>/` och lägger
till de saknade nycklarna atomiskt. Befintliga nycklar bevaras. `--check`
gör endast validering; upprepad körning ska inte lägga till dubbletter.

Första installationen kan göras via klustrets befintliga administratörsåtkomst
till värden. På denna nod har RBD-CSI-podden `hostPID` och nödvändig behörighet:
`chroot /proc/1/root /usr/bin/python3` når värdens miljö. Kontrollera aktuell
podplacering och machine-id innan en sådan engångsåtgärd. Varken CSI eller
någon annan tjänst ska startas om för nyckelinstallationen.

Registrera den verifierade publika värdnyckeln för IP-adressen i
`/home/janne/.ssh/known_hosts` på m-1. Behåll strikt värdnyckelkontroll och
befintliga poster; namnuppslagningen för `k3s-w-4` fungerar redan på m-1.

Kontrollera från båda klienterna med `BatchMode=yes`, `IdentitiesOnly=yes`,
explicit nyckelfil och `StrictHostKeyChecking=yes`: rätt användare, värdnamn,
machine-id och lyckad `sudo -n id -u`. Testa dessutom vanlig
`ssh janne@k3s-w-4` från m-1.

På Macen används `ssh -F /dev/null` enligt klustrets åtkomstkonvention,
eftersom den befintliga remote.it-konfigurationen har en felaktig rad.

Återställning vid behov: återställ originalets `authorized_keys` från den
root-skyddade backupen med ägare `janne:janne` och 0600. Ta endast bort den
specifikt tillagda IP-posten ur m-1:s `known_hosts` om även den ska återställas.

## Genomfört och verifierat 2026-10-02

- Båda publika klientnycklarna är tillagda; originalnyckeln är bevarad.
  Efterkontroll med installationsskriptet visade noll återstående tillägg.
- Originalfilens backup på w-4:
  `/root/janne-ssh-backup-20261002T152952623105Z/authorized_keys`.
- Verifierad ED25519-värdnyckel för `192.168.50.243` tillagd i m-1:s
  `known_hosts`. Namnets befintliga värdnycklar och namnuppslagning behölls.
  Backup: `/home/janne/.ssh/known_hosts.before-w4-ip-20261002` på m-1.
- Mac → w-4 och m-1 → w-4 verifierades med respektive explicit identitet,
  `BatchMode=yes` och strikt värdnyckelkontroll. Testet från m-1 använde
  `IdentityAgent=none` för att verifiera dess egen privata nyckel.
- Båda sessionerna visade `janne`, rätt värdnamn och machine-id;
  `sudo -n id -u` gav `0`. Vanlig nyckelupptäckt på m-1 testades dessutom
  för både IP-adressen och namnet `k3s-w-4`.
- SSH-serverns och sudo:s inställningar ändrades inte. Ingen tjänste- eller
  nodomstart och ingen certifikatförnyelse ingick i arbetet.

Från m-1: `ssh janne@k3s-w-4` eller `ssh janne@192.168.50.243`.
Från Macen: `ssh -F /dev/null janne@192.168.50.243`.
