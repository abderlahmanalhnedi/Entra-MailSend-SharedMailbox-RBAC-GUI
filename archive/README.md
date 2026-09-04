# Entra Mail.Send – Shared Mailbox RBAC GUI

![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE?logo=powershell&logoColor=white)
![Platform](https://img.shields.io/badge/Platform-Windows-0078D6?logo=windows&logoColor=white)
![Exchange Online](https://img.shields.io/badge/Exchange%20Online-RBAC%20for%20Applications-0078D4)

Eine kleine Windows-GUI für Administratoren, um einer **Microsoft Entra Enterprise Application** die Exchange-Online-Rolle **`Application Mail.Send`** gezielt für **eine einzelne Shared Mailbox** zuzuweisen.

Das Tool verwendet **Exchange Online RBAC for Applications** und soll die Einrichtung so einfach machen, dass dafür keine tieferen PowerShell-Kenntnisse nötig sind.

> [!IMPORTANT]
> Für eine wirksame Einschränkung darf dieselbe App **nicht zusätzlich tenantweit** über Microsoft Entra mit **Microsoft Graph → `Mail.Send (Application)`** berechtigt sein. Entra-Berechtigungen und Exchange Application RBAC wirken additiv.

## Screenshot

![Entra Mail.Send Shared Mailbox RBAC GUI](docs/images/entra-mail-send-rbac-gui.png)

## Was macht das Tool?

Das Skript führt die benötigten Exchange-Schritte über eine grafische Oberfläche aus:

- prüft bzw. installiert das PowerShell-Modul `ExchangeOnlineManagement`
- verbindet sich per `Connect-ExchangeOnline`
- nutzt die Microsoft-Anmeldung mit Modern Authentication / MFA
- fragt **kein Admin-Passwort** im Skript ab
- prüft, ob die angegebene Mailbox eine Shared Mailbox ist
- erstellt bei Bedarf den Exchange-Verweis auf den Entra Service Principal
- erstellt einen Management Scope für genau diese Shared Mailbox
- weist die Rolle `Application Mail.Send` auf diesen Scope zu
- prüft die resultierende Exchange-RBAC-Autorisierung mit `Test-ServicePrincipalAuthorization`
- erkennt zusätzliche Exchange-RBAC-Zuweisungen mit Mail.Send, die den vorgesehenen Scope erweitern könnten

## Funktionsweise

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

- Windows
- Windows PowerShell 5.1 oder PowerShell 7
- Internetzugriff auf Microsoft 365 und ggf. PowerShell Gallery
- vorhandene Microsoft Entra App / Enterprise Application
- vorhandene Shared Mailbox in Exchange Online
- administratives Konto mit den erforderlichen Exchange-Berechtigungen

Microsoft nennt für das Einrichten von Application RBAC unter anderem:

- **Exchange Administrator** in Microsoft Entra ID
- die erforderliche delegierende Exchange-RBAC-Berechtigung; standardmäßig besitzt die Rollengruppe **Organization Management** die Delegierung für die Application-RBAC-Rollen

## Schnellstart

### 1. Skript starten

Repository herunterladen oder klonen und anschließend ausführen:

```powershell
.\Entra-MailSend-SharedMailbox-RBAC-GUI.ps1
```

Falls die lokale Execution Policy die Ausführung blockiert, kann für die aktuelle PowerShell-Sitzung beispielsweise Folgendes verwendet werden:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\Entra-MailSend-SharedMailbox-RBAC-GUI.ps1
```

> [!NOTE]
> Eine Änderung der systemweiten Execution Policy ist für dieses Tool nicht erforderlich.

### 2. Admin-Konto eintragen

Beispiel:

```text
admin@contoso.com
```

Danach **„Mit Exchange Online verbinden“** auswählen. Passwort, MFA, Passkey oder andere Anmeldeverfahren werden ausschließlich über den Microsoft-Anmeldedialog verarbeitet.

### 3. App-Daten eintragen

Benötigt werden:

**Application (Client) ID**  
Die Application ID der Entra App.

**Enterprise App Object ID**  
Die Object ID des **Service Principals / der Enterprise Application**.

> [!WARNING]
> Für die Object ID nicht die Object ID aus **App registrations** verwenden. Benötigt wird die Object ID unter **Entra ID → Enterprise applications → Anwendung**.

### 4. Shared Mailbox eintragen

Beispiel:

```text
noreply@contoso.com
```

### 5. Sicherheitsbestätigung setzen

Vor der Einrichtung muss bestätigt werden, dass für diese App kein tenantweites:

```text
Microsoft Graph → Mail.Send (Application)
```

in Entra vergeben ist.

### 6. Zugriff einrichten

Auf **„Zugriff einrichten“** klicken.

Das Tool erstellt bzw. prüft anschließend automatisch:

```text
Service Principal
      ↓
Management Scope
      ↓
Application Mail.Send Role Assignment
      ↓
Shared Mailbox
```

### 7. Zugriff testen

Mit **„Zugriff testen“** wird die Exchange-RBAC-Zuweisung geprüft.

Ein erfolgreicher Test wird im Statusfenster als `GRANTED` angezeigt.

## Sicherheit

Das Tool wurde bewusst so aufgebaut, dass sensible Anmeldedaten nicht selbst verarbeitet werden.

**Es gibt kein Passwortfeld.** Das Skript speichert keine Admin-Kennwörter, Client Secrets oder OAuth-Tokens. Die Anmeldung erfolgt über `Connect-ExchangeOnline` und damit über die von Microsoft bereitgestellte moderne Authentifizierung.

Trotzdem gilt: Vor produktivem Einsatz sollte das Skript in einer Testumgebung bzw. mit einer Test-App und Test-Mailbox geprüft werden.

## Warum Exchange Online RBAC for Applications?

Exchange Online RBAC for Applications ermöglicht die Zuweisung von Application Permissions mit einem Exchange-Ressourcenbereich. Dadurch kann eine App beispielsweise `Mail.Send` erhalten, ohne diese Berechtigung automatisch für alle Mailboxen der Organisation zu bekommen.

Microsoft beschreibt Application RBAC als Nachfolger der älteren **Application Access Policies**.

## Wichtiger Hinweis zu Entra API Permissions

Exchange Application RBAC und in Microsoft Entra vergebene Application Permissions sind voneinander unabhängig und werden bei der effektiven Autorisierung zusammengeführt.

Wenn also dieselbe App zusätzlich tenantweit folgende Entra-Berechtigung besitzt:

```text
Microsoft Graph
└── Mail.Send (Application)
```

kann der Exchange-RBAC-Scope allein den Zugriff nicht wirksam auf die eine Shared Mailbox begrenzen.

Für einen ausschließlich per Exchange RBAC eingeschränkten `Mail.Send`-Zugriff muss die entsprechende organisationsweite Entra-Zuweisung daher entfernt bzw. nicht erteilt sein.

## Was das Tool nicht macht

Das Tool:

- erstellt keine neue Entra App
- erstellt kein Client Secret oder Zertifikat
- konfiguriert keine Anwendung, die Microsoft Graph aufruft
- entfernt keine vorhandenen Entra API Permissions automatisch
- löscht keine bestehenden Exchange-RBAC-Konfigurationen automatisch

Damit bleiben sicherheitsrelevante Änderungen außerhalb des gewünschten Mailbox-Scopes bewusst unter administrativer Kontrolle.

## Fehlerbehebung

### ExchangeOnlineManagement fehlt

Das Tool erkennt ein fehlendes Modul und bietet die Installation für den aktuellen Benutzer an.

Alternativ manuell:

```powershell
Install-Module ExchangeOnlineManagement -Scope CurrentUser
```

### Falsche Enterprise App Object ID

Die Object ID muss von der **Enterprise Application / dem Service Principal** stammen, nicht von der App-Registrierung.

### Zugriff funktioniert außerhalb der Shared Mailbox

Prüfen, ob in Entra weiterhin eine organisationsweite `Mail.Send (Application)`-Berechtigung oder eine weitere Exchange-RBAC-Zuweisung vorhanden ist.

### Test zeigt noch nicht das erwartete Verhalten

`Test-ServicePrincipalAuthorization` prüft die Exchange-RBAC-Zuweisung direkt. Änderungen an produktiven Autorisierungspfaden können zusätzlich durch Caching verzögert sichtbar werden.

## Microsoft-Dokumentation

- [Role Based Access Control for Applications in Exchange Online](https://learn.microsoft.com/en-us/exchange/permissions-exo/application-rbac)
- [Connect-ExchangeOnline](https://learn.microsoft.com/en-us/powershell/module/exchangepowershell/connect-exchangeonline)
- [Exchange Online PowerShell](https://learn.microsoft.com/en-us/powershell/exchange/connect-to-exchange-online-powershell)

## Hinweis

Dieses Projekt ist ein Administrationswerkzeug und sollte nur von Personen verwendet werden, die berechtigt sind, Änderungen an Microsoft Entra ID und Exchange Online der jeweiligen Organisation vorzunehmen.
