# Cross-Platform GUI (Avalonia)

**Sprache / Language:** 🇩🇪 Deutsch · [🇬🇧 English](README_EN.md)

Diese Variante stellt dieselbe Exchange-Online-RBAC-Funktionalität wie die PowerShell-GUI/CLI über eine echte Desktop-Oberfläche auf **Windows, macOS und Linux** bereit.

## Sprache

Die Oberfläche kann oben rechts direkt zwischen **Deutsch** und **English** umgeschaltet werden. Die Auswahl gilt auch für Status- und Fehlermeldungen des Exchange-Backends.

## Architektur

```text
Avalonia GUI (.NET 10)
        ↓
persistenter PowerShell-7-Worker
        ↓
ExchangeOnlineManagement
        ↓
Exchange Online RBAC for Applications
        ↓
Application Mail.Send → genau eine Shared Mailbox
```

Das Admin-Kennwort wird **nicht** von der Anwendung abgefragt oder gespeichert. Die Anmeldung erfolgt über `Connect-ExchangeOnline` und damit über Microsoft Modern Authentication / MFA / Conditional Access.

## Voraussetzungen

- .NET 10 SDK
- PowerShell 7.4 oder neuer (`pwsh` muss im `PATH` liegen)
- Internetzugriff auf Microsoft 365 und PowerShell Gallery
- Exchange Administrator
- Berechtigung zum Zuweisen von Exchange Application RBAC Rollen

`ExchangeOnlineManagement` wird beim Start geprüft und bei Bedarf für den aktuellen Benutzer installiert.

## Auf macOS direkt aus dem Quellcode starten

Im Repository:

```powershell
pwsh ./CrossPlatformGUI/scripts/run-source.ps1
```

Alternativ:

```bash
dotnet run --project CrossPlatformGUI/EntraMailSendRbac.Gui/EntraMailSendRbac.Gui.csproj
```

## macOS `.app` bauen

```bash
chmod +x ./CrossPlatformGUI/scripts/build-macos-app.sh
./CrossPlatformGUI/scripts/build-macos-app.sh
```

Danach liegt die App hier:

```text
CrossPlatformGUI/dist/Entra MailSend RBAC.app
```

Der Build ist für lokale Nutzung **nicht codesigniert/notarisiert**. Für eine öffentliche Verteilung sollte die App mit einem Apple-Developer-Zertifikat signiert und notarisiert werden.

## Windows Build

```powershell
pwsh ./CrossPlatformGUI/scripts/build-windows.ps1
```

Ausgabe:

```text
CrossPlatformGUI/dist/windows-x64/
```

## Bedienung

1. Admin-Konto eingeben.
2. **Microsoft Login** anklicken. Falls Browser-SSO nicht funktioniert, **Device Code** verwenden.
3. Application (Client) ID eintragen.
4. Object ID der **Enterprise Application** eintragen.
5. Shared Mailbox eintragen.
6. Sicherheitsbestätigung aktivieren.
7. **Zugriff einrichten** anklicken.
8. Die App führt anschließend automatisch einen RBAC-Test aus.

## Sicherheits-Hinweis

Damit die Begrenzung wirksam ist, darf dieselbe App nicht parallel die tenantweite Entra-Berechtigung

```text
Microsoft Graph → Mail.Send (Application)
```

besitzen. Entra API Permissions und Exchange Application RBAC wirken additiv.
