# Entra Mail.Send – Shared Mailbox RBAC Tool

![PowerShell](https://img.shields.io/badge/PowerShell-7.4%2B-5391FE?logo=powershell&logoColor=white)
![Avalonia](https://img.shields.io/badge/Avalonia-Cross--Platform%20GUI-7B2BF9)
![Windows GUI](https://img.shields.io/badge/Windows-GUI-0078D6?logo=windows&logoColor=white)
![macOS](https://img.shields.io/badge/macOS-GUI-000000?logo=apple&logoColor=white)
![Linux](https://img.shields.io/badge/Linux-GUI-FCC624?logo=linux&logoColor=black)
![Exchange Online](https://img.shields.io/badge/Exchange%20Online-RBAC%20for%20Applications-0078D4)

Ein Admin-Tool, um einer **Microsoft Entra Enterprise Application** die Exchange-Online-Rolle **`Application Mail.Send`** gezielt für **eine einzelne Shared Mailbox** zuzuweisen.

Das Repository enthält drei Varianten:

- **Cross-Platform GUI (Avalonia)** – Windows, macOS und Linux
- **Windows PowerShell GUI** – klassische Windows Forms Oberfläche
- **Cross-Platform CLI** – PowerShell-Menü für Windows, macOS und Linux

Alle Varianten verwenden **Exchange Online RBAC for Applications**. Das Admin-Kennwort wird vom Tool **nicht abgefragt oder gespeichert**.

> [!IMPORTANT]
> Für eine wirksame Einschränkung darf dieselbe App **nicht zusätzlich tenantweit** über Microsoft Entra mit **Microsoft Graph → `Mail.Send (Application)`** berechtigt sein. Entra-Berechtigungen und Exchange Application RBAC wirken additiv.

## Screenshot – Windows GUI

![Entra Mail.Send Shared Mailbox RBAC GUI](docs/images/entra-mail-send-rbac-gui.png)

## Varianten

| Variante | Plattform | Start |
|---|---|---|
| **Cross-Platform GUI (Avalonia)** | Windows, macOS, Linux | `pwsh ./CrossPlatformGUI/scripts/run-source.ps1` |
| **Windows GUI** | Windows | `.\Entra-MailSend-SharedMailbox-RBAC-GUI.ps1` |
| **Cross-Platform CLI** | Windows, macOS, Linux | `./Entra-MailSend-SharedMailbox-RBAC-CLI.ps1` |

## Was macht das Tool?

Das Tool übernimmt die benötigten Exchange-Schritte und führt den Administrator durch die Einrichtung:

- prüft bzw. installiert `ExchangeOnlineManagement`
- verbindet sich mit `Connect-ExchangeOnline`
- verwendet Microsoft Modern Authentication / MFA / Conditional Access
- fragt **kein Admin-Passwort** ab
- prüft, ob die angegebene Mailbox eine Shared Mailbox ist
- erstellt bei Bedarf den Exchange-Verweis auf den Entra Service Principal
- erstellt einen Management Scope für genau diese Shared Mailbox
- weist `Application Mail.Send` auf diesen Scope zu
- prüft die Autorisierung mit `Test-ServicePrincipalAuthorization`
- erkennt zusätzliche Exchange-RBAC-Zuweisungen, die den vorgesehenen Mail.Send-Scope erweitern könnten

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

Die neue Cross-Platform GUI verwendet zusätzlich folgende lokale Architektur:

```text
Avalonia GUI (.NET 8)
        │
        ▼
persistenter PowerShell-7-Worker
        │
        ▼
ExchangeOnlineManagement
        │
        ▼
Exchange Online RBAC
```

Der PowerShell-Worker bleibt während der Sitzung aktiv, damit die Exchange-Online-Verbindung zwischen den GUI-Aktionen erhalten bleibt.

## Voraussetzungen

### Allgemein

- vorhandene Microsoft Entra App / Enterprise Application
- vorhandene Shared Mailbox in Exchange Online
- Internetzugriff auf Microsoft 365 und ggf. PowerShell Gallery
- **Exchange Administrator** in Microsoft Entra ID
- Berechtigung zum Zuweisen der Exchange Application RBAC Rollen

### Cross-Platform GUI

- Windows, macOS oder Linux
- **.NET 8 SDK oder neuer**
- **PowerShell 7.4 oder neuer** (`pwsh` im `PATH`)

Microsoft unterstützt das Exchange-Online-PowerShell-Modul offiziell unter Windows, macOS und Linux mit PowerShell 7. Für neuere Modulversionen gelten passende PowerShell-Versionen; das Backend berücksichtigt diese Zuordnung.

## Schnellstart – Cross-Platform GUI auf macOS

### 1. Voraussetzungen prüfen

```powershell
pwsh --version
dotnet --version
```

### 2. GUI starten

Im Repository:

```powershell
pwsh ./CrossPlatformGUI/scripts/run-source.ps1
```

Oder direkt:

```bash
dotnet run --project CrossPlatformGUI/EntraMailSendRbac.Gui/EntraMailSendRbac.Gui.csproj
```

Danach öffnet sich eine echte Desktop-GUI auf macOS.

### 3. Lokale macOS `.app` bauen

```bash
chmod +x ./CrossPlatformGUI/scripts/build-macos-app.sh
./CrossPlatformGUI/scripts/build-macos-app.sh
```

Die fertige App liegt anschließend unter:

```text
CrossPlatformGUI/dist/Entra MailSend RBAC.app
```

> [!NOTE]
> Der lokale Build ist nicht mit einem Apple-Developer-Zertifikat signiert oder notarisiert. Für eine öffentliche Verteilung sollte Codesigning und Notarisierung ergänzt werden.

## Schnellstart – Windows GUI

```powershell
.\Entra-MailSend-SharedMailbox-RBAC-GUI.ps1
```

Falls die lokale Execution Policy die Ausführung blockiert, kann nur für die aktuelle Sitzung beispielsweise Folgendes verwendet werden:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\Entra-MailSend-SharedMailbox-RBAC-GUI.ps1
```

## Schnellstart – CLI

### macOS / Linux

```powershell
./Entra-MailSend-SharedMailbox-RBAC-CLI.ps1
```

### Windows

```powershell
.\Entra-MailSend-SharedMailbox-RBAC-CLI.ps1
```

## Bedienung der GUI

1. **Admin-Konto** eintragen.
2. **Microsoft Login** auswählen. Falls Browser-SSO nicht funktioniert, **Device Code** verwenden.
3. **Application (Client) ID** eintragen.
4. **Enterprise App Object ID** eintragen.
5. **Shared Mailbox** eintragen.
6. Sicherheitsbestätigung aktivieren.
7. **Zugriff einrichten** auswählen.
8. Das Tool führt anschließend automatisch einen Zugriffstest aus.

## Benötigte IDs

### Application (Client) ID

Die Application ID der Entra App bzw. Enterprise Application.

### Enterprise App Object ID

Benötigt wird die Object ID des **Service Principals / der Enterprise Application**.

> [!WARNING]
> Nicht die Object ID unter **App registrations** verwenden. Benötigt wird die Object ID unter **Entra ID → Enterprise applications → Anwendung**.

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
GRANTED: Application Mail.Send ist für sharedmailbox@contoso.com im erwarteten Scope.
```

> [!NOTE]
> `Test-ServicePrincipalAuthorization` prüft Exchange Application RBAC. Separat in Entra erteilte tenantweite API Permissions werden dadurch nicht ausgeschlossen und müssen separat geprüft werden.

## Sicherheit

Das Tool wurde bewusst so aufgebaut, dass sensible Anmeldedaten nicht selbst verarbeitet werden.

- kein Passwortfeld
- keine Speicherung von Admin-Kennwörtern
- keine Speicherung von Client Secrets
- keine Speicherung von OAuth-Tokens durch das Tool
- Anmeldung über `Connect-ExchangeOnline`
- MFA / Passkeys / Conditional Access bleiben im Microsoft-Anmeldeprozess

Vor produktivem Einsatz sollte die Konfiguration zuerst mit einer Test-App und Test-Shared-Mailbox geprüft werden.

## Warum Exchange Online RBAC for Applications?

Exchange Online RBAC for Applications ermöglicht Application Permissions mit einem Exchange-Ressourcenbereich. Dadurch kann eine App `Mail.Send` erhalten, ohne diese Berechtigung für alle Mailboxen der Organisation zu bekommen.

Für neue Implementierungen ist dies die modernere Alternative zu den älteren **Application Access Policies**.

## Was das Tool nicht macht

Das Tool:

- erstellt keine neue Entra App
- erstellt kein Client Secret oder Zertifikat
- konfiguriert nicht den eigentlichen Microsoft-Graph-Client der Anwendung
- entfernt vorhandene Entra API Permissions nicht automatisch
- löscht bestehende Exchange-RBAC-Konfigurationen nicht automatisch

Damit bleiben sicherheitsrelevante Änderungen außerhalb des gewünschten Mailbox-Scopes unter administrativer Kontrolle.

## Repository-Struktur

```text
Entra-MailSend-SharedMailbox-RBAC-GUI/
│
├── Entra-MailSend-SharedMailbox-RBAC-GUI.ps1
├── Entra-MailSend-SharedMailbox-RBAC-CLI.ps1
├── README.md
├── docs/
│   └── images/
│       └── entra-mail-send-rbac-gui.png
│
└── CrossPlatformGUI/
    ├── README.md
    ├── .gitignore
    ├── EntraMailSendRbac.Gui/
    │   ├── EntraMailSendRbac.Gui.csproj
    │   ├── Program.cs
    │   ├── App.axaml
    │   ├── App.axaml.cs
    │   ├── MainWindow.axaml
    │   ├── MainWindow.axaml.cs
    │   ├── PowerShellWorkerService.cs
    │   └── Backend/
    │       └── ExchangeWorker.ps1
    └── scripts/
        ├── run-source.ps1
        ├── build-macos-app.sh
        └── build-windows.ps1
```

## Fehlerbehebung

### `pwsh` wird von der GUI nicht gefunden

Prüfen:

```bash
which pwsh
pwsh --version
```

PowerShell 7 muss im `PATH` verfügbar sein.

### `.NET SDK wurde nicht gefunden`

Prüfen:

```bash
dotnet --version
```

Für die GUI wird .NET 8 SDK oder neuer benötigt.

### Microsoft Login öffnet sich nicht

In der Cross-Platform GUI kann alternativ **Device Code** gewählt werden.

### ExchangeOnlineManagement fehlt

Die Cross-Platform GUI prüft das Modul beim Start und installiert bei Bedarf eine kompatible Version für `CurrentUser`.

### Zugriff funktioniert außerhalb der Shared Mailbox

Prüfen, ob:

- in Entra weiterhin `Mail.Send (Application)` tenantweit erteilt ist
- eine weitere Exchange-RBAC-Zuweisung mit `Application Mail.Send`, `Application Mail Full Access` oder `Application Exchange Full Access` existiert

## Microsoft-Dokumentation

- [Role Based Access Control for Applications in Exchange Online](https://learn.microsoft.com/en-us/exchange/permissions-exo/application-rbac)
- [Connect-ExchangeOnline](https://learn.microsoft.com/en-us/powershell/module/exchangepowershell/connect-exchangeonline)
- [Test-ServicePrincipalAuthorization](https://learn.microsoft.com/en-us/powershell/module/exchangepowershell/test-serviceprincipalauthorization)
- [About the Exchange Online PowerShell module](https://learn.microsoft.com/en-us/powershell/exchange/exchange-online-powershell-v2)
- [Avalonia supported platforms](https://docs.avaloniaui.net/docs/supported-platforms)

## Disclaimer

Dieses Projekt ist kein offizielles Microsoft-Produkt. Verwendung auf eigene Verantwortung. Änderungen an produktiven Exchange-/Entra-Berechtigungen sollten vorab getestet und nach dem Least-Privilege-Prinzip geprüft werden.
