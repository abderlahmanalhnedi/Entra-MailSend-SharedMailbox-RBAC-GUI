# Entra Mail.Send – Shared Mailbox RBAC Tool

**Sprache / Language:** 🇩🇪 Deutsch · [🇬🇧 English](README_EN.md)

![PowerShell](https://img.shields.io/badge/PowerShell-7.4%2B-5391FE?logo=powershell&logoColor=white)
![Avalonia](https://img.shields.io/badge/Avalonia-Cross--Platform%20GUI-7B2BF9)
![Windows GUI](https://img.shields.io/badge/Windows-GUI-0078D6?logo=windows&logoColor=white)
![macOS](https://img.shields.io/badge/macOS-GUI-000000?logo=apple&logoColor=white)
![Linux](https://img.shields.io/badge/Linux-GUI-FCC624?logo=linux&logoColor=black)
![Exchange Online](https://img.shields.io/badge/Exchange%20Online-RBAC%20for%20Applications-0078D4)

Ein Admin-Tool, um einer **Microsoft Entra Enterprise Application** die Exchange-Online-Rolle **`Application Mail.Send`** gezielt für **eine einzelne Shared Mailbox** zuzuweisen.

Die neue **Cross-Platform GUI (Avalonia)** läuft unter Windows, macOS und Linux, bietet **Deutsch/English direkt in der Oberfläche** und führt den Administrator in drei klaren Schritten durch Anmeldung, Konfiguration und Prüfung.

> [!IMPORTANT]
> Für eine wirksame Einschränkung darf dieselbe App **nicht zusätzlich tenantweit** über Microsoft Entra mit **Microsoft Graph → `Mail.Send (Application)`** berechtigt sein. Entra-Berechtigungen und Exchange Application RBAC wirken additiv.

## Screenshots

### macOS – Cross-Platform GUI

![Entra Mail.Send Shared Mailbox RBAC GUI auf macOS](docs/images/entra-mail-send-rbac-gui-macos.png)

### Windows – PowerShell GUI

![Entra Mail.Send Shared Mailbox RBAC GUI unter Windows](docs/images/entra-mail-send-rbac-gui.png)

> Die Screenshots zeigen noch die vorherige Oberfläche. Die aktuelle Cross-Platform GUI wurde inzwischen als übersichtlicher 3-Schritte-Workflow neu gestaltet.

## Anmeldung

Die Cross-Platform GUI verwendet nur noch die normale **Microsoft-Anmeldung**:

- Admin-Konto eintragen
- **Mit Microsoft anmelden** auswählen
- Microsoft öffnet den eigenen Anmeldeprozess
- MFA, Passkeys und Conditional Access bleiben vollständig erhalten

Es gibt in der normalen Oberfläche keinen Device-Code-Button mehr.

## Sprache

Oben rechts kann direkt zwischen **Deutsch** und **English** gewechselt werden. Die Auswahl gilt auch für Status- und Fehlermeldungen des Exchange-Backends.

## Voraussetzungen

- Windows, macOS oder Linux
- **.NET 10 SDK**
- **PowerShell 7.4 oder neuer** (`pwsh` im `PATH`)
- vorhandene Microsoft Entra App / Enterprise Application
- vorhandene Shared Mailbox in Exchange Online
- Exchange Administrator
- Berechtigung zum Zuweisen von Exchange Application RBAC Rollen

## Start – macOS

```powershell
pwsh ./CrossPlatformGUI/scripts/run-source.ps1
```

## Start – Windows

```powershell
pwsh .\CrossPlatformGUI\scripts\run-source.ps1
```

## Bedienung der GUI

1. Optional **Deutsch** oder **English** auswählen.
2. Admin-Konto eintragen und **Mit Microsoft anmelden** auswählen.
3. Application (Client) ID eintragen.
4. Enterprise App Object ID eintragen.
5. Shared Mailbox eintragen.
6. Sicherheitsbestätigung aktivieren.
7. **Zugriff einrichten** auswählen.
8. Das Tool führt anschließend automatisch einen Zugriffstest aus.
9. Technische Details sind standardmäßig eingeklappt und können bei Bedarf geöffnet werden.

## Benötigte IDs

### Application (Client) ID

Die Application ID der Entra App bzw. Enterprise Application.

### Enterprise App Object ID

Benötigt wird die Object ID des **Service Principals / der Enterprise Application**.

> [!WARNING]
> Nicht die Object ID unter **App registrations** verwenden. Benötigt wird die Object ID unter **Entra ID → Enterprise applications → Anwendung**.

## Was macht das Tool?

- prüft bzw. installiert `ExchangeOnlineManagement`
- verbindet sich mit `Connect-ExchangeOnline`
- verwendet Microsoft Modern Authentication / MFA / Conditional Access
- fragt kein Admin-Passwort ab
- prüft, ob die angegebene Mailbox eine Shared Mailbox ist
- erstellt bei Bedarf den Exchange-Verweis auf den Entra Service Principal
- erstellt einen Management Scope für genau diese Shared Mailbox
- weist `Application Mail.Send` auf diesen Scope zu
- prüft die Autorisierung mit `Test-ServicePrincipalAuthorization`
- erkennt zusätzliche Exchange-RBAC-Zuweisungen, die den vorgesehenen Mail.Send-Scope erweitern könnten

## Sicherheit

Das Tool speichert keine Admin-Kennwörter, Client Secrets oder OAuth-Tokens. Die Anmeldung erfolgt vollständig über Microsoft.

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

## Microsoft-Dokumentation

- [Role Based Access Control for Applications in Exchange Online](https://learn.microsoft.com/en-us/exchange/permissions-exo/application-rbac)
- [Connect-ExchangeOnline](https://learn.microsoft.com/en-us/powershell/module/exchangepowershell/connect-exchangeonline)
- [Test-ServicePrincipalAuthorization](https://learn.microsoft.com/en-us/powershell/module/exchangepowershell/test-serviceprincipalauthorization)

## Disclaimer

Dieses Projekt ist kein offizielles Microsoft-Produkt. Verwendung auf eigene Verantwortung. Änderungen an produktiven Exchange-/Entra-Berechtigungen sollten vorab getestet und nach dem Least-Privilege-Prinzip geprüft werden.
