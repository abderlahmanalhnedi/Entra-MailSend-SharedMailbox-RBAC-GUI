# Entra Mail.Send – Shared Mailbox RBAC Tool

![PowerShell](https://img.shields.io/badge/PowerShell-7.4%2B-5391FE?logo=powershell&logoColor=white)
![Windows GUI](https://img.shields.io/badge/GUI-Windows-0078D6?logo=windows&logoColor=white)
![Cross Platform CLI](https://img.shields.io/badge/CLI-Windows%20%7C%20macOS%20%7C%20Linux-2ea44f)
![Exchange Online](https://img.shields.io/badge/Exchange%20Online-RBAC%20for%20Applications-0078D4)

Ein kleines Admin-Tool, um einer **Microsoft Entra Enterprise Application** die Exchange-Online-Rolle **`Application Mail.Send`** gezielt für **eine einzelne Shared Mailbox** zuzuweisen.

Das Repository enthält zwei Varianten:

- **Windows GUI** für eine möglichst einfache Bedienung per Oberfläche
- **Cross-Platform CLI** für Windows, macOS und Linux

Beide Varianten verwenden **Exchange Online RBAC for Applications** und fragen **kein Admin-Passwort** im Skript ab.

> [!IMPORTANT]
> Für eine wirksame Einschränkung darf dieselbe App **nicht zusätzlich tenantweit** über Microsoft Entra mit **Microsoft Graph → `Mail.Send (Application)`** berechtigt sein. Entra-Berechtigungen und Exchange Application RBAC wirken additiv.

## Screenshot – Windows GUI

![Entra Mail.Send Shared Mailbox RBAC GUI](docs/images/entra-mail-send-rbac-gui.png)

## Varianten

| Datei | Plattform | PowerShell | Bedienung |
|---|---|---:|---|
| `Entra-MailSend-SharedMailbox-RBAC-GUI.ps1` | Windows | Windows PowerShell 5.1 oder PowerShell 7 | Grafische Oberfläche |
| `Entra-MailSend-SharedMailbox-RBAC-CLI.ps1` | Windows, macOS, Linux | PowerShell 7.4+ | Interaktives Terminal-Menü |

## Was macht das Tool?

Das Tool übernimmt die benötigten Exchange-Schritte und führt den Administrator durch die Einrichtung:

- prüft bzw. installiert `ExchangeOnlineManagement`
- verbindet sich per `Connect-ExchangeOnline`
- verwendet Microsoft Modern Authentication / MFA / Conditional Access
- fragt **kein Admin-Passwort** im Skript ab
- prüft, ob die angegebene Mailbox eine Shared Mailbox ist
- erstellt bei Bedarf den Exchange-Verweis auf den Entra Service Principal
- erstellt einen Management Scope für genau diese Shared Mailbox
- weist `Application Mail.Send` auf diesen Scope zu
- prüft die Autorisierung mit `Test-ServicePrincipalAuthorization`
- warnt vor zusätzlichen Exchange-RBAC-Zuweisungen, die den Mail.Send-Scope erweitern könnten

## Architektur

```text
Microsoft Entra Enterprise Application
                 │
                 ▼
       Exchange Service Principal
                 │
                 ▼
        Application Mail.Send
                 │
                 ▼
          Management Scope
                 │
                 ▼
        eine Shared Mailbox
```

## Voraussetzungen

- vorhandene Microsoft Entra App / Enterprise Application
- vorhandene Shared Mailbox in Exchange Online
- Internetzugriff auf Microsoft 365 und ggf. PowerShell Gallery
- **Exchange Administrator** in Microsoft Entra ID
- Berechtigung zum Zuweisen der Application-RBAC-Rolle; standardmäßig verfügt die Exchange-Rollengruppe **Organization Management** über die delegierende Zuweisung

### Für die CLI-Version

- PowerShell **7.4 oder neuer**
- Windows, macOS oder unterstütztes Linux

Das Skript berücksichtigt die Kompatibilität des Exchange-Online-Moduls:

- PowerShell 7.6+ → aktuelle `ExchangeOnlineManagement`-Version
- PowerShell 7.4 / 7.5 → kompatible Modulversion `3.9.2`

## Schnellstart – Windows GUI

Repository herunterladen bzw. klonen und anschließend in PowerShell ausführen:

```powershell
.\Entra-MailSend-SharedMailbox-RBAC-GUI.ps1
```

Falls die lokale Execution Policy die Ausführung blockiert, kann nur für die aktuelle Sitzung beispielsweise Folgendes verwendet werden:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\Entra-MailSend-SharedMailbox-RBAC-GUI.ps1
```

> [!NOTE]
> Eine systemweite Änderung der Execution Policy ist für dieses Tool nicht erforderlich.

## Schnellstart – macOS / Linux / Windows CLI

PowerShell 7 starten und in den Repository-Ordner wechseln.

### macOS / Linux

```powershell
./Entra-MailSend-SharedMailbox-RBAC-CLI.ps1
```

### Windows mit PowerShell 7

```powershell
.\Entra-MailSend-SharedMailbox-RBAC-CLI.ps1
```

Danach erscheint ein einfaches Menü:

```text
============================================================
 Entra Mail.Send - Shared Mailbox RBAC CLI
 Windows | macOS | Linux
============================================================

[1] Mit Exchange Online verbinden
[2] App- und Mailbox-Daten eingeben
[3] Zugriff einrichten
[4] Zugriff testen
[5] Aktuelle Eingaben anzeigen
[6] Verbindung trennen
[0] Beenden
```

## Benötigte Daten

### Admin-Konto

Beispiel:

```text
admin@contoso.com
```

Die Anmeldung erfolgt über Microsoft. Passwort, MFA, Passkey oder andere Anmeldeverfahren werden nicht vom Skript verarbeitet.

### Application (Client) ID

Die Application ID der Entra App.

### Enterprise App Object ID

Die Object ID des **Service Principals / der Enterprise Application**.

> [!WARNING]
> Nicht die Object ID unter **App registrations** verwenden. Benötigt wird die Object ID unter **Entra ID → Enterprise applications → Anwendung**.

### Shared Mailbox

Beispiel:

```text
noreply@contoso.com
```

## Sicherheitsbestätigung

Vor der Konfiguration muss bestätigt werden, dass für die App kein tenantweites:

```text
Microsoft Graph → Mail.Send (Application)
```

in Entra aktiv ist.

Der Grund: Exchange Application RBAC und separat in Microsoft Entra vergebene Application Permissions werden bei der effektiven Berechtigung zusammengeführt.

## Zugriff testen

Das Tool verwendet:

```powershell
Test-ServicePrincipalAuthorization
```

Ein erfolgreicher Test zeigt sinngemäß:

```text
GRANTED: Application Mail.Send ist fuer sharedmailbox@contoso.com im erwarteten Scope.
```

> [!NOTE]
> `Test-ServicePrincipalAuthorization` prüft Exchange Application RBAC. Separat in Entra erteilte tenantweite API Permissions werden dadurch nicht ausgeschlossen und müssen separat geprüft werden.

## Sicherheit

Das Tool wurde bewusst so aufgebaut, dass sensible Anmeldedaten nicht selbst verarbeitet werden.

- kein Passwortfeld
- keine Speicherung von Admin-Kennwörtern
- keine Speicherung von Client Secrets
- keine Speicherung von OAuth-Tokens
- Anmeldung über `Connect-ExchangeOnline`
- MFA / Passkeys / Conditional Access bleiben im Microsoft-Anmeldeprozess

Vor produktivem Einsatz sollte die Konfiguration trotzdem zuerst mit einer Test-App und Test-Shared-Mailbox geprüft werden.

## Warum Exchange Online RBAC for Applications?

Exchange Online RBAC for Applications ermöglicht Application Permissions mit einem Exchange-Ressourcenbereich. Dadurch kann eine App beispielsweise `Mail.Send` erhalten, ohne diese Berechtigung für alle Mailboxen der Organisation zu bekommen.

Microsoft empfiehlt diese Methode gegenüber den älteren **Application Access Policies** für neue Implementierungen.

## Was das Tool nicht macht

Das Tool:

- erstellt keine neue Entra App
- erstellt kein Client Secret oder Zertifikat
- konfiguriert keine Anwendung, die Microsoft Graph aufruft
- entfernt vorhandene Entra API Permissions nicht automatisch
- löscht bestehende Exchange-RBAC-Konfigurationen nicht automatisch

Damit bleiben sicherheitsrelevante Änderungen außerhalb des gewünschten Mailbox-Scopes bewusst unter administrativer Kontrolle.

## Fehlerbehebung

### macOS: Skript wird nicht gefunden

PowerShell führt Dateien aus dem aktuellen Verzeichnis nicht automatisch aus. Deshalb mit `./` starten:

```powershell
./Entra-MailSend-SharedMailbox-RBAC-CLI.ps1
```

### ExchangeOnlineManagement fehlt

Die CLI bietet die Installation für den aktuellen Benutzer automatisch an.

Alternativ:

```powershell
Install-Module ExchangeOnlineManagement -Scope CurrentUser
```

### Standard-Anmeldung funktioniert nicht

Die CLI bietet nach einem fehlgeschlagenen normalen Login optional eine **Device-Code-Anmeldung** an. Auch dabei werden Kennwort und MFA ausschließlich von Microsoft verarbeitet.

### Falsche Enterprise App Object ID

Die Object ID muss von der **Enterprise Application / dem Service Principal** stammen, nicht von der App-Registrierung.

### Zugriff funktioniert außerhalb der Shared Mailbox

Prüfen, ob:

- in Entra weiterhin `Mail.Send (Application)` tenantweit erteilt ist
- eine weitere Exchange-RBAC-Zuweisung mit `Application Mail.Send`, `Application Mail Full Access` oder `Application Exchange Full Access` existiert

### Änderungen wirken noch nicht in der Anwendung

Microsoft weist darauf hin, dass Änderungen an Application-RBAC-Berechtigungen durch Caching verzögert wirksam werden können. `Test-ServicePrincipalAuthorization` umgeht diesen Cache beim Test.

## Repository-Struktur

```text
Entra-MailSend-SharedMailbox-RBAC-GUI/
│
├── Entra-MailSend-SharedMailbox-RBAC-GUI.ps1
├── Entra-MailSend-SharedMailbox-RBAC-CLI.ps1
├── README.md
└── docs/
    └── images/
        └── entra-mail-send-rbac-gui.png
```

## Microsoft-Dokumentation

- [Role Based Access Control for Applications in Exchange Online](https://learn.microsoft.com/en-us/exchange/permissions-exo/application-rbac)
- [Connect-ExchangeOnline](https://learn.microsoft.com/en-us/powershell/module/exchangepowershell/connect-exchangeonline)
- [Test-ServicePrincipalAuthorization](https://learn.microsoft.com/en-us/powershell/module/exchangepowershell/test-serviceprincipalauthorization)
- [About the Exchange Online PowerShell module](https://learn.microsoft.com/en-us/powershell/exchange/exchange-online-powershell-v2)

## Disclaimer

Dieses Projekt ist kein offizielles Microsoft-Produkt. Verwendung auf eigene Verantwortung. Änderungen an produktiven Exchange-/Entra-Berechtigungen sollten vorab getestet und nach dem Least-Privilege-Prinzip geprüft werden.
